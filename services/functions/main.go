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
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5/pgxpool"
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
	tdx := shared.NewTDXClient(shared.TDXConfig{
		Store:         shared.RedisTDXStore{RC: rc},
		IMSKey:        imsCacheKey,
		SinceFallback: sinceFallback,
	})

	switch mode {
	case modeIngestor:
		registerIngestorCrons(r, tdx)
		r.Start()
		defer r.Stop()
		waitForShutdown()
	case modeLoader:
		registerLoaderCrons(r, db, rc)
		r.Start()
		defer r.Stop()
		waitForShutdown()
	case modeLegacyProd:
		runLegacyProd(r, tdx, rc, db)
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
	ctx, cancel := context.WithTimeout(context.Background(), d)
	defer cancel()
	fn(ctx)
}

// runDaily runs a daily job under a d timeout, retrying up to 3 times with a
// one-minute backoff (obs.Retry). A context deadline that fires without job
// returning an error is wrapped as transient so it counts as a retryable
// failure. Exhausted retries are logged, not fatal — the next daily tick retries.
func runDaily(name string, d time.Duration, job func(context.Context) error) {
	err := obs.Retry(context.Background(), 3, time.Minute, func() error {
		var jobErr error
		withTimeout(d, func(ctx context.Context) {
			jobErr = job(ctx)
			if jobErr == nil && ctx.Err() != nil {
				jobErr = obs.Transient(ctx.Err())
			}
		})
		return jobErr
	})
	if err != nil {
		log.Infof("[crontab] action=%s event=failed error=%v", name, err)
	}
}

