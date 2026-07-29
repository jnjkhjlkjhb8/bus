// Package shared holds process bootstrap helpers common to the router and
// functions binaries: Redis and PostgreSQL pool construction and small env
// parsing. Connection helpers panic on failure so a misconfigured process
// fails fast at startup rather than serving traffic without its backends.
package shared

import (
	"context"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
)

// ConnectRedis dials REDIS_ADDR with a fixed pool and verifies the connection
// with PING. REDIS_PASSWORD is optional: empty (the default for the local
// test-env Redis, which runs without --requirepass) authenticates as
// no-password, exactly like the pre-auth behavior this replaces; staging and
// prod set it to match Redis's --requirepass. It panics if the ping fails, so
// callers get a ready client or a crashed process — never a half-open one.
func ConnectRedis() *redis.Client {
	client := redis.NewClient(&redis.Options{
		Addr:         os.Getenv("REDIS_ADDR"),
		Password:     os.Getenv("REDIS_PASSWORD"),
		DB:           0,
		PoolSize:     20,
		MinIdleConns: 3,
		PoolTimeout:  5 * time.Second,
	})
	// Redis answers PING with "LOADING ..." right after a restart until its
	// dataset is in memory, and may not be dialable at all if it starts a beat
	// behind us. Retry for ~10s so a transient startup race no longer crashes
	// the process; a still-failing Redis after that is a real outage and panics.
	// Fixed 10 attempts at 1s; widen if a restart's dataset load runs longer.
	var err error
	for i := 0; ; i++ {
		var pong string
		pong, err = client.Ping().Result()
		if err == nil {
			obs.Logf("[REDIS] action=connect event=success pong=%s", pong)
			return client
		}
		if i >= 9 {
			obs.Logf("[REDIS] action=connect event=failed error=%v", err)
			panic(err)
		}
		time.Sleep(time.Second)
	}
}

// ConnectDB builds a pgx pool from DATABASE_URL. maxConnsEnv names the env var
// holding the pool's max size (default maxConnsDefault); the matching MIN var is
// derived by replacing "_MAX_" with "_MIN_". PG_SCHEMA, when set, pins the
// connection search_path for staging isolation. It pings before returning and
// panics on any parse, connect, or ping failure.
func ConnectDB(maxConnsEnv string, maxConnsDefault int32) *pgxpool.Pool {
	config, err := pgxpool.ParseConfig(os.Getenv("DATABASE_URL"))
	if err != nil {
		obs.Logf("[DB] action=parse_config event=failed error=%v", err)
		panic(err)
	}
	if s := os.Getenv("PG_SCHEMA"); s != "" {
		config.ConnConfig.RuntimeParams["search_path"] = s
	}
	if t := os.Getenv("PG_STATEMENT_TIMEOUT"); t != "" {
		config.ConnConfig.RuntimeParams["statement_timeout"] = t
	}
	config.MaxConns = EnvInt32(maxConnsEnv, maxConnsDefault)
	config.MinConns = EnvInt32(strings.Replace(maxConnsEnv, "_MAX_", "_MIN_", 1), 2)
	config.MaxConnLifetime = 30 * time.Minute
	config.MaxConnIdleTime = 5 * time.Minute
	conn, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		obs.Logf("[DB] action=connect event=failed error=%v", err)
		panic(err)
	}
	if err = conn.Ping(context.Background()); err != nil {
		obs.Logf("[DB] action=ping event=failed error=%v", err)
		panic(err)
	}
	obs.Logf("[DB] action=connect event=success")
	return conn
}

// EnvInt32 reads env var name as an int32, returning fallback when the var is
// unset, unparseable, or negative. Invalid non-empty values are logged before
// falling back.
func EnvInt32(name string, fallback int32) int32 {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	n, err := strconv.ParseInt(value, 10, 32)
	if err != nil || n < 0 {
		obs.Logf("[CONFIG] name=%s event=invalid value=%q fallback=%d", name, value, fallback)
		return fallback
	}
	return int32(n)
}
