package main

import (
	"context"
	"encoding/json"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"google.golang.org/protobuf/proto"
)

// loaderTestPool connects to the DATABASE_URL cluster and skips when it is unset
// or the raw_tdx schema is not provisioned, mirroring the dumpRawTDX DB tests.
func loaderTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set; skipping loader integration test")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	var provisioned bool
	if err := pool.QueryRow(context.Background(),
		"SELECT to_regclass('raw_tdx.bus_route') IS NOT NULL").Scan(&provisioned); err != nil {
		pool.Close()
		t.Fatalf("probe raw_tdx schema: %v", err)
	}
	if !provisioned {
		pool.Close()
		t.Skip("raw_tdx schema not provisioned; skipping loader integration test")
	}
	return pool
}

// TestRawTDXSourceStripsBookkeeping lands a partitioned row and asserts the
// reconstructed element carries the TDX fields but neither the partition column
// (city) nor fetched_at, and that MAX(fetched_at) comes back fresh.
func TestRawTDXSourceStripsBookkeeping(t *testing.T) {
	pool := loaderTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	prev := ingestDB
	ingestDB = pool
	defer func() { ingestDB = prev }()

	const city = "ZZ_LOAD_CITY"
	cleanup := func() { _, _ = pool.Exec(ctx, "DELETE FROM raw_tdx.bus_route WHERE city=$1", city) }
	cleanup()
	defer cleanup()

	body := []byte(`[{"RouteUID":"ZZR1","RouteName":{"Zh_tw":"測"},"VersionID":7}]`)
	if err := dumpRawTDX(ctx, "bus_route", "city", city, body); err != nil {
		t.Fatalf("land: %v", err)
	}

	src := rawTDXSource{pool: pool}
	arr, fetchedAt, err := src.datasetJSON(ctx, "bus_route", "city", city)
	if err != nil {
		t.Fatalf("datasetJSON: %v", err)
	}
	if isStale(fetchedAt) {
		t.Fatalf("just-landed partition reported stale (fetched_at=%s)", fetchedAt)
	}
	var elems []map[string]json.RawMessage
	if err := json.Unmarshal(arr, &elems); err != nil {
		t.Fatalf("unmarshal reconstructed array: %v", err)
	}
	if len(elems) != 1 {
		t.Fatalf("got %d elements, want 1", len(elems))
	}
	if _, ok := elems[0]["fetched_at"]; ok {
		t.Fatal("fetched_at leaked into reconstructed element")
	}
	if _, ok := elems[0]["city"]; ok {
		t.Fatal("partition column city leaked into reconstructed element")
	}
	// Lowercased TDX keys survive (jsonb columns) and decode into the transform
	// structs (json.Unmarshal is case-insensitive).
	if _, ok := elems[0]["routeuid"]; !ok {
		t.Fatalf("routeuid missing from reconstructed element: %s", arr)
	}
}

// TestRawTDXSourceEmptyPartitionIsStale asserts an absent partition yields "[]"
// and an epoch fetched_at that isStale treats as stale (so the loader skips it).
func TestRawTDXSourceEmptyPartitionIsStale(t *testing.T) {
	pool := loaderTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	src := rawTDXSource{pool: pool}
	arr, fetchedAt, err := src.datasetJSON(ctx, "bus_route", "city", "ZZ_NO_SUCH_CITY")
	if err != nil {
		t.Fatalf("datasetJSON: %v", err)
	}
	if string(arr) != "[]" {
		t.Fatalf("empty partition array = %s, want []", arr)
	}
	if !isStale(fetchedAt) {
		t.Fatal("empty partition should be stale (epoch fetched_at)")
	}
}

