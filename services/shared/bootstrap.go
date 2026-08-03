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

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
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

		// v9 retries three times when MaxRetries is zero, where v6 did not retry
		// at all; -1 keeps the no-retry behavior the callers were written against.
		MaxRetries: -1,
		// Pin RESP2. v9 negotiates RESP3 by default, which changes reply shapes
		// for some commands; the wire protocol is not what this migration is
		// changing.
		Protocol: 2,
		// Without this, v9 applies only the socket timeouts and ignores context
		// deadlines — the whole point of moving off v6.
		ContextTimeoutEnabled: true,
		// Skip the CLIENT SETINFO handshake v9 sends on every new connection.
		DisableIdentity: true,
	})
	// Redis answers PING with "LOADING ..." right after a restart until its
	// dataset is in memory, and may not be dialable at all if it starts a beat
	// behind us. Retry for ~10s so a transient startup race no longer crashes
	// the process; a still-failing Redis after that is a real outage and panics.
	// Fixed 10 attempts at 1s; widen if a restart's dataset load runs longer.
	// Process bootstrap is a top-level entry point, so the readiness probe owns
	// its context rather than inheriting one.
	ctx := context.Background()
	var err error
	for i := 0; ; i++ {
		var pong string
		pong, err = client.Ping(ctx).Result()
		if err == nil {
			zap.S().Infow("connect success", "component", "redis", "action", "connect", "event", "success", "pong", pong)
			return client
		}
		if i >= 9 {
			zap.S().Errorw("connect failed", "component", "redis", "action", "connect", "event", "failed", "err", err)
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
		zap.S().Errorw("parse config failed", "component", "db", "action", "parse_config", "event", "failed", "err", err)
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
		zap.S().Errorw("connect failed", "component", "db", "action", "connect", "event", "failed", "err", err)
		panic(err)
	}
	if err = conn.Ping(context.Background()); err != nil {
		zap.S().Errorw("ping failed", "component", "db", "action", "ping", "event", "failed", "err", err)
		panic(err)
	}
	zap.S().Infow("connect success", "component", "db", "action", "connect", "event", "success")
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
		zap.S().Warnw("invalid", "component", "config", "name", name, "event", "invalid", "value", value, "fallback", fallback)
		return fallback
	}
	return int32(n)
}
