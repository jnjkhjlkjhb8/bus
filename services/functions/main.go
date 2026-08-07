// Package main is the functions binary: a TDX ingestion scheduler and MQTT
// subscriber. One image runs in three modes selected by the ROLE env var
// (resolveRole): ROLE=ingestor lands raw TDX payloads into raw_tdx on a daily
// cron; ROLE=loader transforms raw_tdx into this env's PG_SCHEMA at 03:30;
// empty ROLE runs the legacy prod path (Firebase notifications, all
// transform/realtime crons, MQTT alerts) that writes static data to PostgreSQL
// and realtime ETAs to Redis. It also fills missing bus ETAs via schedule and
// segment-time prediction.
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/functions/notify"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"github.com/robfig/cron/v3"
	"go.uber.org/zap"
)

// main boots the functions binary: it initializes observability, resolves the
// run mode from ROLE (a fatal error on unknown/unimplemented roles), opens
// shared Redis and PostgreSQL connections, then dispatches to either the
// ingestor cron set or the legacy prod flow. It blocks until a shutdown signal.
func main() {
	if err := run(); err != nil {
		// Straight to stderr: run's deferred obs cleanup has already flushed
		// Sentry by the time it returns, so logging this through the
		// Sentry-forwarding handler would enqueue an event nothing flushes.
		_, _ = fmt.Fprintf(os.Stderr, "functions exited with error: %v\n", err)
		os.Exit(1)
	}
}

