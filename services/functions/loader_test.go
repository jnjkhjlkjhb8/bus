package main

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"google.golang.org/protobuf/proto"
)

// fakeLoadSource serves fixed JSON per (table,partVal) and a fixed fetched_at.
// It is the loadSource seam's in-memory adapter for unit tests.
type fakeLoadSource struct {
	json    map[string][]byte // key: table + "|" + partVal
	fetched time.Time
	calls   []string
}

func (f *fakeLoadSource) datasetJSON(_ context.Context, table, _, partVal string) ([]byte, time.Time, error) {
	f.calls = append(f.calls, table+"|"+partVal)
	b, ok := f.json[table+"|"+partVal]
	if !ok {
		return []byte("[]"), f.fetched, nil
	}
	return b, f.fetched, nil
}

func TestStalenessCheckSkips(t *testing.T) {
	// A partition older than the 27h threshold must be skipped, not loaded.
	if !isStale(time.Now().Add(-28 * time.Hour)) {
		t.Fatal("28h old partition should be stale")
	}
	if isStale(time.Now().Add(-1 * time.Hour)) {
		t.Fatal("1h old partition should be fresh")
	}
}

// railDateWindow feeds both the ingestor's landing partitions and the loader's
// read partitions; an off-by-one here silently drops the first or last landed
// timetable date from every load.
func TestRailDateWindow(t *testing.T) {
	// Sample today before and after the call so the assertion cannot flake if
	// the test straddles midnight.
	before := time.Now().Format(time.DateOnly)
	got := railDateWindow(2)
	after := time.Now().Format(time.DateOnly)
	if len(got) != 3 {
		t.Fatalf("railDateWindow(2) returned %d entries, want 3", len(got))
	}
	if got[0] != before && got[0] != after {
		t.Fatalf("railDateWindow(2)[0] = %s, want today (%s or %s)", got[0], before, after)
	}
	first, err := time.Parse(time.DateOnly, got[0])
	if err != nil {
		t.Fatal(err)
	}
	for i, d := range got {
		if want := first.AddDate(0, 0, i).Format(time.DateOnly); d != want {
			t.Fatalf("railDateWindow(2)[%d] = %s, want %s", i, d, want)
		}
	}
	if single := railDateWindow(0); len(single) != 1 {
		t.Fatalf("railDateWindow(0) = %v, want exactly one entry", single)
	}
}

func TestRunLoadIteratesPartitionsAndDecodes(t *testing.T) {
	// A registry spec with two partitions must invoke datasetJSON once per
	// partition and hand each a decoder positioned at the array.
	src := &fakeLoadSource{
		json: map[string][]byte{
			"probe|A": []byte(`[{"x":1}]`),
			"probe|B": []byte(`[{"x":2},{"x":3}]`),
		},
		fetched: time.Now(),
	}
	var seen []int
	spec := loadSpec{
		key: "probe", table: "probe", partCol: "city",
		partitions: func() []string { return []string{"A", "B"} },
		load: func(_ context.Context, dec *json.Decoder, _ loadSink, _ string) error {
			if _, err := dec.Token(); err != nil { // opening '['
				return err
			}
			for dec.More() {
				var m struct {
					X int `json:"x"`
				}
				if err := dec.Decode(&m); err != nil {
					return err
				}
				seen = append(seen, m.X)
			}
			return nil
		},
	}
	if err := runLoadSpecs(context.Background(), src, nil, nil, []loadSpec{spec}); err != nil {
		t.Fatalf("runLoadSpecs: %v", err)
	}
	if len(seen) != 3 || seen[0] != 1 || seen[1] != 2 || seen[2] != 3 {
		t.Fatalf("decoded values = %v, want [1 2 3]", seen)
	}
	if len(src.calls) != 2 || src.calls[0] != "probe|A" || src.calls[1] != "probe|B" {
		t.Fatalf("datasetJSON calls = %v", src.calls)
	}
}

func TestRunLoadSkipsStalePartition(t *testing.T) {
	src := &fakeLoadSource{
		json:    map[string][]byte{"probe|A": []byte(`[{"x":1}]`)},
		fetched: time.Now().Add(-40 * time.Hour), // stale
	}
	loaded := false
	spec := loadSpec{
		key: "probe", table: "probe", partCol: "city",
		partitions: func() []string { return []string{"A"} },
		load: func(_ context.Context, _ *json.Decoder, _ loadSink, _ string) error {
			loaded = true
			return nil
		},
	}
	if err := runLoadSpecs(context.Background(), src, nil, nil, []loadSpec{spec}); err != nil {
		t.Fatalf("runLoadSpecs: %v", err)
	}
	if loaded {
		t.Fatal("stale partition must be skipped, load ran anyway")
	}
}

