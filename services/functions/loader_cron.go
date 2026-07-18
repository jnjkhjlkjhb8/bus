package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"sync"
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

const loadTimeout = 60 * time.Minute

// registerLoaderCrons schedules the daily 03:30 load: transform raw_tdx into
// this environment's PG_SCHEMA. It runs 30 minutes after the prod ingestor's
// 03:00 landing (ADR-0005 coordination). When LOAD_ON_BOOT=true it also runs
// one load immediately, mirroring INGEST_ON_BOOT, so a fresh deploy backfills
// its schema without waiting for the next tick. The raw_tdx reader's pool comes
// from RAW_DATABASE_URL when set, else the process sink pool db (see
// rawSourcePool); the transforms always sink to db. boot tracks the
// LOAD_ON_BOOT goroutine so drainShutdown waits for it instead of abandoning
// it mid-run on shutdown.
func registerLoaderCrons(r *cron.Cron, rawPool, db *pgxpool.Pool, rc *redis.Client, boot *sync.WaitGroup) {
	src := rawTDXSource{pool: rawPool}
	runner := newStaticPipelineRunner(rawPool, loadTimeout)
	// The marker write sits outside the load's retry wrapper on purpose: a
	// failed one-row upsert must not re-drive a load that already succeeded,
	// and it gets its own quick retry + distinct log instead
	// (recordPipelineMarkerWithRetry). markerEarned decides whether the run
	// earned it.
	_, _ = addStaticCron(r, "0 30 3 * * *", func() {
		started := time.Now()
		runDate := started.In(taipei)
		var stats loadStats
		err := runDailyWithRetry(context.Background(), loadTimeout, time.Minute, func(ctx context.Context) error {
			return runner.Run(ctx, func(ctx context.Context) error {
				var runErr error
				stats, runErr = runLoad(ctx, src, db, rc, nil)
				return runErr
			})
		})
		if err != nil {
			log.Errorf("[crontab] action=load event=failed ok=%d failed=%d skipped=%d error=%v", stats.ok, stats.failed, stats.skipped, err)
		}
		if !markerEarned(stats, err) {
			return
		}
		_ = recordPipelineMarkerWithRetry(context.Background(), db, "load", runDate)
		runVectorRefresh(rawPool, db, rc, runDate)
	})
	if os.Getenv("LOAD_ON_BOOT") == "true" {
		log.Infoln("[LOAD] action=boot event=enabled")
		trackBoot(boot, func() {
			runDate := time.Now().In(taipei)
			var stats loadStats
			err := runner.Run(context.Background(), func(ctx context.Context) error {
				var runErr error
				stats, runErr = runLoad(ctx, src, db, rc, nil)
				return runErr
			})
			if err != nil {
				log.Errorf("[LOAD] action=boot event=failed ok=%d failed=%d skipped=%d error=%v", stats.ok, stats.failed, stats.skipped, err)
			}
			if !markerEarned(stats, err) {
				return
			}
			_ = recordPipelineMarkerWithRetry(context.Background(), db, "load", runDate)
			runVectorRefresh(rawPool, db, rc, runDate)
		})
	} else {
		log.Warn("[LOAD] action=boot event=skipped")
	}
}

// vectorRefreshTimeout bounds one changetovector attempt in the loader. It
// mirrors the retry/resume budget the functions cron used before this stage
// moved here: three attempts (runDailyWithRetry), each resumable because
// freshVectorSkipSQL skips rows already embedded with unchanged content.
const vectorRefreshTimeout = 10 * time.Minute

// runVectorRefresh runs changetovector in the loader process immediately after a
// successful load, then records its pipeline marker. Binding it to the loader
// keeps the load->vector critical path inside one container: the functions
// service no longer needs to be running (or to poll the "load" marker) for
// search vectors to refresh. It acquires the static-pipeline advisory lock via
// its own runner, after the load's runner has released it, so the two stages
// stay serialized exactly as they were across processes. A run with no EMBED_URL
// skips embedding but still records the marker (changeToVector returns nil for a
// nil embedder), so the downstream computeTravelAvg stage is never stranded --
// unchanged from the previous functions-hosted flow.
func runVectorRefresh(rawPool, db *pgxpool.Pool, rc *redis.Client, runDate time.Time) {
	job := vectorRefreshJob(rc, db, configuredEmbeddingClient())
	runner := newStaticPipelineRunner(rawPool, vectorRefreshTimeout)
	err := runDailyWithRetry(context.Background(), vectorRefreshTimeout, time.Minute, func(ctx context.Context) error {
		return runner.Run(ctx, job)
	})
	if err != nil {
		log.Errorf("[crontab] action=changetovector event=failed error=%v", err)
		return
	}
	// Marker write is outside the job retry: a failed one-row upsert must not
	// re-drive an already successful vector refresh.
	_ = recordPipelineMarkerWithRetry(context.Background(), db, "changetovector", runDate)
}

// markerEarned reports whether a load run may publish its pipeline marker, the
// signal changetovector and computeTravelAvg poll before starting.
//
// A partition that fails validation writes nothing, so its schema keeps
// yesterday's rows. Running the downstream stages over one stale city plus
// nineteen fresh ones beats withholding the marker and stranding vector search
// and ETA prediction nationwide over a single bad row, which is what a
// per-partition failure used to do.
//
// Two cases still withhold it. A run that loaded no partition at all published
// nothing to act on. A truncated run (deadline, cancellation) is not a partial
// load but an unfinished one: every partition it never reached would look
// current to a downstream stage, so the next run must redo it.
func markerEarned(stats loadStats, err error) bool {
	if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
		log.Errorf("[LOAD] action=marker event=withheld reason=run_truncated ok=%d", stats.ok)
		return false
	}
	if stats.ok == 0 {
		log.Errorf("[LOAD] action=marker event=withheld reason=no_partition_loaded failed=%d skipped=%d", stats.failed, stats.skipped)
		return false
	}
	return true
}