// run is main's body as a normal error-returning function: a boot failure must
// unwind the deferred Redis/PostgreSQL closes and the obs flush, which log.Fatal
// would skip.
func run() error {
	defer obs.Init("functions")()
	defer obs.Recover("main")

	role := os.Getenv("ROLE")
	rawDumpEnabled = role == "ingestor"
	mode, err := resolveRole(role)
	if err != nil {
		return err
	}
	zap.S().Infow("log", "component", "boot", "action", "start", "role", role)

	r := cron.New(cron.WithSeconds())
	rc := shared.ConnectRedis()
	// The ingestor is a nightly batch (≤3-way concurrency); give it its own small
	// pool so its 03:00 burst can never eat more than a handful of the shared
	// 50-slot server's connections, independent of the realtime functions pool.
	maxConnsEnv, maxConnsDefault := "FUNCTIONS_DB_MAX_CONNS", int32(10)
	switch role {
	case "ingestor":
		maxConnsEnv, maxConnsDefault = "INGEST_DB_MAX_CONNS", 10
	case "loader":
		// The loader is a nightly transform batch like the ingestor; give it its
		// own small pool so its 03:30 burst can't starve the realtime functions.
		maxConnsEnv, maxConnsDefault = "LOAD_DB_MAX_CONNS", 5
	}
	db := shared.ConnectDB(maxConnsEnv, maxConnsDefault)
	ingestDB = db
	defer func(rc *redis.Client) {
		if cerr := rc.Close(); cerr != nil {
			zap.S().Errorw("failed", "component", "redis", "action", "close", "event", "failed", "err", cerr)
		}
	}(rc)
	defer db.Close()
	if err := initArchive(context.Background(), os.Getenv("ARCHIVE_MYSQL_DSN")); err != nil {
		return err
	}
	defer func() {
		if archiveDB != nil {
			if cerr := archiveDB.Close(); cerr != nil {
				zap.S().Errorw("failed", "component", "archive", "action", "close", "event", "failed", "err", cerr)
			}
		}
	}()
	// Loader and vector coordination must lock the database that owns raw_tdx,
	// which can differ from the environment's transform/vector target. The
	// ingestor always lands into its process DB and therefore locks db directly.
	rawPool := db
	closeRawPool := func() {}
	if mode != modeIngestor {
		rawPool, closeRawPool, err = rawSourcePool(context.Background(), db)
		if err != nil {
			return err
		}
	}
	defer closeRawPool()
	tdx := shared.NewTDXClient(shared.TDXConfig{
		Store:         shared.RedisTDXStore{RC: rc},
		IMSKey:        imsCacheKey,
		SinceFallback: sinceFallback,
	})
	// One-shot manual trigger: `functions run <job>` runs the job once and exits,
	// bypassing cron so an operator can refresh embeddings on demand. Needs the
	// same env (DATABASE_URL, REDIS_ADDR, EMBED_URL) as the scheduled run.
	if len(os.Args) > 2 && os.Args[1] == "run" {
		switch os.Args[2] {
		case "changetovector":
			job := vectorRefreshJob(rc, db, configuredEmbeddingClient())
			runner := newStaticPipelineRunner(rawPool, manualBackfillTimeout)
			if err := runner.Run(context.Background(), job); err != nil {
				return fmt.Errorf("changetovector failed: %w", err)
			}
		case "gtfs":
			// Same builder the loader runs after a load, on demand: a feed can be
			// republished without waiting for 03:30 or forcing a reload.
			runGTFSExport(rawPool, time.Now().In(taipei))
		case "gtfs-rt":
			// The snapshot the router serves, built once. The daily timetables the
			// diff reads are loaded into Redis first: on a cron they arrive from the
			// hourly loader, and a one-shot run has no such producer behind it.
			ctx, cancel := context.WithTimeout(context.Background(), gtfsRTIndexTimeout)
			defer cancel()
			daily := map[string]string{}
			if err := loadChangedBusDailyTimetables(ctx, rawPool, rawTDXSource{pool: rawPool}, db, rc, daily); err != nil {
				return fmt.Errorf("bus daily timetable load failed: %w", err)
			}
			builder := &gtfsRTBuilder{db: rawPool, rc: rc}
			if err := builder.run(ctx, time.Now().In(taipei)); err != nil {
				return fmt.Errorf("gtfs-rt failed: %w", err)
			}
		case "bikeeta", "traeta", "buseta":
			// Refreshes what the published feeds read out of Redis: bike
			// availability for GBFS station_status, TRA delays and bus arrivals
			// for the GTFS-RT delay producers.
			//
			// The dispatcher is always nil, so a manual run sends no push
			// notifications. The pool is only given to bus, which cannot resolve a
			// stop without it; bike and tra run without one so that a manual
			// refresh writes no history rows. Bus does record its prediction
			// errors — that is not separable from the job, and it is the same
			// observation the scheduled run would have made.
			ctx, cancel := context.WithTimeout(context.Background(), manualBackfillTimeout)
			defer cancel()
			job := map[string]string{"bikeeta": "bike", "traeta": "tra", "buseta": "bus"}[os.Args[2]]
			var pool *pgxpool.Pool
			if job == "bus" {
				pool = db
			}
			runLive(ctx, restLiveSource{tdx: tdx}, redisLiveSink{rc: rc}, liveRegistry(pool, nil), []string{job})
		default:
			return fmt.Errorf("unknown job: %s", os.Args[2])
		}
		return nil
	}

	switch mode {
	case modeIngestor:
		var boot sync.WaitGroup
		registerIngestorCrons(r, tdx, db, &boot)
		r.Start()
		touchHealthFile()
		waitForShutdown()
		drainShutdown(r.Stop(), &boot, shutdownGrace)
	case modeLoader:
		var boot sync.WaitGroup
		registerLoaderCrons(r, rawPool, db, rc, &boot)
		r.Start()
		touchHealthFile()
		waitForShutdown()
		drainShutdown(r.Stop(), &boot, shutdownGrace)
	case modeLegacyProd:
		if err := runLegacyProd(r, tdx, rc, rawPool, db); err != nil {
			return err
		}
	case modeInvalid:
		// Unreachable: resolveRole returns modeInvalid only with an error,
		// which already returned above.
	}
	return nil
}

// appMode is the resolved run mode of the binary, derived from the ROLE env var.
type appMode int

// Run modes returned by resolveRole. modeInvalid is the zero value and only
// accompanies an error; it must never reach the run dispatch.
const (
	modeInvalid appMode = iota
	modeLegacyProd
	modeIngestor
	modeLoader
)

// resolveRole maps the ROLE env to a run mode. Unimplemented (eta/realtime) and
// unknown roles are errors, so they can never silently fall into the legacy prod
// flow. Empty ROLE preserves current prod behavior; ROLE=loader owns the 03:30
// loader cron (registerLoaderCrons) in its own container.
func resolveRole(role string) (appMode, error) {
	switch role {
	case "":
		return modeLegacyProd, nil
	case "ingestor":
		return modeIngestor, nil
	case "loader":
		return modeLoader, nil
	case "eta", "realtime":
		return modeInvalid, fmt.Errorf("ROLE=%s not implemented yet (Phase 2)", role)
	default:
		return modeInvalid, fmt.Errorf("unknown ROLE: %q", role)
	}
}