func TestLoaderRegistryKeysUnique(t *testing.T) {
	seen := map[string]bool{}
	for _, s := range loaderRegistry(nil) {
		if seen[s.key] {
			t.Fatalf("duplicate registry key %q", s.key)
		}
		seen[s.key] = true
	}
}

func TestLoaderExceptionalBindingsUseSemanticSink(t *testing.T) {
	tests := []struct {
		key       string
		operation string
		part      string
	}{
		{key: "bus_operator", operation: "bus operators", part: "Taipei"},
		{key: "bus", operation: "bus city assembly", part: "Taipei"},
		{key: "bus_dailytimetable", operation: "bus daily timetable", part: "Taipei"},
		{key: "mrt_odfare", operation: "MRT journey matrix", part: "TRTC"},
		{key: "mrt_trtc_traveltime", operation: "MRT travel time", part: "TRTC"},
		{key: "thsr_station", operation: "THSR stations", part: ""},
	}
	bindings := loaderTransforms(&fakeLoadSource{})
	for _, tt := range tests {
		t.Run(tt.key, func(t *testing.T) {
			sink := &fakeLoadSink{}
			dec := json.NewDecoder(bytes.NewReader([]byte("[]")))
			if err := bindings[tt.key].load(context.Background(), dec, sink, tt.part); err != nil {
				t.Fatalf("load: %v", err)
			}
			if len(sink.semanticCalls) != 1 {
				t.Fatalf("semantic calls = %v, want one %q call", sink.semanticCalls, tt.operation)
			}
			got := sink.semanticCalls[0]
			if got.operation != tt.operation || got.part != tt.part {
				t.Fatalf("semantic call = %+v, want operation %q part %q", got, tt.operation, tt.part)
			}
		})
	}
}

// TestLoadBusDailyTimetableWritesRedis feeds a daily-timetable array to the
// shared assembly function and asserts it lands the reconstructed protobuf under
// bus_daily_timetable:<subRouteUID> with the expected TTL, exercising the loader
// path that closes the legacy busDailyroute Redis gap. It needs a local Redis
// (127.0.0.1:6379) and skips when one is not reachable, mirroring the DB-gated
// tests' skip posture.
func TestLoadBusDailyTimetableWritesRedis(t *testing.T) {
	rc := redis.NewClient(&redis.Options{
		Addr:        "127.0.0.1:6379",
		DialTimeout: 200 * time.Millisecond,
		MaxRetries:  0,
	})
	defer rc.Close()
	if err := rc.Ping().Err(); err != nil {
		t.Skipf("local Redis not reachable; skipping: %v", err)
	}

	const uid = "ZZ_DTT_SUB1"
	key := "bus_daily_timetable:" + uid
	_ = rc.Del(key).Err()
	defer func() { _ = rc.Del(key).Err() }()

	body := []byte(`[{"SubRouteUID":"` + uid + `","Direction":0,"Timetables":[{"TripID":"T1","IsLowFloor":true,"StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`)
	dec := json.NewDecoder(bytes.NewReader(body))
	if err := loadBusDailyTimetable(context.Background(), dec, nil, rc, "Kaohsiung"); err != nil {
		t.Fatalf("loadBusDailyTimetable: %v", err)
	}

	pb, err := rc.Get(key).Bytes()
	if err != nil {
		t.Fatalf("read %s: %v", key, err)
	}
	var got models.Bus_DailyTimetables
	if err := proto.Unmarshal(pb, &got); err != nil {
		t.Fatalf("unmarshal proto: %v", err)
	}
	if got.SubRouteUID != uid {
		t.Fatalf("SubRouteUID = %q, want %q", got.SubRouteUID, uid)
	}
	dir0, ok := got.Direction[0]
	if !ok || len(dir0.DailyTimetables) != 1 {
		t.Fatalf("direction 0 timetables = %+v, want one entry", got.Direction)
	}
	if dir0.DailyTimetables[0].TripID != "T1" || len(dir0.DailyTimetables[0].StopTimes) != 1 {
		t.Fatalf("assembled trip = %+v, want TripID T1 with one stop", dir0.DailyTimetables[0])
	}
	ttl := rc.TTL(key).Val()
	if ttl <= 23*time.Hour || ttl > 23*time.Hour+30*time.Minute {
		t.Fatalf("TTL = %s, want ~23h30m", ttl)
	}
}

