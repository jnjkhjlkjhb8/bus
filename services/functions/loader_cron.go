package main

import (
	"context"
	"os"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/robfig/cron/v3"
)

// rawSourcePool returns the pool the loader reads raw_tdx from. When
// RAW_DATABASE_URL is set it opens a dedicated pool against that DSN, letting a
// test environment read the shared Azure raw_tdx (read-only) while sinking
// transforms to its own local schema via db. PG_SCHEMA is deliberately NOT
// pinned on this pool: rawTDXSource reads raw_tdx.<table> schema-qualified, so a
// search_path would have no effect on it and pinning the sink schema here would
// be misleading. When RAW_DATABASE_URL is unset it returns db unchanged, so the
// single-cluster deployment keeps reading and writing through one pool (zero
// behavior change). The returned pool is process-lifetime, like db.
func rawSourcePool(db *pgxpool.Pool) *pgxpool.Pool {
	dsn := os.Getenv("RAW_DATABASE_URL")
	if dsn == "" {
		return db
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		// event containing "fail" emits at Error level via obs.legacyLevel.
		log.Infof("[LOAD] action=raw_pool event=connect_failed fallback=sink_pool error=%v", err)
		return db
	}
	if err := pool.Ping(context.Background()); err != nil {
		log.Infof("[LOAD] action=raw_pool event=ping_failed fallback=sink_pool error=%v", err)
		pool.Close()
		return db
	}
	log.Infoln("[LOAD] action=raw_pool event=connected source=RAW_DATABASE_URL")
	return pool
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
func registerLoaderCrons(r *cron.Cron, db *pgxpool.Pool, rc *redis.Client) {
	rawPool := rawSourcePool(db)
	src := rawTDXSource{pool: rawPool}
	_, _ = r.AddFunc("0 30 3 * * *", func() {
		// runDaily's 3× retry never fires for the loader: runLoad returns nil
		// unconditionally (per-partition failures are isolated and logged inside
		// runLoadSpecs, by design), so there is no error to retry on. The wrapper
		// is kept only for the shared timeout/observability plumbing.
		runDaily("load", loadTimeout, func(ctx context.Context) error {
			return runLoad(ctx, src, db, rc, nil)
		})
	})
	if os.Getenv("LOAD_ON_BOOT") == "true" {
		log.Infoln("[LOAD] action=boot event=enabled")
		go func() {
			withTimeout(loadTimeout, func(ctx context.Context) {
				_ = runLoad(ctx, src, db, rc, nil)
			})
		}()
	} else {
		log.Infoln("[LOAD] action=boot event=skipped")
	}
}