// withTimeout runs fn with a context that is canceled after d. It exists so cron
// jobs cannot run unbounded; fn is expected to honor ctx cancellation itself.
func withTimeout(d time.Duration, fn func(context.Context)) {
	_ = runWithTimeout(context.Background(), d, func(ctx context.Context) error {
		fn(ctx)
		return nil
	})
}

// runWithTimeout bounds one cooperative job attempt. A job that returns nil
// only after its deadline is still reported as a deadline failure.
func runWithTimeout(parent context.Context, d time.Duration, job func(context.Context) error) error {
	ctx, cancel := context.WithTimeout(parent, d)
	defer cancel()
	err := job(ctx)
	if err == nil && ctx.Err() != nil {
		return ctx.Err()
	}
	return err
}

// runDailyWithRetry is the testable retry core. Every failed daily attempt is
// transient by definition: the same bounded operation is safe to repeat and a
// later attempt must not be suppressed by a partition-level failure.
func runDailyWithRetry(parent context.Context, d, backoff time.Duration, job func(context.Context) error) error {
	return obs.Retry(parent, 3, backoff, func() error {
		return obs.Transient(runWithTimeout(parent, d, job))
	})
}

// runDaily runs a daily job under a d timeout, retrying up to 3 times with a
// one-minute backoff (obs.Retry). Exhausted retries are logged, not fatal — the
// next daily tick retries.
func runDaily(name string, d time.Duration, job func(context.Context) error) {
	err := runDailyWithRetry(context.Background(), d, time.Minute, job)
	if err != nil {
		zap.S().Errorw("failed", "component", "crontab", "action", name, "event", "failed", "err", err)
	}
}

const (
	// Stable, repo-specific signed 64-bit key shared by every functions role.
	staticPipelineAdvisoryKey    int64 = 0x6275737374617469
	staticPipelineReleaseTimeout       = 5 * time.Second
)

// manualBackfillTimeout bounds the `functions run changetovector` one-shot. It
// is deliberately far larger than the cron's per-attempt 10m budget so a cold
// full-corpus backfill on a CPU/small-GPU embedder completes in one pass.
const manualBackfillTimeout = 2 * time.Hour

// staticPipelineLocker holds a cross-process lock until its release callback.
// The PostgreSQL implementation below uses a transaction-scoped advisory lock;
// this narrow seam keeps concurrency tests independent of a live database.
type staticPipelineLocker interface {
	Acquire(context.Context) (release func() error, err error)
}

type staticPipelineTxBeginner interface {
	Begin(context.Context) (pgx.Tx, error)
}

type staticPipelineConnector interface {
	Connect(context.Context) (staticPipelineTxBeginner, func() error, error)
}

type staticPipelineDedicatedConn interface {
	staticPipelineTxBeginner
	Close(context.Context) error
}

// pgStaticPipelineConnector opens a dedicated connection from a copy of the
// raw pool's connection config. The production ingest/load pools intentionally
// allow MaxConns=1; holding the advisory-lock transaction inside that pool would
// consume its only slot and deadlock the job's own SQL.
type pgStaticPipelineConnector struct {
	pool    *pgxpool.Pool
	connect func(context.Context, *pgx.ConnConfig) (staticPipelineDedicatedConn, error)
}

func (c pgStaticPipelineConnector) Connect(ctx context.Context) (staticPipelineTxBeginner, func() error, error) {
	if c.pool == nil {
		return nil, nil, errors.New("static pipeline raw lock pool is nil")
	}
	connect := c.connect
	if connect == nil {
		connect = func(ctx context.Context, cfg *pgx.ConnConfig) (staticPipelineDedicatedConn, error) {
			return pgx.ConnectConfig(ctx, cfg)
		}
	}
	conn, err := connect(ctx, c.pool.Config().ConnConfig.Copy())
	if err != nil {
		return nil, nil, fmt.Errorf("connect static pipeline advisory database: %w", err)
	}
	if conn == nil {
		return nil, nil, errors.New("connect static pipeline advisory database returned nil connection")
	}
	var once sync.Once
	var closeErr error
	closeConnection := func() error {
		once.Do(func() {
			releaseCtx, cancel := context.WithTimeout(context.Background(), staticPipelineReleaseTimeout)
			defer cancel()
			if err := conn.Close(releaseCtx); err != nil {
				closeErr = fmt.Errorf("close static pipeline advisory connection: %w", err)
			}
		})
		return closeErr
	}
	return conn, closeConnection, nil
}