// TestRawTDXSourceTHSRTraindateNormalized guards the #1 drift risk: the
// thsr_dailytimetable.traindate column is timestamptz, so to_jsonb would
// serialize it as a full timestamp, but the transform's train_date temp column is
// a date and the original TDX TrainDate was "YYYY-MM-DD". datasetJSON must
// re-derive the date-only form so loadThsrTimetable decodes the value it always
// historically saw.
func TestRawTDXSourceTHSRTraindateNormalized(t *testing.T) {
	pool := loaderTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	prev := ingestDB
	ingestDB = pool
	defer func() { ingestDB = prev }()

	const date = "2026-07-04"
	cleanup := func() {
		_, _ = pool.Exec(ctx, "DELETE FROM raw_tdx.thsr_dailytimetable WHERE traindate = $1", date)
	}
	cleanup()
	defer cleanup()

	body := []byte(`[{"TrainDate":"2026-07-04","DailyTrainInfo":{"TrainNo":"0101"},"StopTimes":[],"VersionID":1}]`)
	if err := dumpRawTDX(ctx, "thsr_dailytimetable", "traindate", date, body); err != nil {
		t.Fatalf("land: %v", err)
	}

	src := rawTDXSource{pool: pool}
	arr, _, err := src.datasetJSON(ctx, "thsr_dailytimetable", "traindate", date)
	if err != nil {
		t.Fatalf("datasetJSON: %v", err)
	}
	var elems []struct {
		TrainDate string `json:"traindate"`
	}
	if err := json.Unmarshal(arr, &elems); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(elems) != 1 {
		t.Fatalf("got %d elements, want 1: %s", len(elems), arr)
	}
	if elems[0].TrainDate != date {
		t.Fatalf("traindate = %q, want %q (timestamptz not normalized to date)", elems[0].TrainDate, date)
	}
	// The value must also parse into the transform's TrainDate string as a date.
	if _, err := time.Parse("2006-01-02", elems[0].TrainDate); err != nil {
		t.Fatalf("traindate not a bare date: %v", err)
	}
}

// TestRunLoadThroughRawTDXSource exercises the full seam end to end: land a TRA
// station partition, then run the tra_station loader spec through runLoad against
// the raw_tdx source and assert the transform wrote the env-schema table.
func TestRunLoadThroughRawTDXSource(t *testing.T) {
	pool := loaderTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	prev := ingestDB
	ingestDB = pool
	defer func() { ingestDB = prev }()

	// tra_station is unpartitioned (TRUNCATE lifecycle); skip if the env-schema
	// sink table is absent (fresh raw_tdx-only DB has no tra_stations).
	var sink bool
	if err := pool.QueryRow(ctx, "SELECT to_regclass('tra_stations') IS NOT NULL").Scan(&sink); err != nil {
		t.Fatalf("probe sink: %v", err)
	}
	if !sink {
		t.Skip("tra_stations env table absent; skipping end-to-end loader test")
	}

	const sid = "ZZ_LOAD_STATION"
	sinkCleanup := func() { _, _ = pool.Exec(ctx, "DELETE FROM tra_stations WHERE station_id=$1", sid) }
	sinkCleanup()
	defer sinkCleanup()

	body := []byte(`[{"StationID":"ZZ_LOAD_STATION","StationName":{"Zh_tw":"測站"},"LocationCityCode":"TPE","StationPosition":{"PositionLon":121.5,"PositionLat":25.0},"StationCode":"Z1"}]`)
	if err := dumpRawTDX(ctx, "tra_station", "", "", body); err != nil {
		t.Fatalf("land: %v", err)
	}
	defer func() { _, _ = pool.Exec(ctx, "TRUNCATE raw_tdx.tra_station") }()

	src := rawTDXSource{pool: pool}
	if err := runLoad(ctx, src, pool, nil, []string{"tra_station"}); err != nil {
		t.Fatalf("runLoad: %v", err)
	}
	var n int
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM tra_stations WHERE station_id=$1", sid).Scan(&n); err != nil {
		t.Fatalf("count sink: %v", err)
	}
	if n != 1 {
		t.Fatalf("tra_stations rows = %d, want 1", n)
	}
}

