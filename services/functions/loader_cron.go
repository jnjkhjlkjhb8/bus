package main

import (
	"context"
	"errors"
	"os"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"github.com/robfig/cron/v3"
	"go.uber.org/zap"
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
		return nil, nil, _oops.Wrapf(err, "parse configured RAW_DATABASE_URL")
	}
	cfg.MaxConns = shared.EnvInt32("RAW_DB_MAX_CONNS", 4)
	cfg.MaxConnLifetime = 30 * time.Minute
	cfg.MaxConnIdleTime = 5 * time.Minute
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, nil, _oops.Wrapf(err, "connect configured RAW_DATABASE_URL")
	}
	pingCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, nil, _oops.Wrapf(err, "ping configured RAW_DATABASE_URL")
	}
	zap.S().Infow("connected",
		"component", "load",
		"action", "raw_pool",
		"event", "connected",
		"source", "RAW_DATABASE_URL",
	)
	return pool, pool.Close, nil
}

const _loadTimeout = 60 * time.Minute

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
	runner := newStaticPipelineRunner(rawPool, _loadTimeout)
	// Both entry points share one runner, so the 03:30 tick and a LOAD_ON_BOOT
	// run contend for the same advisory lock instead of overlapping.
	_, _ = addStaticCron(r, "0 30 3 * * *", func() {
		runLoadStage("crontab", "load", src, rawPool, db, rc, func(job func(context.Context) error) error {
			return runDailyWithRetry(context.Background(), _loadTimeout, time.Minute, func(ctx context.Context) error {
				return runner.Run(ctx, job)
			})
		})
	})
	if os.Getenv("LOAD_ON_BOOT") == "true" {
		zap.S().Infow("enabled", "component", "load", "action", "boot", "event", "enabled")
		trackBoot(boot, func() {
			// Boot deliberately does not retry: a fresh deploy that cannot load
			// should surface once and leave the 03:30 tick to redo it, rather than
			// hold the advisory lock through three attempts while the service comes up.
			runLoadStage("load", "boot", src, rawPool, db, rc, func(job func(context.Context) error) error {
				return runner.Run(context.Background(), job)
			})
		})
	} else {
		zap.S().Warnw("skipped", "component", "load", "action", "boot", "event", "skipped")
	}
	registerBusDailyTimetableCron(r, rawPool, db, rc)
}

// runLoadStage runs one load and, when the run earns it, the whole downstream
// chain that waits on the load marker. The 03:30 tick and the LOAD_ON_BOOT path
// are the same pipeline with different attempt policies, so attempt and the
// component/action log identity are the only things they supply separately: it receives the load job and decides whether to
// wrap it in retries. Everything after the run — the failure log, the
// markerEarned gate, the marker write, then vector refresh and GTFS export — is
// owned here, so neither caller can publish a marker its run did not earn or
// start a downstream stage without one.
//
// runDate is stamped before the run, not after: the stages downstream key off
// the service day the load was for, and a load that starts at 03:30 and finishes
// after midnight would otherwise mark the wrong day.
func runLoadStage(
	component, action string,
	src rawTDXSource,
	rawPool, db *pgxpool.Pool,
	rc *redis.Client,
	attempt func(job func(context.Context) error) error,
) {
	runDate := time.Now().In(_taipei)
	var stats loadStats
	err := attempt(func(ctx context.Context) error {
		var runErr error
		stats, runErr = runLoad(ctx, src, db, rc, nil)
		return runErr
	})
	if err != nil {
		zap.S().Errorw("failed",
			"component", component,
			"action", action,
			"event", "failed",
			"ok", stats.ok,
			"failed", stats.failed,
			"skipped", stats.skipped,
			"err", err,
		)
	}
	if !markerEarned(stats, err) {
		return
	}
	// The marker write sits outside attempt on purpose: a failed one-row upsert
	// must not re-drive a load that already succeeded, so it gets its own quick
	// retry and a distinct log (recordPipelineMarkerWithRetry).
	recordPipelineMarkerWithRetry(context.Background(), db, "load", runDate)
	runVectorRefresh(rawPool, db, rc, runDate)
	runGTFSExport(rawPool, runDate)
}

// _vectorRefreshTimeout bounds one changetovector attempt in the loader. It
// mirrors the retry/resume budget the functions cron used before this stage
// moved here: three attempts (runDailyWithRetry), each resumable because
// freshVectorSkipSQL skips rows already embedded with unchanged content.
const _vectorRefreshTimeout = 10 * time.Minute

// runVectorRefresh runs changetovector in the loader process immediately after a
// successful load, then records its pipeline marker. Binding it to the loader
// keeps the load->vector critical path inside one container: the functions
// service no longer needs to be running (or to poll the "load" marker) for
// search vectors to refresh. It acquires the static-pipeline advisory lock via
// its own runner, after the load's runner has released it, so the two stages
// stay serialized exactly as they were across processes.
func runVectorRefresh(rawPool, db *pgxpool.Pool, rc *redis.Client, runDate time.Time) {
	job := vectorRefreshJob(rc, db)
	runner := newStaticPipelineRunner(rawPool, _vectorRefreshTimeout)
	err := runDailyWithRetry(context.Background(), _vectorRefreshTimeout, time.Minute, func(ctx context.Context) error {
		return runner.Run(ctx, job)
	})
	if err != nil {
		zap.S().Errorw("failed", "component", "crontab", "action", "changetovector", "event", "failed", "err", err)
		return
	}
	// Marker write is outside the job retry: a failed one-row upsert must not
	// re-drive an already successful vector refresh.
	recordPipelineMarkerWithRetry(context.Background(), db, "changetovector", runDate)
}

// markerEarned reports whether a load run may publish its pipeline marker, the
// signal changetovector and the segment-time passes poll before starting.
//
// A partition that fails validation writes nothing, so its schema keeps
// yesterday's rows. Running the downstream stages over one stale city plus
// nineteen fresh ones beats withholding the marker and stranding vector search
// and ETA prediction nationwide over a single bad row, which is what withholding
// the marker on any per-partition failure would do.
//
// Two cases still withhold it. A run that loaded no partition at all published
// nothing to act on. A truncated run (deadline, cancellation) is not a partial
// load but an unfinished one: every partition it never reached would look
// current to a downstream stage, so the next run must redo it.
func markerEarned(stats loadStats, err error) bool {
	if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
		zap.S().Errorw("withheld",
			"component", "load",
			"action", "marker",
			"event", "withheld",
			"reason", "run_truncated",
			"ok", stats.ok,
		)
		return false
	}
	if stats.ok == 0 {
		zap.S().Errorw("withheld",
			"component", "load",
			"action", "marker",
			"event", "withheld",
			"reason", "no_partition_loaded",
			"failed", stats.failed,
			"skipped", stats.skipped,
		)
		return false
	}
	return true
}
