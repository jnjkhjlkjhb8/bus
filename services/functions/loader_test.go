package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"google.golang.org/protobuf/proto"
)

// fakeLoadSource serves fixed JSON per (table,partVal) and a fixed fetched_at.
// It is the loadSource seam's in-memory adapter for unit tests.
type fakeLoadSource struct {
	json    map[string][]byte // key: table + "|" + partVal
	errs    map[string]error
	fetched time.Time
	calls   []string
}

func (f *fakeLoadSource) datasetJSON(_ context.Context, table, _, partVal string) ([]byte, time.Time, error) {
	f.calls = append(f.calls, table+"|"+partVal)
	if err := f.errs[table+"|"+partVal]; err != nil {
		return nil, time.Time{}, err
	}
	b, ok := f.json[table+"|"+partVal]
	if !ok {
		return []byte("[]"), f.fetched, nil
	}
	return b, f.fetched, nil
}

func TestRunLoadSpecsReturnsJoinedPartitionErrorsAndContinues(t *testing.T) {
	readErr := errors.New("partition read failed")
	transformErr := errors.New("partition transform failed")
	src := &fakeLoadSource{
		json: map[string][]byte{
			"probe|B": []byte(`[{"x":2}]`),
			"probe|C": []byte(`[{"x":3}]`),
		},
		errs:    map[string]error{"probe|A": readErr},
		fetched: time.Now(),
	}
	var loaded []string
	spec := loadSpec{
		key: "probe", table: "probe", partCol: "city",
		partitions: func() []string { return []string{"A", "B", "C"} },
		load: func(_ context.Context, _ *json.Decoder, _ loadSink, part string) error {
			loaded = append(loaded, part)
			if part == "B" {
				return transformErr
			}
			return nil
		},
	}

	_, err := runLoadSpecs(context.Background(), src, nil, nil, []loadSpec{spec})
	if !errors.Is(err, readErr) || !errors.Is(err, transformErr) {
		t.Fatalf("runLoadSpecs error = %v, want joined read and transform errors", err)
	}
	if got, want := src.calls, []string{"probe|A", "probe|B", "probe|C"}; !slices.Equal(got, want) {
		t.Fatalf("dataset calls = %v, want %v", got, want)
	}
	if got, want := loaded, []string{"B", "C"}; !slices.Equal(got, want) {
		t.Fatalf("loaded partitions = %v, want %v", got, want)
	}
}

func TestConfiguredInvalidRawDatabaseURLFailsClosed(t *testing.T) {
	t.Setenv("RAW_DATABASE_URL", "://invalid")
	pool, cleanup, err := rawSourcePool(context.Background(), nil)
	if cleanup != nil {
		cleanup()
	}
	if err == nil {
		t.Fatalf("rawSourcePool returned pool %v and nil error for configured invalid URL", pool)
	}
}

func TestConfiguredUnreachableRawDatabaseURLFailsClosed(t *testing.T) {
	t.Setenv("RAW_DATABASE_URL", "postgres://test:test@127.0.0.1:1/test?connect_timeout=1")
	pool, cleanup, err := rawSourcePool(context.Background(), nil)
	if cleanup != nil {
		cleanup()
	}
	if err == nil {
		t.Fatalf("rawSourcePool returned pool %v and nil error for unreachable configured database", pool)
	}
}

func TestRawSourcePoolHonorsCanceledContext(t *testing.T) {
	t.Setenv("RAW_DATABASE_URL", "postgres://test:test@127.0.0.1:1/test?connect_timeout=30")
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	started := time.Now()
	pool, cleanup, err := rawSourcePool(ctx, nil)
	if cleanup != nil {
		cleanup()
	}
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("rawSourcePool returned pool %v and error %v, want context.Canceled", pool, err)
	}
	if elapsed := time.Since(started); elapsed > time.Second {
		t.Fatalf("rawSourcePool took %v with an already-canceled context", elapsed)
	}
}

