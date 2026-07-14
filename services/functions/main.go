// Package main is the functions binary: a TDX ingestion scheduler and MQTT
// subscriber. One image runs in three modes selected by the ROLE env var
// (resolveRole): ROLE=ingestor lands raw TDX payloads into raw_tdx on a daily
// cron; ROLE=loader transforms raw_tdx into this env's PG_SCHEMA at 03:30;
// empty ROLE runs the legacy prod path (Firebase notifications, all
// transform/realtime crons, MQTT alerts) that writes static data to PostgreSQL
// and realtime ETAs to Redis. It also fills missing bus ETAs via schedule and
// travel-average prediction.
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

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/functions/notify"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"github.com/robfig/cron/v3"
)

// main boots the functions binary: it initializes observability, resolves the
// run mode from ROLE (a fatal error on unknown/unimplemented roles), opens
// shared Redis and PostgreSQL connections, then dispatches to either the
// ingestor cron set or the legacy prod flow. It blocks until a shutdown signal.
func main() {
	defer obs.Init("functions")()
	defer obs.Recover("main")

	role := os.Getenv("ROLE")
	rawDumpEnabled = role == "ingestor"
	mode, err := resolveRole(role)
	if err != nil {
		log.Fatal(err)
	}
	log.Infof("[BOOT] action=start role=%q", role)

	r := cron.New(cron.WithSeconds())
	rc := shared.ConnectRedis()
	// The ingestor is a nightly batch (≤3-way concurrency); give it its own small
	// pool so its 03:00 burst can never eat more than a handful of the shared
	// 50-slot Azure server's connections, independent of the realtime functions pool.
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
			log.Infof("[REDIS] action=close event=failed error=%v", cerr)
		}
	}(rc)
	defer db.Close()
	// Loader and vector coordination must lock the database that owns raw_tdx,
	// which can differ from the environment's transform/vector target. The
	// ingestor always lands into its process DB and therefore locks db directly.
	rawPool := db
	closeRawPool := func() {}
	if mode != modeIngestor {
		rawPool, closeRawPool, err = rawSourcePool(context.Background(), db)
		if err != nil {
			log.Fatal(err)
		}
	}
	defer closeRawPool()
	// One-shot manual trigger: `functions run <job>` runs the job once and exits,
	// bypassing cron so an operator can refresh embeddings on demand. Needs the
	// same env (DATABASE_URL, REDIS_ADDR, EMBED_URL) as the scheduled run.
	if len(os.Args) > 2 && os.Args[1] == "run" {
		switch os.Args[2] {
		case "changetovector":
			job := vectorRefreshJob(rc, db, configuredEmbeddingClient())
			runner := newStaticPipelineRunner(rawPool, 10*time.Minute)
			if err := runner.Run(context.Background(), job); err != nil {
				log.Fatalf("changetovector failed: %v", err)
			}
		default:
			log.Fatalf("unknown job: %s", os.Args[2])
		}
		return
	}
	tdx := shared.NewTDXClient(shared.TDXConfig{
		Store:         shared.RedisTDXStore{RC: rc},
		IMSKey:        imsCacheKey,
		SinceFallback: sinceFallback,
	})

	switch mode {
	case modeIngestor:
		registerIngestorCrons(r, tdx, db)
		r.Start()
		defer r.Stop()
		waitForShutdown()
	case modeLoader:
		registerLoaderCrons(r, rawPool, db, rc)
		r.Start()
		defer r.Stop()
		waitForShutdown()
	case modeLegacyProd:
		runLegacyProd(r, tdx, rc, rawPool, db)
	}
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
// one-minute backoff (obs.Retry). A context deadline that fires without job
// returning an error is wrapped as transient so it counts as a retryable
// failure. Exhausted retries are logged, not fatal — the next daily tick retries.
func runDaily(name string, d time.Duration, job func(context.Context) error) {
	err := runDailyWithRetry(context.Background(), d, time.Minute, job)
	if err != nil {
		log.Infof("[crontab] action=%s event=failed error=%v", name, err)
	}
}

const (
	// Stable, repo-specific signed 64-bit key shared by every functions role.
	staticPipelineAdvisoryKey    int64 = 0x6275737374617469
	staticPipelineReleaseTimeout       = 5 * time.Second
)

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
	return job(ctx)
}

