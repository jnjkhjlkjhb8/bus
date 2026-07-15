package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"github.com/robfig/cron/v3"
)

// rawSourcePool returns the pool the loader reads raw_tdx from. When
// RAW_DATABASE_URL is set it opens a dedicated pool against that DSN, letting a
// test environment read the shared Azure raw_tdx (read-only) while sinking
// transforms to its own local schema via db. PG_SCHEMA is deliberately NOT
// pinned on this pool: rawTDXSource reads raw_tdx.<table> schema-qualified, so a
// search_path would have no effect on it and pinning the sink schema here would
// be misleading. When RAW_DATABASE_URL is unset it returns db unchanged, so the
// single-cluster deployment keeps reading and writing through one pool. A
// configured URL is strict: parse/connect/ping failures are returned instead of
// silently targeting the sink database. The returned cleanup owns only a
// dedicated raw pool; the caller owns db.
func rawSourcePool(ctx context.Context, db *pgxpool.Pool) (*pgxpool.Pool, func(), error) {
	if ctx == nil {
		ctx = context.Background()
	}
	dsn := os.Getenv("RAW_DATABASE_URL")
	if dsn == "" {
		return db, func() {}, nil
	}
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, nil, fmt.Errorf("parse configured RAW_DATABASE_URL: %w", err)
	}
	cfg.MaxConns = shared.EnvInt32("RAW_DB_MAX_CONNS", 4)
	cfg.MaxConnLifetime = 30 * time.Minute
	cfg.MaxConnIdleTime = 5 * time.Minute
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, nil, fmt.Errorf("connect configured RAW_DATABASE_URL: %w", err)
	}
	pingCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, nil, fmt.Errorf("ping configured RAW_DATABASE_URL: %w", err)
	}
	log.Infoln("[LOAD] action=raw_pool event=connected source=RAW_DATABASE_URL")
	return pool, pool.Close, nil
}

// loadTimeout bounds one full load run. The Azure B1ms database serves reads
// slowly under memory pressure; a 20-minute budget has been exhausted mid-run,
// cascading "context deadline exceeded" over every remaining partition. The
// loader container is otherwise idle, so a generous budget costs nothing.
const loadTimeout = 60 * time.Minute

// registerLoaderCrons schedules the daily 03:30 load: transform raw_tdx into
// this environment's PG_SCHEMA. It runs 30 minutes after the prod ingestor's
// 03:00 landing (ADR-0005 coordination). When LOAD_ON_BOOT=true it also runs
// one load immediately, mirroring INGEST_ON_BOOT, so a fresh deploy backfills
// its schema without waiting for the next tick. The raw_tdx reader's pool comes
// from RAW_DATABASE_URL when set, else the process sink pool db (see
// rawSourcePool); the transforms always sink to db.
func registerLoaderCrons(r *cron.Cron, rawPool, db *pgxpool.Pool, rc *redis.Client) {
	src := rawTDXSource{pool: rawPool}
	runner := newStaticPipelineRunner(rawPool, loadTimeout)
	_, _ = addStaticCron(r, "0 30 3 * * *", func() {
		runDaily("load", loadTimeout, func(ctx context.Context) error {
			return runner.Run(ctx, func(ctx context.Context) error {
				return runLoad(ctx, src, db, rc, nil)
			})
		})
	})
	if os.Getenv("LOAD_ON_BOOT") == "true" {
		log.Infoln("[LOAD] action=boot event=enabled")
		go func() {
			if err := runner.Run(context.Background(), func(ctx context.Context) error {
				return runLoad(ctx, src, db, rc, nil)
			}); err != nil {
				log.Errorf("[LOAD] action=boot event=failed error=%v", err)
			}
		}()
	} else {
		log.Warn("[LOAD] action=boot event=skipped")
	}
}