func TestRawSourcePoolNormalizesNilContext(t *testing.T) {
	t.Setenv("RAW_DATABASE_URL", "postgres://test:test@127.0.0.1:1/test?connect_timeout=1")
	pool, cleanup, err := rawSourcePool(nil, nil) //nolint:staticcheck // SA1012: the nil context is the input under test
	if cleanup != nil {
		cleanup()
	}
	if err == nil {
		t.Fatalf("rawSourcePool returned pool %v and nil error for unreachable configured database", pool)
	}
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

func TestBusLoaderOrdersInterCityLastAndExcludesLienchiang(t *testing.T) {
	got := busLoadCities()
	if len(got) == 0 || got[len(got)-1] != "InterCity" {
		t.Fatalf("busLoadCities = %v, want InterCity last", got)
	}
	if slices.Contains(got, "LienchiangCounty") {
		t.Fatalf("busLoadCities = %v, must exclude unsupported Lienchiang", got)
	}
	// Landing still covers both partitions; this ordering is load-only.
	landed := allCities()
	if !slices.Contains(landed, "InterCity") || !slices.Contains(landed, "LienchiangCounty") {
		t.Fatalf("allCities = %v, ingest order/coverage was changed", landed)
	}
	for _, spec := range loaderRegistry(&fakeLoadSource{}) {
		if spec.key != "bus" {
			continue
		}
		parts := spec.partitions()
		if !slices.Equal(parts, got) {
			t.Fatalf("%s loader partitions = %v, want %v", spec.key, parts, got)
		}
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
	if _, err := runLoadSpecs(context.Background(), src, nil, nil, []loadSpec{spec}); err != nil {
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
	stats, err := runLoadSpecs(context.Background(), src, nil, nil, []loadSpec{spec})
	if !errors.Is(err, errLoadStale) {
		t.Fatalf("runLoadSpecs error = %v, want errLoadStale", err)
	}
	if stats.failed != 1 || stats.ok != 0 {
		t.Fatalf("stats = %+v, want a landed-but-stale partition counted as failed", stats)
	}
	if loaded {
		t.Fatal("stale partition must be skipped, load ran anyway")
	}
}

func TestRunLoadStaleOKLoadsOldButSkipsEmpty(t *testing.T) {
	run := func(name string, fetched time.Time, hasRows bool) bool {
		body := map[string][]byte{}
		if hasRows {
			body["probe|A"] = []byte(`[{"x":1}]`)
		}
		src := &fakeLoadSource{json: body, fetched: fetched}
		loaded := false
		spec := loadSpec{
			key: "probe", table: "probe", partCol: "system", staleOK: true,
			partitions: func() []string { return []string{"A"} },
			load: func(_ context.Context, _ *json.Decoder, _ loadSink, _ string) error {
				loaded = true
				return nil
			},
		}
		stats, err := runLoadSpecs(context.Background(), src, nil, nil, []loadSpec{spec})
		if hasRows && err != nil {
			t.Fatalf("%s: runLoadSpecs: %v", name, err)
		}
		// A zero fetched_at means the partition never landed, which is not a
		// run failure: the rail date windows outrun TDX's publication horizon
		// every day. It must still be skipped, just not reported as stale.
		if !hasRows {
			if err != nil {
				t.Fatalf("%s: runLoadSpecs error = %v, want a never-landed partition to be skipped silently", name, err)
			}
			if stats.skipped != 1 || stats.failed != 0 {
				t.Fatalf("%s: stats = %+v, want the partition counted as skipped", name, stats)
			}
		}
		return loaded
	}
	// staleOK: a landing far past staleAfter must still load (304-served static data).
	if !run("old", time.Now().Add(-200*time.Hour), true) {
		t.Fatal("staleOK partition with old-but-present landing must load")
	}
	// staleOK still honors the empty guard: a zero fetched_at (empty partition,
	// i.e. a landing that never happened) must not DELETE-and-reinsert nothing.
	if run("empty", time.Time{}, false) {
		t.Fatal("staleOK partition with empty landing must be skipped")
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
		{key: "bus", operation: "bus city assembly", part: "Taipei"},
		{key: "bus_dailytimetable", operation: "bus daily timetable", part: "Taipei"},
		{key: "mrt_odfare", operation: "MRT journey matrix", part: "TRTC"},
		{key: "mrt_traveltime", operation: "MRT travel time", part: "TRTC"},
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
// against testRedisAddr (REDIS_TEST_ADDR, falling back to 127.0.0.1:6379) and
// skips when one is not reachable, mirroring the DB-gated tests' skip posture.
func TestLoadBusDailyTimetableWritesRedis(t *testing.T) {
	rc := dialTestRedis(t)
	defer rc.Close()

	const uid = "KHH_DTT_SUB1"
	key := "bus_daily_timetable:" + uid
	_ = rc.Del(context.Background(), key).Err()
	defer func() { _ = rc.Del(context.Background(), key).Err() }()

	body := []byte(`[{"SubRouteUID":"` + uid + `","Direction":0,"Timetables":[{"TripID":"T1","IsLowFloor":true,"StopTimes":[{"StopSequence":1,"StopUID":"S1","ArrivalTime":"08:00","DepartureTime":"08:01"}]}]}]`)
	dec := json.NewDecoder(bytes.NewReader(body))
	if err := loadBusDailyTimetable(context.Background(), dec, nil, nil, rc, "Kaohsiung"); err != nil {
		t.Fatalf("loadBusDailyTimetable: %v", err)
	}

	pb, err := rc.Get(context.Background(), key).Bytes()
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
	ttl := rc.TTL(context.Background(), key).Val()
	if ttl <= 25*time.Hour+59*time.Minute || ttl > 26*time.Hour {
		t.Fatalf("TTL = %s, want 26h", ttl)
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
		return []byte("[]"), f.fetched, nil //nolint:nilerr // a missing fixture is the empty-dataset case, not a failure
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
	if _, err := runLoad(ctx, src, pool, nil, []string{"thsr_station"}); err != nil {
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

func TestMarkerEarned(t *testing.T) {
	cases := []struct {
		name  string
		stats loadStats
		err   error
		want  bool
	}{
		// The regression this whole change exists for: one city rejecting a
		// bad row must not strand changetovector and the segment-time passes.
		{"partial load publishes", loadStats{ok: 19, failed: 1}, errors.New("bus Taoyuan: Shape[107] references unknown"), true},
		{"clean load publishes", loadStats{ok: 20}, nil, true},
		{"rail horizon skips do not block", loadStats{ok: 20, skipped: 20}, nil, true},
		{"nothing loaded withholds", loadStats{failed: 20}, errors.New("boom"), false},
		{"empty run withholds", loadStats{}, nil, false},
		// A truncated run is unfinished, not partial: the partitions it never
		// reached would look current to a downstream stage.
		{"deadline withholds despite progress", loadStats{ok: 12}, fmt.Errorf("load: %w", context.DeadlineExceeded), false},
		{"cancel withholds despite progress", loadStats{ok: 12}, fmt.Errorf("load: %w", context.Canceled), false},
	}
	for _, c := range cases {
		if got := markerEarned(c.stats, c.err); got != c.want {
			t.Errorf("%s: markerEarned(%+v, %v) = %v, want %v", c.name, c.stats, c.err, got, c.want)
		}
	}
}

// The legacy log parser splits a formatted line into key=value attrs, so a
// detail carrying spaces or '=' (wrapped error text, mostly) was shredded into
// bogus fields and truncated at the first space.
func TestLoadQuarantineDetailSurvivesLogParser(t *testing.T) {
	q := newLoadQuarantine("bus", "Tainan")
	q.drop("subroute", "subroute_identity", `Route[15].SubRoutes[0] uid="TNN104500" dir=2`)
	q.drop("subroute", "subroute_identity", "second sample is ignored")
	got := q.sample["subroute_identity"]
	if strings.ContainsAny(got, " =\"") {
		t.Fatalf("sample = %q, want no space, '=' or quote to survive the log parser", got)
	}
	if !strings.Contains(got, "TNN104500") {
		t.Fatalf("sample = %q, want the offending record still identifiable", got)
	}
	if q.dropped["subroute_identity"] != 2 {
		t.Fatalf("count = %d, want both drops counted", q.dropped["subroute_identity"])
	}
}

// The gate exists because the 2026-07-17 run dropped 223 of Taipei's shapes as
// a "tail". A tail is a handful of records; a third of a city's shapes is a
// defect, and quarantining it silently ships a gutted city that looks fresh.
func TestLoadQuarantineRatioGate(t *testing.T) {
	tests := []struct {
		name    string
		seen    int
		drops   int
		wantErr bool
	}{
		{"clean", 400, 0, false},
		{"tail stays under the limit", 400, 13, false},
		{"exactly at the limit passes", 400, 40, false},
		{"a third of the city fails", 400, 223, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			q := newLoadQuarantine("bus", "Taipei")
			q.consider("shape", tt.seen)
			for i := range tt.drops {
				q.drop("shape", "shape_unknown_direction", fmt.Sprintf("Shape[%d]", i))
			}
			err := q.exceeded()
			if tt.wantErr && err == nil {
				t.Fatalf("exceeded() = nil, want a ratio error for %d/%d", tt.drops, tt.seen)
			}
			if !tt.wantErr && err != nil {
				t.Fatalf("exceeded() = %v, want nil for %d/%d", err, tt.drops, tt.seen)
			}
		})
	}
}

// A kind that dropped nothing must not gate on a zero denominator, and one
// kind blowing its limit must not be masked by another kind being clean.
func TestLoadQuarantineRatioGateIsPerKind(t *testing.T) {
	q := newLoadQuarantine("bus", "Taipei")
	q.consider("shape", 400)
	q.consider("subroute", 4000)
	for i := range 223 {
		q.drop("shape", "shape_unknown_direction", fmt.Sprintf("Shape[%d]", i))
	}
	err := q.exceeded()
	if err == nil {
		t.Fatal("exceeded() = nil, want the shape ratio to fail despite 4000 clean subroutes")
	}
	if !strings.Contains(err.Error(), "shape") {
		t.Fatalf("exceeded() = %v, want the offending kind named", err)
	}
	// No drops at all: nothing to gate on, including kinds never considered.
	if err := newLoadQuarantine("bus", "Taipei").exceeded(); err != nil {
		t.Fatalf("exceeded() = %v, want nil for a clean partition", err)
	}
}

func TestQuarantineRatioLimitEnvOverride(t *testing.T) {
	t.Setenv("LOAD_QUARANTINE_MAX_RATIO", "0.5")
	if got := quarantineRatioLimit(); got != 0.5 {
		t.Fatalf("quarantineRatioLimit() = %v, want 0.5", got)
	}
	// A nonsense value must not silently disable the gate.
	t.Setenv("LOAD_QUARANTINE_MAX_RATIO", "banana")
	if got := quarantineRatioLimit(); got != defaultQuarantineRatio {
		t.Fatalf("quarantineRatioLimit() = %v, want the %v default", got, defaultQuarantineRatio)
	}
	t.Setenv("LOAD_QUARANTINE_MAX_RATIO", "7")
	if got := quarantineRatioLimit(); got != defaultQuarantineRatio {
		t.Fatalf("quarantineRatioLimit() = %v, want the %v default for an out-of-range value", got, defaultQuarantineRatio)
	}
}