type pgStaticPipelineLocker struct{ connector staticPipelineConnector }

func (l pgStaticPipelineLocker) Acquire(ctx context.Context) (func() error, error) {
	if l.connector == nil {
		return nil, errors.New("static pipeline raw lock connector is nil")
	}
	conn, closeConnection, err := l.connector.Connect(ctx)
	if err != nil {
		return nil, err
	}
	if conn == nil || closeConnection == nil {
		if closeConnection != nil {
			_ = closeConnection()
		}
		return nil, errors.New("static pipeline connector returned incomplete connection")
	}
	tx, err := conn.Begin(ctx)
	if err != nil {
		return nil, errors.Join(
			fmt.Errorf("begin static pipeline advisory transaction: %w", err),
			closeConnection(),
		)
	}
	rollback := func() error {
		releaseCtx, cancel := context.WithTimeout(context.Background(), staticPipelineReleaseTimeout)
		defer cancel()
		err := tx.Rollback(releaseCtx)
		if errors.Is(err, pgx.ErrTxClosed) {
			return nil
		}
		return err
	}
	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock($1)", staticPipelineAdvisoryKey); err != nil {
		return nil, errors.Join(
			fmt.Errorf("acquire static pipeline advisory lock: %w", err),
			rollback(),
			closeConnection(),
		)
	}
	var once sync.Once
	var releaseErr error
	return func() error {
		once.Do(func() {
			releaseCtx, cancel := context.WithTimeout(context.Background(), staticPipelineReleaseTimeout)
			defer cancel()
			if err := tx.Commit(releaseCtx); err != nil {
				releaseErr = errors.Join(
					fmt.Errorf("release static pipeline advisory lock: %w", err),
					rollback(),
				)
			}
			releaseErr = errors.Join(releaseErr, closeConnection())
		})
		return releaseErr
	}, nil
}

// One process-wide gate serializes boot, cron, and manual static work. Separate
// containers have separate gates and are serialized by pgStaticPipelineLocker.
var staticPipelineProcessGate = make(chan struct{}, 1)

type staticPipelineRunner struct {
	gate    chan struct{}
	locker  staticPipelineLocker
	timeout time.Duration
}

func newStaticPipelineRunner(rawLockPool *pgxpool.Pool, timeout time.Duration) staticPipelineRunner {
	return staticPipelineRunner{
		gate: staticPipelineProcessGate,
		locker: pgStaticPipelineLocker{connector: pgStaticPipelineConnector{
			pool: rawLockPool,
		}},
		timeout: timeout,
	}
}

// Run waits for the local gate and PostgreSQL advisory lock within one timeout,
// runs job, and always releases both. The independent release context ensures a
// canceled job cannot strand the transaction-scoped lock. A panic is rethrown
// only after release; if release also fails, both failures remain visible.
func (r staticPipelineRunner) Run(parent context.Context, job func(context.Context) error) (err error) {
	if parent == nil {
		parent = context.Background()
	}
	ctx, cancel := context.WithTimeout(parent, r.timeout)
	defer cancel()
	if r.gate == nil {
		return errors.New("static pipeline process gate is nil")
	}
	select {
	case r.gate <- struct{}{}:
		defer func() { <-r.gate }()
	case <-ctx.Done():
		return ctx.Err()
	}
	if r.locker == nil {
		return errors.New("static pipeline advisory locker is nil")
	}
	release, err := r.locker.Acquire(ctx)
	if err != nil {
		return err
	}
	if release == nil {
		return errors.New("static pipeline advisory locker returned nil release")
	}
	defer func() {
		releaseErr := release()
		if recovered := recover(); recovered != nil {
			if releaseErr != nil {
				panic(errors.Join(fmt.Errorf("static pipeline job panic: %v", recovered), releaseErr))
			}
			panic(recovered)
		}
		err = errors.Join(err, releaseErr)
	}()
	jobErr := job(ctx)
	// A job may fail to cooperate with cancellation and return nil after the
	// deadline. Never report that run as successful; preserve both a real job
	// failure and the deadline/cancellation signal when both are present.
	return errors.Join(jobErr, ctx.Err())
}

