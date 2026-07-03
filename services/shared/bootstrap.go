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
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
)

// ConnectRedis dials REDIS_ADDR with a fixed pool (no auth, DB 0) and verifies
// the connection with PING. It panics if the ping fails, so callers get a
// ready client or a crashed process — never a half-open one.
func ConnectRedis() *redis.Client {
	client := redis.NewClient(&redis.Options{
		Addr:         os.Getenv("REDIS_ADDR"),
		Password:     "",
		DB:           0,
		PoolSize:     20,
		MinIdleConns: 3,
		PoolTimeout:  5 * time.Second,
	})
	pong, err := client.Ping().Result()
	if err != nil {
		obs.Logf("[REDIS] action=connect event=failed error=%v", err)
		panic(err)
	}
	obs.Logf("[REDIS] action=connect event=success pong=%s", pong)
	return client
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