// provisionBusSinks creates the env-schema tables loadBus writes on the
// operator/fare assertion path (stop composite type, bus_subroutes,
// bus_operators, raw_bus_route staging, bus_static, bus_station_stop_map,
// bus_schedule). The throwaway loader cluster is raw_tdx-only and has no
// PostGIS, so bus_stations / bus_station_groups are intentionally omitted:
// savestations / saveStationGroups run in their own transactions, log the
// missing-relation error, and do not abort loadBus — the assertion path
// (bus_subroutes + bus_operators + bus_static.pb) does not touch them. Column
// shapes mirror the production upsert targets (busSubroutesUpsertSQL,
// busScheduleUpsertSQL, savestatictodb, loadBusOperators).
func provisionBusSinks(t *testing.T, ctx context.Context, pool *pgxpool.Pool) {
	t.Helper()
	ddl := []string{
		`DO $$ BEGIN
			CREATE TYPE stop AS (station_uid text, stop_name text, stop_sequence int, position_lon float, position_lat float);
		EXCEPTION WHEN duplicate_object THEN NULL; END $$`,
		`CREATE TABLE IF NOT EXISTS bus_operators (
			operator_id text NOT NULL, authority_code text NOT NULL,
			operator_name text NOT NULL, operator_phone text, operator_url text,
			updated_at timestamptz NOT NULL DEFAULT NOW(),
			PRIMARY KEY (operator_id, authority_code))`,
		`CREATE TABLE IF NOT EXISTS raw_bus_route (
			sub_route_uid text NOT NULL, direction smallint NOT NULL,
			route_uid text, route_name text, sub_route_name text,
			depart text, destin text, type text NOT NULL, content jsonb NOT NULL,
			created_at timestamptz,
			PRIMARY KEY (sub_route_uid, direction, type))`,
		`CREATE TABLE IF NOT EXISTS bus_subroutes (
			sub_route_uid text NOT NULL, route_uid text, direction smallint NOT NULL,
			route_name text, sub_route_name text, city text, depart text, destin text,
			geometry text, stops stop[], schedule jsonb, operators jsonb,
			updated_at timestamptz NOT NULL DEFAULT NOW(),
			PRIMARY KEY (sub_route_uid, direction))`,
		`CREATE TABLE IF NOT EXISTS bus_static (
			sub_route_name text, route_name text, sub_route_uid text PRIMARY KEY,
			route_uid text, city text, depart text, destin text, pb bytea,
			updated_at timestamptz NOT NULL DEFAULT NOW())`,
		`CREATE TABLE IF NOT EXISTS bus_station_stop_map (
			station_id text, station_name text, sub_route_uid text, route_name text,
			direction int, stop_uid text, stop_sequence int,
			updated_at timestamptz NOT NULL DEFAULT NOW(),
			PRIMARY KEY (sub_route_uid, stop_uid, direction))`,
		`CREATE TABLE IF NOT EXISTS bus_schedule (
			sub_route_uid text, direction smallint, type bool, tripid text,
			islowfloor bool, stopsequence smallint,
			"stop_uid/MinHeadwayMins" text, "stop_name/MaxHeadwayMins" text,
			"arrival_time/StartTime" time, "departure_time/EndTime" time,
			service_day smallint, updated_at timestamptz NOT NULL DEFAULT NOW(),
			PRIMARY KEY (sub_route_uid, direction, type, service_day, tripid, "stop_uid/MinHeadwayMins"))`,
	}
	for _, s := range ddl {
		if _, err := pool.Exec(ctx, s); err != nil {
			t.Fatalf("provision sink: %v\nDDL: %s", err, s)
		}
	}
}