// addStaticCron applies cron's own non-overlap guard in addition to the runner's
// boot/manual gate. The runner remains authoritative because boot is not a cron
// entry and different static job names can otherwise overlap.
//
// Every job registered this way also touches the liveness marker
// (touchHealthFile) once it returns, success or failure -- see that
// function's doc comment for why the container healthcheck cares about
// scheduler liveness, not per-job business success.
func addStaticCron(r *cron.Cron, spec string, job func()) (cron.EntryID, error) {
	guarded := cron.NewChain(cron.SkipIfStillRunning(cron.DefaultLogger)).Then(cron.FuncJob(func() {
		job()
		touchHealthFile()
	}))
	return r.AddJob(spec, guarded)
}

// staticJobSpec is one nightly pipeline job's recipe. Before this, every cron
// closure composed the same decisions by hand and picked them à la carte: the
// 04:00 chain hand-rolled its marker wait including the deadline margin, while
// the 04:15 and 04:30 entries reached for runDaily directly. Making them fields
// means a job that needs an upstream marker cannot forget the margin, and the
// nightly pipeline's shape reads as a list instead of five closures.
//
// Deliberately not covered: weatherSync and loadHolidays. Those are best-effort
// refreshes with a last-good Redis snapshot behind them, so they warn rather
// than error and must not retry — a different category, not a missing field.
//
// Also deliberately absent: a locked flag. The static-pipeline advisory lock
// would be redundant here, because waitFor already proves the upstream stage
// finished, and adding it would mean bounding the whole chain under one more
// timeout that could truncate a legitimately slow segment-time pass.
type staticJobSpec struct {
	name     string
	schedule string
	// waitFor is the upstream pipeline marker to poll before the first attempt.
	// Empty means the job has no upstream stage.
	waitFor string
	// timeout bounds one attempt. Zero means run bounds itself, which is what the
	// multi-pass entries do: each of their passes carries its own budget, so a
	// failure in the third must not re-drive the first two.
	timeout time.Duration
	// attempts above 1 retries with a one-minute backoff (obs.Retry). Every failed
	// daily attempt is transient by definition: the same bounded operation is safe
	// to repeat.
	attempts int
	run      func(ctx context.Context) error
}

// registerStaticJob schedules one staticJobSpec, composing marker wait, timeout,
// and retry in that order. Failures are logged, never fatal: the next daily tick
// retries.
func registerStaticJob(r *cron.Cron, marker pipelineMarkerReader, spec staticJobSpec) {
	_, _ = addStaticCron(r, spec.schedule, func() {
		runStaticJob(marker, spec, time.Now, sleepCtx, time.Minute)
	})
}

// runStaticJob is registerStaticJob's testable core. Every wall-clock dependency
// is injected for the same reason waitForPipelineMarker takes now and sleep: the
// marker polls every five minutes against a two-hour deadline and retries back
// off a minute apart, so a test on the real clock would genuinely wait.
func runStaticJob(
	marker pipelineMarkerReader,
	spec staticJobSpec,
	now func() time.Time,
	sleep func(context.Context, time.Duration) error,
	backoff time.Duration,
) {
	if spec.waitFor != "" {
		waitCtx, cancel := context.WithTimeout(context.Background(), pipelineMarkerPollDeadline+time.Minute)
		defer cancel()
		err := waitForPipelineMarker(waitCtx, marker, spec.waitFor, now().In(taipei),
			pipelineMarkerPollInterval, pipelineMarkerPollDeadline, now, sleep)
		if err != nil {
			zap.S().Errorw("marker wait failed",
				"component", "pipeline",
				"action", spec.name,
				"event", "marker_wait_failed",
				"upstream", spec.waitFor,
				"err", err,
			)
			return
		}
	}
	var err error
	switch {
	case spec.timeout <= 0:
		err = spec.run(context.Background())
	case spec.attempts > 1:
		err = runDailyWithRetry(context.Background(), spec.timeout, backoff, spec.run)
	default:
		err = runWithTimeout(context.Background(), spec.timeout, spec.run)
	}
	if err != nil {
		zap.S().Errorw("failed", "component", "crontab", "action", spec.name, "event", "failed", "err", err)
	}
}

func vectorRefreshJob(rc vectorRedis, db vectorDB, embedder embeddingClient) func(context.Context) error {
	return func(ctx context.Context) error {
		return changeToVector(ctx, rc, db, embedder)
	}
}