// addStaticCron applies cron's own non-overlap guard in addition to the runner's
// boot/manual gate. The runner remains authoritative because boot is not a cron
// entry and different static job names can otherwise overlap.
func addStaticCron(r *cron.Cron, spec string, job func()) (cron.EntryID, error) {
	guarded := cron.NewChain(cron.SkipIfStillRunning(cron.DefaultLogger)).Then(cron.FuncJob(job))
	return r.AddJob(spec, guarded)
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
		return runLoad(ctx, src, db, rc, []string{"bus_dailytimetable"})
	})
}

// runLegacyProd is the current prod path: Firebase, notification dispatcher, all
// transform/realtime crons, and MQTT. Only ROLE="" reaches here — the ingestor
// never initializes any of it.
func runLegacyProd(r *cron.Cron, tdx *shared.TDXClient, rc *redis.Client, rawPool, db *pgxpool.Pool) {
	sender, err := notify.NewFirebaseSender(context.Background())
	if err != nil {
		log.Fatal(err)
	}
	dispatcher := notify.NewDispatcher(notify.NewStore(db), sender)
	bootLoadRunner := newStaticPipelineRunner(rawPool, loadTimeout)
	if err := runBootBusDailyTimetable(
		context.Background(), bootLoadRunner, rawTDXSource{pool: rawPool}, db, rc,
	); err != nil {
		log.Infof("[bus] action=bus_dailyroute event=error error=%v", err)
	}
	loadHolidays()
	loadModel()
	// Prime the weather cache at boot: the @every 10m cron below does not fire until
	// 10 minutes in, so without this every bus_eta_history row written in that window
	// after a restart would carry null weather features. Run it off the boot path so
	// the CWA round-trip does not delay cron startup.
	go weatherSync(rc)
	// The legacy direct-fetch static jobs are gone: the ingestor lands raw_tdx at
	// 03:00 and the ROLE=loader container transforms it into this env's schema at
	// 03:30. changetovector reads the tables the loader fills, so it runs at 03:45 —
	// cross-service coordination by clock, the same way loader trails ingestor.
	refreshVectors := vectorRefreshJob(rc, db, configuredEmbeddingClient())
	vectorRunner := newStaticPipelineRunner(rawPool, 10*time.Minute)
	_, _ = addStaticCron(r, "0 45 3 * * *", func() {
		runDaily("changetovector", 10*time.Minute, func(ctx context.Context) error {
			return vectorRunner.Run(ctx, refreshVectors)
		})
	})
	registerLiveCrons(r, tdx, rc, db, dispatcher)
	_, _ = r.AddFunc("@every 10m", func() {
		weatherSync(rc)
	})
	_, _ = r.AddFunc("0 0 4 * * *", func() {
		runDaily("computeTravelAvg", 15*time.Minute, func(ctx context.Context) error { return computeTravelAvg(ctx, db) })
	})
	_, _ = r.AddFunc("0 15 4 * * *", func() {
		runDaily("measurePredictionError", 10*time.Minute, func(ctx context.Context) error { return measurePredictionError(ctx, db) })
	})
	_, _ = r.AddFunc("0 30 4 * * *", func() {
		runDaily("cleanupBusHistory", 10*time.Minute, func(ctx context.Context) error { return cleanupBusHistory(ctx, db) })
		runDaily("cleanupBikeHistory", 10*time.Minute, func(ctx context.Context) error { return cleanupBikeHistory(ctx, db) })
	})
	r.Start()
	defer r.Stop()
	mqttClient := notify.StartMQTT(rc, dispatcher)
	if mqttClient != nil {
		defer mqttClient.Disconnect(500)
	}
	waitForShutdown()
}

// waitForShutdown blocks until SIGINT or SIGTERM, letting deferred cleanup
// (cron stop, connection close, MQTT disconnect) run on graceful termination.
func waitForShutdown() {
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	log.Infoln("[BOOT] action=shutdown event=signal_received")
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
			log.Infof("[BUS_STATIC] action=station_map event=scan_error error=%v", err)
			continue
		}
		list = append(list, temp)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return list, nil
}

// clearBusStaticCache deletes the legacy IMS cache keys for every bus static
// endpoint of a city, forcing the next fetch of each to pull fresh data.
func clearBusStaticCache(rc *redis.Client, city string) {
	for _, api := range []string{"Route", "StopOfRoute", "Shape", "Schedule", "Station", "StationGroup"} {
		if err := rc.Del("LastTimeGet_bus_" + api + city).Err(); err != nil {
			log.Infof("[BUS_STATIC] action=clear_cache city=%s api=%s event=cache_delete_error error=%v", city, api, err)
		}
	}
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