// TestLoadBusEnrichesFromRawTDX is the loadBus per-spec coverage: it lands
// route/stop/operator/fare fixtures for one city into raw_tdx, provisions the
// env-schema sinks, then runs the bus_operator and bus specs together through
// runLoad. It asserts (1) a bus_subroutes row exists carrying the operator
// detail (proving loadBusOperatorMap read the standalone spec's upsert back from
// bus_operators) and (2) the bus_static.pb proto carries the Fare (proving
// loadBusFareMaps enrichment flowed through), and (3) bus_operators holds
// exactly one row for the fixture operator (proving a single upsert path, not
// the old double upsert).
func TestLoadBusEnrichesFromRawTDX(t *testing.T) {
	pool := loaderTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	prev := ingestDB
	ingestDB = pool
	defer func() { ingestDB = prev }()

	provisionBusSinks(t, ctx, pool)

	// Keelung (prefix KEE) so citymap/makethatsame/fare-prefix logic resolves.
	// makethatsame is identity for non-InterCity, so the subroute UID is the raw
	// SubRouteUID "KEE100", and the fare's SubRouteID "100" resolves to KEE+100.
	const city = "Keelung"
	const subUID = "KEE100"
	const opID = "ZZ_LOAD_OP"

	cleanup := func() {
		for _, tbl := range []string{"bus_route", "bus_stopofroute", "bus_shape", "bus_schedule", "bus_station", "bus_stationgroup", "bus_operator", "bus_routefare"} {
			_, _ = pool.Exec(ctx, "DELETE FROM raw_tdx."+tbl+" WHERE city=$1", city)
		}
		_, _ = pool.Exec(ctx, "DELETE FROM bus_subroutes WHERE sub_route_uid=$1", subUID)
		_, _ = pool.Exec(ctx, "DELETE FROM bus_static WHERE sub_route_uid=$1", subUID)
		_, _ = pool.Exec(ctx, "DELETE FROM raw_bus_route WHERE route_uid='KEE1'")
		_, _ = pool.Exec(ctx, "DELETE FROM bus_operators WHERE operator_id=$1", opID)
	}
	cleanup()
	defer cleanup()

	// Fixture: one route with one operator-referencing subroute, its operator
	// registry entry, and a matching subroute fare. Empty arrays for the bus
	// datasets loadBus reads but this fixture does not exercise.
	land := func(table, body string) {
		if err := dumpRawTDX(ctx, table, "city", city, []byte(body)); err != nil {
			t.Fatalf("land %s: %v", table, err)
		}
	}
	land("bus_route", `[{"RouteUID":"KEE1","RouteName":{"Zh_tw":"1路"},"Operators":[{"OperatorID":"ZZ_LOAD_OP"}],"SubRoutes":[{"SubRouteUID":"KEE100","SubRouteName":{"Zh_tw":"1路"},"Direction":0}]}]`)
	land("bus_stopofroute", `[{"RouteUID":"KEE1","SubRouteUID":"KEE100","Direction":0,"Stops":[{"StopUID":"KEE_S1","StopName":{"Zh_tw":"站一"},"StopSequence":1,"StationID":"KEE_ST1","StopPosition":{"PositionLon":121.7,"PositionLat":25.1}}]}]`)
	land("bus_shape", `[]`)
	land("bus_schedule", `[]`)
	land("bus_station", `[]`)
	land("bus_stationgroup", `[]`)
	land("bus_operator", `[{"OperatorID":"ZZ_LOAD_OP","OperatorName":{"Zh_tw":"測運"},"OperatorPhone":"02-1234","OperatorUrl":"https://ex","AuthorityCode":"KEE"}]`)
	land("bus_routefare", `[{"RouteID":"KEE1","SubRouteID":"100","FarePricingType":1,"IsFreeBus":0}]`)

	// loadBus clears the legacy Redis static cache; point at an unreachable addr
	// with tiny timeouts so the Del calls log-and-continue instead of blocking (no
	// live Redis needed for this DB-path test), matching ingestor_test.go.
	rc := redis.NewClient(&redis.Options{
		Addr:         "127.0.0.1:1",
		DialTimeout:  time.Millisecond,
		ReadTimeout:  time.Millisecond,
		WriteTimeout: time.Millisecond,
		MaxRetries:   0,
	})
	defer rc.Close()

	src := rawTDXSource{pool: pool}
	if err := runLoad(ctx, src, pool, rc, []string{"bus_operator", "bus"}); err != nil {
		t.Fatalf("runLoad: %v", err)
	}

	// (1) subroute row exists with operator detail embedded.
	var opsJSON []byte
	if err := pool.QueryRow(ctx, "SELECT operators FROM bus_subroutes WHERE sub_route_uid=$1", subUID).Scan(&opsJSON); err != nil {
		t.Fatalf("read bus_subroutes: %v", err)
	}
	if !strings.Contains(string(opsJSON), opID) {
		t.Fatalf("bus_subroutes.operators = %s, want it to contain operator %s", opsJSON, opID)
	}

	// (2) the serialized proto in bus_static carries the fare (fare is embedded in
	// the proto blob, not a bus_subroutes column).
	var pb []byte
	if err := pool.QueryRow(ctx, "SELECT pb FROM bus_static WHERE sub_route_uid=$1", subUID).Scan(&pb); err != nil {
		t.Fatalf("read bus_static.pb: %v", err)
	}
	var sub models.BusSubroute
	if err := proto.Unmarshal(pb, &sub); err != nil {
		t.Fatalf("unmarshal bus_static.pb: %v", err)
	}
	if sub.Fare == nil {
		t.Fatal("bus_static.pb subroute has nil Fare; fare enrichment did not flow")
	}
	if len(sub.Operators) == 0 {
		t.Fatal("bus_static.pb subroute has no Operators; operator enrichment did not flow")
	}

	// (3) bus_operators has exactly one row for the fixture operator: the single
	// upsert path (standalone bus_operator spec), not the old double upsert.
	var opRows int
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM bus_operators WHERE operator_id=$1", opID).Scan(&opRows); err != nil {
		t.Fatalf("count bus_operators: %v", err)
	}
	if opRows != 1 {
		t.Fatalf("bus_operators rows for %s = %d, want 1", opID, opRows)
	}
}