// runBootBusDailyTimetable refreshes the legacy prod process's schedule cache
// through the same bounded process gate and raw-database advisory lock as every
// other static job. The caller logs an error and continues booting; this helper
// intentionally adds no second timeout around the runner.
func runBootBusDailyTimetable(
	parent context.Context,
	runner staticPipelineRunner,
	src loadSource,
	db *pgxpool.Pool,
	rc *redis.Client,
) error {
	return runner.Run(parent, func(ctx context.Context) error {
		_, err := runLoad(ctx, src, db, rc, []string{"bus_dailytimetable"})
		return err
	})
}

// runLegacyProd is the current prod path: Firebase, notification dispatcher, all
// transform/realtime crons, and MQTT. Only ROLE="" reaches here — the ingestor
// never initializes any of it. A boot failure is returned rather than fatal, so
// run's deferred Redis/PostgreSQL closes and the obs flush still get to run —
// without the flush the failure that stopped boot never reaches Sentry.
func runLegacyProd(r *cron.Cron, tdx *shared.TDXClient, rc *redis.Client, rawPool, db *pgxpool.Pool) error {
	sender, err := notify.NewFirebaseSender(context.Background())
	if err != nil {
		return fmt.Errorf("init Firebase sender: %w", err)
	}
	dispatcher := notify.NewDispatcher(notify.NewStore(db), sender)
	// The card-refresh transports (ADR-0018). Absent APNs credentials disable the
	// iOS leg only; a malformed key is a boot failure rather than a silent
	// downgrade, because credentials that are present but unusable are a mistake.
	apns, err := notify.NewAPNSSender()
	if err != nil {
		return fmt.Errorf("init APNs sender: %w", err)
	}
	pusher := notify.NewTrackPusher(sender, apns)
	bootLoadRunner := newStaticPipelineRunner(rawPool, loadTimeout)
	if err := runBootBusDailyTimetable(
		context.Background(), bootLoadRunner, rawTDXSource{pool: rawPool}, db, rc,
	); err != nil {
		zap.S().Errorw("error", "component", "bus", "action", "bus_dailyroute", "event", "error", "err", err)
	}
	holidayCtx, holidayCancel := context.WithTimeout(context.Background(), holidayHTTPTimeout)
	if err := loadHolidays(holidayCtx); err != nil {
		zap.S().Warnw(fmt.Sprintf("initial refresh failed; weekend/last-good fallback active: %v", err),
			"component", "holiday",
		)
	}
	holidayCancel()
	loadModel()
	// Prime the weather cache at boot: the @every 10m cron below does not fire until
	// 10 minutes in, so without this every bus_eta_history row written in that window
	// after a restart would carry null weather features. The bounded context keeps
	// startup delay finite while avoiding a detached refresh goroutine.
	weatherCtx, weatherCancel := context.WithTimeout(context.Background(), weatherHTTPTimeout)
	if err := weatherSync(weatherCtx, rc); err != nil {
		zap.S().Warnw(fmt.Sprintf("initial sync failed; keeping last good Redis snapshot: %v", err),
			"component", "weather",
		)
	}
	weatherCancel()
	// The ingestor lands raw_tdx at 03:00 and the ROLE=loader container transforms
	// it into this env's schema at 03:30. changetovector runs in that same loader
	// process right after the load (registerLoaderCrons -> runVectorRefresh), and
	// the segment-time passes (below) read what it fills. Each cron entry here
	// keeps its own clock offset (03:45 / 04:00) but first polls pipeline_runs for
	// the upstream stage's durable completion marker (written by the
	// loader/changetovector on success) rather than trusting the offset alone.
	// markerReader is what the 04:00 cron polls the "changetovector" marker with.
	markerReader := pgPipelineMarkerReader{db: db}
	registerLiveCrons(r, tdx, rc, db, dispatcher)
	// GTFS-RT snapshot (ADR-0019): rebuilt here, served by services/router. It
	// reads rawPool because the static trip index is derived from
	// raw_tdx.bus_schedule, the same source trips.txt is built from.
	registerGTFSRTCron(r, rawPool, rc)
	// Metro alight-reminder tracker (ADR-0015): a 15s cron that advances active
	// car-bound sessions from GetTrainInfo (event-driven, one call per hop). Not a
	// liveSpec — it never touches TDX. Nil-safe dispatcher when push is disabled.
	registerMrtTrackCron(r, rc, db, dispatcher, pusher)
	_, _ = addStaticCron(r, "@every 10m", func() {
		ctx, cancel := context.WithTimeout(context.Background(), weatherHTTPTimeout)
		defer cancel()
		if err := weatherSync(ctx, rc); err != nil {
			zap.S().Warnw(fmt.Sprintf("sync failed; keeping last good Redis snapshot: %v", err),
				"component", "weather",
			)
		}
	})
	_, _ = addStaticCron(r, "@every 24h", func() {
		ctx, cancel := context.WithTimeout(context.Background(), holidayHTTPTimeout)
		defer cancel()
		if err := loadHolidays(ctx); err != nil {
			zap.S().Warnw(fmt.Sprintf("refresh failed; keeping last good snapshot: %v", err), "component", "holiday")
		}
	})
	registerStaticJob(r, markerReader, staticJobSpec{
		name: "segmentTimes", schedule: "0 0 4 * * *", waitFor: "changetovector",
		// Each pass carries its own budget and retries independently, so the spec
		// leaves timeout zero rather than bounding the chain: a failure in the fill
		// pass must not re-drive the observation pass that already wrote.
		run: func(context.Context) error {
			// The observation pass: adjacent stops differenced within one recorded
			// snapshot. A plate-pairing pass ran ahead of it until 2026-08-02
			// (segment_time.go says why it went).
			runDaily("computeSegmentTimesFromEstimates", 15*time.Minute, func(ctx context.Context) error {
				return computeSegmentTimesFromEstimates(ctx, db, resolveHistory())
			})
			// Then, once the observations are in: a distance-derived estimate for
			// the hops still empty, so one unobserved segment does not cost GTFS the
			// whole route direction. Marked sample_count = 0 and never written over
			// an observed row.
			runDaily("fillSegmentTimesFromDistance", 15*time.Minute, func(ctx context.Context) error {
				return fillSegmentTimesFromDistance(ctx, db)
			})
			return nil
		},
	})
	registerStaticJob(r, markerReader, staticJobSpec{
		name: "measurePredictionError", schedule: "0 15 4 * * *",
		timeout: 10 * time.Minute, attempts: 3,
		run: func(ctx context.Context) error { return measurePredictionError(ctx, db, resolveHistory()) },
	})
	registerStaticJob(r, markerReader, staticJobSpec{
		// Both cleanups stay on one entry so they run in sequence. Two entries at
		// 04:30 would open two pooled connections at once against an Azure B1ms that
		// the nightly load already pushes hard.
		name: "cleanups", schedule: "0 30 4 * * *",
		run: func(context.Context) error {
			runDaily("cleanupPredictionErrors", 10*time.Minute, func(ctx context.Context) error { return cleanupPredictionErrors(ctx, db) })
			runDaily("cleanupBikeHistory", 10*time.Minute, func(ctx context.Context) error { return cleanupBikeHistory(ctx, db) })
			return nil
		},
	})
	r.Start()
	touchHealthFile()
	mqttClient := notify.StartMQTT(rc, dispatcher)
	waitForShutdown()
	// Stop intake first: MQTT (no more messages dispatched) then cron (no
	// more ticks fired). Only then wait for whatever is already in flight.
	if mqttClient != nil {
		mqttClient.Disconnect(500)
	}
	drainShutdown(r.Stop(), &sync.WaitGroup{}, shutdownGrace)
	return nil
}