// runLegacyProd is the current prod path: Firebase, notification dispatcher, all
// transform/realtime crons, and MQTT. Only ROLE="" reaches here — the ingestor
// never initializes any of it.
func runLegacyProd(r *cron.Cron, tdx *shared.TDXClient, rc *redis.Client, db *pgxpool.Pool) {
	sender, err := newFirebaseSender(context.Background())
	if err != nil {
		log.Fatal(err)
	}
	dispatcher := newNotificationDispatcher(notificationStore{db: db}, sender)
	busDailyroute(tdx, rc)
	loadHolidays()
	loadModel()
	// The legacy direct-fetch static jobs (bikeStatic/mrtStatic/railStatic; the
	// bus one is deleted) no longer run here: the ingestor lands raw_tdx at 03:00
	// and the ROLE=loader container transforms it into this env's schema at 03:30.
	// changetovector reads the tables the loader fills, so it runs at 03:45 —
	// cross-service coordination by clock, the same way loader trails ingestor.
	_, _ = r.AddFunc("0 45 3 * * *", func() {
		runDaily("changetovector", 10*time.Minute, func(ctx context.Context) error {
			changetovector(ctx, rc, db)
			return nil
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
	mqttClient := startMQTT(rc, dispatcher)
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

// ingestDB is the process-wide pool used by the raw_tdx landing path and by
// dbSince. It is set once in main and read without locking; dumpRawTDX treats a
// nil value as a hard error.
var ingestDB *pgxpool.Pool

// rawDumpEnabled gates the raw_tdx landing to ROLE=ingestor only, so the default
// prod transform path never writes raw_tdx.
var rawDumpEnabled bool

// imsCacheKey is the If-Modified-Since cache key for a fetch target. The ingestor
// writes namespaced shared:raw:* keys; the default prod path keeps its legacy key
// so prod behavior is unchanged. Both key forms live in shared/keys.go.
func imsCacheKey(name string) string {
	if rawDumpEnabled {
		return shared.TDXRawIMSKey(name)
	}
	return shared.TDXLegacyIMSKey(name)
}

// dbSince derives an If-Modified-Since value from the latest updated_at of the
// prod table backing a fetch target, so a cold IMS cache still avoids re-pulling
// data already in PostgreSQL. It maps the fetch name to a table/partition query;
// unknown names, a nil pool, or any query error yield "" (fetch everything). Not
// used in ingestor mode (see dbSinceFallbackAllowed).
func dbSince(name string) string {
	if ingestDB == nil {
		return ""
	}
	var q string
	var arg any
	switch {
	case strings.HasPrefix(name, "tra_traindate_"):
		q = "SELECT MAX(updated_at) FROM tra_timetable WHERE train_date=$1"
		arg = strings.TrimPrefix(name, "tra_traindate_")
	case strings.HasPrefix(name, "thsr_traindate_"):
		q = "SELECT MAX(updated_at) FROM thsr_timetable WHERE train_date=$1"
		arg = strings.TrimPrefix(name, "thsr_traindate_")
	case name == "tra_stations":
		q = "SELECT MAX(updated_at) FROM tra_stations"
	case name == "thsr_stations":
		q = "SELECT MAX(updated_at) FROM thsr_stations"
	case name == "tra_fare":
		q = "SELECT MAX(updated_at) FROM tra_fares"
	case name == "thsr_fare":
		q = "SELECT MAX(updated_at) FROM thsr_fares"
	case strings.HasPrefix(name, "mrt_stations"):
		q = "SELECT MAX(updated_at) FROM mrt_station WHERE system=$1"
		arg = strings.TrimPrefix(name, "mrt_stations")
	case strings.HasPrefix(name, "mrt_firstlast"):
		q = "SELECT MAX(updated_at) FROM mrt_schedule WHERE system=$1"
		arg = strings.TrimPrefix(name, "mrt_firstlast")
	case strings.HasPrefix(name, "bike_stations"):
		q = "SELECT MAX(updated_at) FROM bike_stations WHERE city=$1"
		arg = strings.TrimPrefix(name, "bike_stations")
	default:
	}
	ctx := context.Background()
	var t *time.Time
	var err error
	if arg != nil {
		err = ingestDB.QueryRow(ctx, q, arg).Scan(&t)
	} else {
		err = ingestDB.QueryRow(ctx, q).Scan(&t)
	}
	if err != nil || t == nil {
		return ""
	}
	return t.UTC().Format(http.TimeFormat)
}

// dbSinceFallbackAllowed reports whether an empty IMS cache may fall back to a
// prod table's updated_at. Never in ingestor mode: a 304 against an empty
// raw_tdx would strand the landing table permanently empty.
func dbSinceFallbackAllowed() bool { return !rawDumpEnabled }

// sinceFallback is the shared TDX client's cold-cache If-Modified-Since source:
// in the legacy prod path it derives the value from the backing table's
// updated_at (dbSince); in ingestor mode it returns "" so an empty raw_tdx is
// never masked by a table-derived 304.
func sinceFallback(name string) string {
	if dbSinceFallbackAllowed() {
		return dbSince(name)
	}
	return ""
}

// rawDumpTarget maps a TDX static endpoint path to its raw_tdx landing table and
// partition column. Real-time / unmapped endpoints return ok=false.
func rawDumpTarget(url string) (table, partCol, partVal string, ok bool) {
	seg := strings.Split(strings.Trim(url, "/"), "/")
	if len(seg) < 3 || seg[0] != "v2" {
		return "", "", "", false
	}
	cityOf := func() string {
		for i, s := range seg {
			if s == "City" && i+1 < len(seg) {
				return seg[i+1]
			}
			if s == "InterCity" {
				return "InterCity"
			}
		}
		return ""
	}
	switch {
	case seg[1] == "Bus":
		// Bus/Stop is intentionally absent: it is never fetched by the ingestor
		// (raw_tdx.bus_stop stays unused; whitelist + DDL are kept — see rawTDXTables).
		busTables := map[string]string{
			"Route": "bus_route", "StopOfRoute": "bus_stopofroute", "Shape": "bus_shape",
			"Schedule": "bus_schedule", "Station": "bus_station", "StationGroup": "bus_stationgroup",
			"Operator": "bus_operator", "RouteFare": "bus_routefare",
			"DailyTimeTable": "bus_dailytimetable",
		}
		if t, exists := busTables[seg[2]]; exists {
			return t, "city", cityOf(), true
		}
	case seg[1] == "Bike" && seg[2] == "Station":
		return "bike_station", "city", cityOf(), true
	case seg[1] == "Rail" && len(seg) >= 4 && seg[2] == "Metro":
		metroTables := map[string]string{
			"Station": "metro_station", "FirstLastTimetable": "metro_schedule", "ODFare": "metro_odfare",
		}
		if t, exists := metroTables[seg[3]]; exists {
			return t, "system", seg[len(seg)-1], true
		}
	case seg[1] == "Rail" && len(seg) >= 4 && (seg[2] == "TRA" || seg[2] == "THSR"):
		// Timetable endpoints are landed per train date so the loader window
		// (TRA today..+60, THSR today..+45) survives a mid-run partition swap
		// instead of the whole table being TRUNCATE'd. The partition column is
		// the existing traindate column landed from the TDX payload.
		switch seg[2] + "/" + seg[3] {
		case "TRA/DailyTimetable":
			return "tra_dailytimetable", "traindate", seg[len(seg)-1], true
		case "THSR/DailyTimetable":
			return "thsr_dailytimetable", "traindate", seg[len(seg)-1], true
		}
		railTables := map[string]string{
			"TRA/Station": "tra_station", "THSR/Station": "thsr_station",
			"TRA/ODFare": "tra_odfare", "THSR/ODFare": "thsr_odfare",
			"TRA/TrainType": "tra_traintype",
		}
		if t, exists := railTables[seg[2]+"/"+seg[3]]; exists {
			return t, "", "", true
		}
	}
	return "", "", "", false
}

// errRawDump marks a raw_tdx landing failure so callers can log it distinctly
// and, crucially, avoid caching a Last-Modified that would mask the failure.
var errRawDump = errors.New("raw dump failed")

// rawTDXTables is the whitelist of raw_tdx landing tables. Table and partition
// names are interpolated into SQL, so they must never come from input — only
// from this set (and rawDumpTarget, which produces a subset).
//
// bus_stop and tra_traintype are currently unused: neither is fetched by the
// ingestor nor read by any loader (train-type data arrives inside the daily
// timetables). Their whitelist entries and DDL are kept — the tables may already
// exist on Azure and dropping them is not worth the migration.
var rawTDXTables = map[string]bool{
	"bus_route": true, "bus_stopofroute": true, "bus_shape": true,
	"bus_schedule": true, "bus_station": true, "bus_stationgroup": true,
	"bus_stop": true, "bus_operator": true, "bus_routefare": true, // bus_stop: unused
	"bus_dailytimetable": true, "bike_station": true, "metro_station": true,
	"metro_schedule": true, "metro_odfare": true, "tra_odfare": true,
	"tra_dailytimetable": true, "tra_traintype": true, "thsr_station": true, // tra_traintype: unused
	"thsr_dailytimetable": true, "tra_station": true, "thsr_odfare": true,
}

// validateRawTarget guards the raw_tdx landing: it rejects any table not in the
// rawTDXTables whitelist and any partition column other than "" / "city" /
// "system" / "traindate". Table and partition names are interpolated into SQL,
// so this is the injection barrier — never relax it to accept caller-supplied
// identifiers.
func validateRawTarget(table, partCol string) error {
	if !rawTDXTables[table] {
		return fmt.Errorf("%w: table %q not whitelisted", errRawDump, table)
	}
	if partCol != "" && partCol != "city" && partCol != "system" && partCol != "traindate" {
		return fmt.Errorf("%w: partition column %q not allowed", errRawDump, partCol)
	}
	return nil
}

// rawPartitionWhere builds the partition WHERE clause for a raw_tdx landing
// table. Callers pass values already cleared by validateRawTarget, so table and
// partCol are safe to interpolate. thsr_dailytimetable.traindate is timestamptz
// landed at Taipei midnight (tra_dailytimetable.traindate is plain text), so
// comparing it to a YYYY-MM-DD string under the services' UTC session matches
// nothing; select by Taipei calendar date instead so the right partition is
// found regardless of the session TimeZone.
func rawPartitionWhere(table, partCol string) string {
	if table == "thsr_dailytimetable" {
		return "WHERE (traindate AT TIME ZONE 'Asia/Taipei')::date = $1::date"
	}
	return fmt.Sprintf("WHERE %s = $1", partCol)
}

// rawDeleteSQL builds the per-partition DELETE for a raw_tdx landing. table and
// partCol are interpolated, so callers must pass values already cleared by
// validateRawTarget.
func rawDeleteSQL(table, partCol string) string {
	return fmt.Sprintf("DELETE FROM raw_tdx.%s %s", table, rawPartitionWhere(table, partCol))
}

// rawInsertSQL lowercases each object's top-level keys (PascalCase TDX → lowercase
// columns), preserves nested objects/arrays as jsonb, injects context columns, and
// coerces types by column name. It streams the array element-by-element through a
// LATERAL jsonb_populate_record rather than materialising one giant lowercased
// jsonb_agg array and re-parsing it in a single jsonb_populate_recordset — that
// intermediate is O(payload) memory and was the long pole on the largest table
// (tra_odfare, ~every station pair): the single-statement build overran the landing
// deadline. An empty TDX array yields zero elements → a clean 0-row insert.
func rawInsertSQL(table string) string {
	return fmt.Sprintf(`INSERT INTO raw_tdx.%s
SELECT r.* FROM jsonb_array_elements($2::jsonb) elem,
  LATERAL jsonb_populate_record(NULL::raw_tdx.%s,
    (SELECT jsonb_object_agg(lower(e.k), e.v) FROM jsonb_each(elem) AS e(k,v)) || $1::jsonb) r`, table, table)
}

// dumpRawTDX lands a raw TDX JSON array into raw_tdx.<table>. Partitioned tables
// replace their partition (DELETE WHERE col=val); unpartitioned tables are
// TRUNCATE'd. A dump failure is an ingestion failure and is returned as an error:
// the caller must NOT advance the Last-Modified / If-Modified-Since cache unless
// the dump succeeds, otherwise a later 304 would leave raw_tdx permanently stale.
func dumpRawTDX(ctx context.Context, table, partCol, partVal string, body []byte) error {
	if ingestDB == nil {
		return fmt.Errorf("%w: ingestDB is nil", errRawDump)
	}
	if err := validateRawTarget(table, partCol); err != nil {
		return err
	}
	if len(body) == 0 {
		body = []byte("[]")
	}
	return obs.Retry(ctx, 3, 2*time.Second, func() error {
		return obs.Transient(landRawTDX(ctx, table, partCol, partVal, body))
	})
}

// landRawTDX runs one raw_tdx landing transaction, bounded by its own timeout so
// a dead Azure peer cannot block the pgx socket read indefinitely (there is no
// server statement_timeout, and TCP keepalive is too slow to notice). On timeout
// pgx cancels the query; dumpRawTDX retries, and if all attempts fail the caller
// leaves the IMS cache un-advanced so this partition refetches next run.
func landRawTDX(ctx context.Context, table, partCol, partVal string, body []byte) error {
	ctx, cancel := context.WithTimeout(ctx, 3*time.Minute)
	defer cancel()

	tx, err := ingestDB.Begin(ctx)
	if err != nil {
		return fmt.Errorf("%w: begin: %v", errRawDump, err)
	}
	// Roll back on a context independent of ctx: if this attempt was cancelled by
	// the deadline above, a Rollback(ctx) would be a no-op and the TRUNCATE/DELETE's
	// lock would linger, blocking the next retry's TRUNCATE until its own deadline.
	defer func() {
		rbCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = tx.Rollback(rbCtx)
	}()

	// Bound lock waits so a held lock fails this attempt fast (retryable) instead of
	// stalling TRUNCATE/DELETE for the full landing deadline.
	if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout = '20s'"); err != nil {
		return fmt.Errorf("%w: set lock_timeout: %v", errRawDump, err)
	}

	inject := "{}"
	if partCol != "" {
		if _, err := tx.Exec(ctx, rawDeleteSQL(table, partCol), partVal); err != nil {
			return fmt.Errorf("%w: delete partition: %v", errRawDump, err)
		}
		b, _ := json.Marshal(map[string]string{partCol: partVal})
		inject = string(b)
	} else if _, err := tx.Exec(ctx, fmt.Sprintf("TRUNCATE raw_tdx.%s", table)); err != nil {
		return fmt.Errorf("%w: truncate: %v", errRawDump, err)
	}
	rows, err := insertRawChunks(ctx, func(ctx context.Context, sql string, args ...any) (int64, error) {
		ct, err := tx.Exec(ctx, sql, args...)
		if err != nil {
			return 0, err
		}
		return ct.RowsAffected(), nil
	}, table, inject, body)
	if err != nil {
		return fmt.Errorf("%w: insert: %v", errRawDump, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("%w: commit: %v", errRawDump, err)
	}
	log.Infof("[RAW_TDX] table=%s rows=%d event=success", table, rows)
	return nil
}

// rawChunkBytes bounds the JSON slice bound to one INSERT during a raw_tdx
// landing. The server parses each jsonb bind parameter in backend-private
// memory (not bounded by work_mem), so binding a whole payload in one
// statement scales server memory with payload size — which OOM-crashed the
// 2GB B1ms Azure server. 4MB keeps per-statement parse memory trivial.
const rawChunkBytes = 4 << 20

// insertRawChunks streams the landed JSON array into raw_tdx.<table> in
// rawChunkBytes slices via exec (one INSERT per slice, all inside the caller's
// transaction), so server-side parse memory is bounded by the chunk size
// rather than the payload. An element larger than rawChunkBytes still lands as
// its own single-element chunk. An empty array issues one 0-row insert,
// matching the previous single-statement behavior; a non-array payload is an
// error, as it was under jsonb_array_elements.
func insertRawChunks(ctx context.Context, exec func(context.Context, string, ...any) (int64, error), table, inject string, body []byte) (int64, error) {
	dec := json.NewDecoder(bytes.NewReader(body))
	if tok, err := dec.Token(); err != nil || tok != json.Delim('[') {
		return 0, fmt.Errorf("payload is not a JSON array (token %v): %v", tok, err)
	}
	sql := rawInsertSQL(table)
	chunk := append(make([]byte, 0, rawChunkBytes+(1<<20)), '[')
	var rows int64
	flush := func() error {
		n, err := exec(ctx, sql, inject, append(chunk, ']'))
		if err != nil {
			return err
		}
		rows += n
		chunk = chunk[:1]
		return nil
	}
	flushed := false
	for dec.More() {
		var elem json.RawMessage
		if err := dec.Decode(&elem); err != nil {
			return rows, fmt.Errorf("decode array element: %v", err)
		}
		if len(chunk) > 1 {
			chunk = append(chunk, ',')
		}
		chunk = append(chunk, elem...)
		if len(chunk) >= rawChunkBytes {
			if err := flush(); err != nil {
				return rows, err
			}
			flushed = true
		}
	}
	if len(chunk) > 1 || !flushed {
		if err := flush(); err != nil {
			return rows, err
		}
	}
	return rows, nil
}

// busstaticmp loads the per-stop station map for a city prefix: every stop of
// every subroute joined to its station group and coordinates. busEta uses it to
// attach live ETAs to stops and to group stops under a shared station. Rows that
// fail to scan are logged and skipped rather than aborting the whole load.
func busstaticmp(ctx context.Context, db *pgxpool.Pool, city string) ([]busStationmap, error) {
	query := `SELECT bssm.station_id, bssm.station_name,
	                 COALESCE(bsgm.group_uid, bssm.station_id),
	                 COALESCE(bg.group_name, bssm.station_name),
	                 bssm.sub_route_uid, bssm.route_name,
	                 bssm.direction, bssm.stop_uid, bssm.stop_sequence,
	                 COALESCE(ST_Y(bs.position), 0), COALESCE(ST_X(bs.position), 0)
	          FROM bus_station_stop_map bssm
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
			&temp.GroupName, &temp.SubRouteUID, &temp.SubRouteName, &temp.Direction, &temp.StopUID, &temp.StopSequence,
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