// fixtureSource reads committed raw_tdx array fixtures from testdata/raw_tdx/,
// keyed by table name. It is the loadSource seam's file adapter for replay tests:
// the fixtures were exported by scripts/export-fixtures using the same
// reconstruction contract as rawTDXSource (lowercased keys, no fetched_at), so a
// committed fixture replays byte-identically through the loader with no network.
type fixtureSource struct {
	dir     string
	fetched time.Time
}

func (f fixtureSource) datasetJSON(_ context.Context, table, _, _ string) ([]byte, time.Time, error) {
	b, err := os.ReadFile(filepath.Join(f.dir, table+".json"))
	if err != nil {
		// Absent fixture → empty array, treated as fresh so the transform runs on
		// zero rows rather than being staleness-skipped.
		return []byte("[]"), f.fetched, nil
	}
	return b, f.fetched, nil
}

// provisionThsrStationSink creates the thsr_stations env-schema sink on the
// raw_tdx-only loader cluster. That cluster has no PostGIS, but loadThsrStation
// calls ST_GeomFromText; a text-returning stub of that function plus a text geom
// column lets the real transform run unmodified. Mirrors provisionBusSinks'
// posture of creating sinks in-test on the throwaway cluster.
func provisionThsrStationSink(t *testing.T, ctx context.Context, pool *pgxpool.Pool) {
	t.Helper()
	ddl := []string{
		`CREATE OR REPLACE FUNCTION ST_GeomFromText(wkt text, srid int) RETURNS text
			LANGUAGE sql IMMUTABLE AS 'SELECT wkt'`,
		`CREATE TABLE IF NOT EXISTS thsr_stations (
			station_id text PRIMARY KEY,
			name text,
			city text,
			geom text,
			stationcode text,
			updated_at timestamptz NOT NULL DEFAULT NOW())`,
	}
	for _, s := range ddl {
		if _, err := pool.Exec(ctx, s); err != nil {
			t.Fatalf("provision thsr_stations sink: %v\nDDL: %s", err, s)
		}
	}
}

// TestLoaderReplayThsrStation replays the committed thsr_station fixture through
// the real loadThsrStation transform via runLoad and asserts the sink rows,
// exercising the second loadSource adapter (fixtureSource) end to end with no
// network. loadThsrStation's ON CONFLICT (station_id) upsert makes the replay
// idempotent, so re-running is safe.
func TestLoaderReplayThsrStation(t *testing.T) {
	pool := loaderTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	prev := ingestDB
	ingestDB = pool
	defer func() { ingestDB = prev }()

	provisionThsrStationSink(t, ctx, pool)
	cleanup := func() {
		_, _ = pool.Exec(ctx, "DELETE FROM thsr_stations WHERE station_id IN ('0990','1000')")
	}
	cleanup()
	defer cleanup()

	src := fixtureSource{dir: "testdata/raw_tdx", fetched: time.Now()}
	if err := runLoad(ctx, src, pool, nil, []string{"thsr_station"}); err != nil {
		t.Fatalf("runLoad: %v", err)
	}

	var n int
	if err := pool.QueryRow(ctx,
		"SELECT count(*) FROM thsr_stations WHERE station_id IN ('0990','1000')").Scan(&n); err != nil {
		t.Fatalf("count: %v", err)
	}
	if n != 2 {
		t.Fatalf("loaded %d thsr stations, want 2", n)
	}

	// The reconstructed geom must round-trip the fixture position through the
	// transform's POINT(lon lat) formatting, proving the fixture keys decoded into
	// the railStation struct (not merely that rows appeared).
	var geom string
	if err := pool.QueryRow(ctx,
		"SELECT geom FROM thsr_stations WHERE station_id='0990'").Scan(&geom); err != nil {
		t.Fatalf("read geom: %v", err)
	}
	if geom != "POINT(121.606700 25.053300)" {
		t.Fatalf("geom = %q, want POINT(121.606700 25.053300)", geom)
	}
}
