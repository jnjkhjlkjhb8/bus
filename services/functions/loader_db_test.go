package main

import (
	"context"
	"encoding/json"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
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