// waitForShutdown blocks until SIGINT or SIGTERM, letting deferred cleanup
// (cron stop, connection close, MQTT disconnect) run on graceful termination.
func waitForShutdown() {
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	zap.S().Infow("signal received", "component", "boot", "action", "shutdown", "event", "signal_received")
}

// shutdownGrace bounds how long drainShutdown waits for in-flight cron/boot
// work to finish before the caller proceeds to close shared Redis/DB
// connections. A job that outlives it is abandoned mid-flight (its own
// per-job timeout is expected to have fired well before this), but the
// process still exits instead of hanging forever on a stuck job.
const shutdownGrace = 30 * time.Second

// drainShutdown waits, bounded by grace, for both cronDone (the context
// returned by cron.Cron.Stop — its own intake must already be stopped before
// calling this) and boot (goroutines started outside cron, e.g. an
// *_ON_BOOT run) to finish. Call it after intake has stopped and before
// closing any dependency a running job might still be using: that ordering
// is what keeps a job from observing a closed Redis/DB connection mid-run.
func drainShutdown(cronDone context.Context, boot *sync.WaitGroup, grace time.Duration) {
	done := make(chan struct{})
	go func() {
		<-cronDone.Done()
		if boot != nil {
			boot.Wait()
		}
		close(done)
	}()
	select {
	case <-done:
		zap.S().Infow("jobs drained", "component", "boot", "action", "shutdown", "event", "jobs_drained")
	case <-time.After(grace):
		zap.S().Warnw("grace timeout",
			"component", "boot",
			"action", "shutdown",
			"event", "grace_timeout",
			"grace", grace,
		)
	}
}

// trackBoot runs fn in a goroutine tracked by wg, so a boot-time job started
// outside cron (INGEST_ON_BOOT, LOAD_ON_BOOT) is waited for by drainShutdown
// instead of being abandoned when the process starts shutting down.
func trackBoot(wg *sync.WaitGroup, fn func()) {
	wg.Add(1)
	go func() {
		defer wg.Done()
		fn()
	}()
}

// busstaticmp loads the per-stop station map for a city prefix: every stop of
// every subroute joined to its station group and coordinates. busEta uses it to
// attach live ETAs to stops and to group stops under a shared station. Rows that
// fail to scan are logged and skipped rather than aborting the whole load.
func busstaticmp(ctx context.Context, db *pgxpool.Pool, city string) ([]busStationmap, error) {
	query := `SELECT bssm.station_id, bssm.station_name,
	                 COALESCE(bsgm.group_uid, bssm.station_id),
	                 COALESCE(bg.group_name, bssm.station_name),
	                 bssm.sub_route_uid, COALESCE(bst.route_uid, ''), bssm.route_name,
	                 COALESCE(bsr.destin, bst.destin, ''),
	                 bssm.direction, bssm.stop_uid, bssm.stop_sequence,
	                 COALESCE(ST_Y(bs.position), 0), COALESCE(ST_X(bs.position), 0)
	          FROM bus_station_stop_map bssm
	          LEFT JOIN bus_static bst ON bst.sub_route_uid = bssm.sub_route_uid
	          LEFT JOIN bus_subroutes bsr ON bsr.sub_route_uid = bssm.sub_route_uid
	                                     AND bsr.direction = bssm.direction
	          LEFT JOIN bus_stations bs ON bs.station_uid = bssm.station_id
	          LEFT JOIN bus_station_group_members bsgm ON bsgm.station_uid = bssm.station_id
	          LEFT JOIN bus_station_groups bg ON bg.group_uid = bsgm.group_uid
	          WHERE bssm.sub_route_uid LIKE $1`
	rows, err := db.Query(ctx, query, city+"%")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var list []busStationmap
	for rows.Next() {
		var temp busStationmap
		err := rows.Scan(&temp.StationUID, &temp.StationName, &temp.GroupUID,
			&temp.GroupName, &temp.SubRouteUID, &temp.RouteUID, &temp.SubRouteName, &temp.Destination, &temp.Direction, &temp.StopUID, &temp.StopSequence,
			&temp.Lat, &temp.Lon)
		if err != nil {
			zap.S().Errorw("scan error",
				"component", "bus_static",
				"action", "station_map",
				"event", "scan_error",
				"err", err,
			)
			continue
		}
		list = append(list, temp)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return list, nil
}

// mask packs a weekly service pattern into a bitmask: bit 0 = Monday through bit
// 6 = Sunday, and bit 7 = national holiday when the optional nationalHoliday
// argument is true. The stored uint8 is what schedule lookups match the current
// day against.
func mask(mon, tues, wed, thur, fri, satur, sun bool, nationalHoliday ...bool) uint8 {
	var res uint8
	days := []bool{mon, tues, wed, thur, fri, satur, sun}
	for i, v := range days {
		if v {
			res |= 1 << i
		}
	}
	if len(nationalHoliday) > 0 && nationalHoliday[0] {
		res |= 1 << 7
	}
	return res
}

// mask2 is mask for TDX ServiceDay fields that arrive as uint8 flags (1 = runs).
// It packs Monday..Sunday into bits 0..6; unlike mask it has no holiday bit.
func mask2(mon, tues, wed, thur, fri, satur, sun uint8) uint8 {
	var res uint8
	days := []uint8{mon, tues, wed, thur, fri, satur, sun}
	for i, v := range days {
		if v == 1 {
			res |= 1 << i
		}
	}
	return res
}
