package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
)

type fakeRawFetcher struct {
	getInto func(context.Context, string, string, func(shared.TDXIntoCommit) error) (shared.TDXIntoResult, error)
}

func (f fakeRawFetcher) GetInto(ctx context.Context, url, name string, commit func(shared.TDXIntoCommit) error) (shared.TDXIntoResult, error) {
	return f.getInto(ctx, url, name, commit)
}

// fakeTDXStore is an in-memory shared.TDXStore for the ingestor fan-out tests: it
// returns a cached token so the client never does a real client_credentials
// exchange, and empty values (never an error) for every other key so the
// conditional-GET sends no If-Modified-Since. Writes are dropped.
type fakeTDXStore struct {
	token string
	set   func(key, value string, ttl time.Duration) error
}

func (f fakeTDXStore) Get(_ context.Context, key string) (string, error) {
	if key == shared.TDXTokenKey || key == shared.TDXTokenKeyLegacy {
		return f.token, nil
	}
	return "", nil
}
func (f fakeTDXStore) Set(_ context.Context, key, value string, ttl time.Duration) error {
	if f.set != nil {
		return f.set(key, value, ttl)
	}
	return nil
}
func (fakeTDXStore) Del(context.Context, ...string) error { return nil }

// testTDXClient builds a TDX client pointed at a test server with a fake store,
// so no request needs a live Redis or a real TDX token exchange.
func testTDXClient(baseURL string) *shared.TDXClient {
	return shared.NewTDXClient(shared.TDXConfig{
		Store:   fakeTDXStore{token: "test-token"},
		IMSKey:  imsCacheKey,
		BaseURL: baseURL,
	})
}

func TestValidateRawTarget(t *testing.T) {
	valid := []struct{ table, part string }{
		{"bus_route", "city"}, {"metro_station", "system"},
		{"tra_odfare", ""}, {"thsr_dailytimetable", ""},
		{"tra_station", ""}, {"tra_dailytimetable", "traindate"},
	}
	for _, v := range valid {
		if err := validateRawTarget(rawTarget{table: v.table, partCol: v.part}); err != nil {
			t.Errorf("validateRawTarget(%q,%q) unexpected error: %v", v.table, v.part, err)
		}
	}
	bad := []struct{ table, part string }{
		{"bus_route; DROP TABLE x", "city"}, // injection attempt
		{"pg_class", "city"},                // not whitelisted
		{"", ""},                            // empty table
		{"bus_route", "1=1"},                // injection via partCol
		{"bus_route", "route_uid"},          // non-partition column
	}
	for _, b := range bad {
		if err := validateRawTarget(rawTarget{table: b.table, partCol: b.part}); err == nil {
			t.Errorf("validateRawTarget(%q,%q) expected error, got nil", b.table, b.part)
		}
	}
}

func TestRawDeleteSQL(t *testing.T) {
	got := rawDeleteSQL(rawTarget{table: "bus_route", partCol: "city"})
	want := "DELETE FROM raw_tdx.bus_route WHERE city = $1"
	if got != want {
		t.Errorf("rawDeleteSQL = %q, want %q", got, want)
	}
}

func TestRawInsertSQLStructure(t *testing.T) {
	got := rawInsertSQL("metro_station")
	for _, sub := range []string{
		"INSERT INTO raw_tdx.metro_station",
		"NULL::raw_tdx.metro_station",
		"jsonb_array_elements($2::jsonb)",
		"jsonb_object_agg(lower(",
		"$1::jsonb",
	} {
		if !strings.Contains(got, sub) {
			t.Errorf("rawInsertSQL missing %q in:\n%s", sub, got)
		}
	}
}

func TestRawDumpTargetStatic(t *testing.T) {
	cases := []struct {
		url, table, partCol, partVal string
	}{
		{"/v2/Bus/Route/City/Taipei", "bus_route", "city", "Taipei"},
		{"/v2/Bus/StopOfRoute/City/Kaohsiung", "bus_stopofroute", "city", "Kaohsiung"},
		{"/v2/Bus/Route/InterCity", "bus_route", "city", "InterCity"},
		{"/v2/Bus/StationGroup/City/Tainan", "bus_stationgroup", "city", "Tainan"},
		{"/v2/Bus/RouteFare/City/Taipei", "bus_routefare", "city", "Taipei"},
		{"/v2/Bus/DailyTimeTable/City/Taipei", "bus_dailytimetable", "city", "Taipei"},
		{"/v2/Bike/Station/City/Taichung", "bike_station", "city", "Taichung"},
		{"/v2/Rail/Metro/Station/TRTC", "metro_station", "system", "TRTC"},
		{"/v2/Rail/Metro/FirstLastTimetable/KRTC", "metro_schedule", "system", "KRTC"},
		{"/v2/Rail/Metro/ODFare/TRTC", "metro_odfare", "system", "TRTC"},
		{"/v2/Rail/TRA/ODFare", "tra_odfare", "", ""},
		{"/v2/Rail/TRA/TrainType", "tra_traintype", "", ""},
		{"/v2/Rail/TRA/Station", "tra_station", "", ""},
		{"/v2/Rail/THSR/Station", "thsr_station", "", ""},
		{"/v2/Rail/THSR/ODFare", "thsr_odfare", "", ""},
		{"/v2/Rail/TRA/DailyTimetable/TrainDate/2026-07-02", "tra_dailytimetable", "traindate", "2026-07-02"},
		{"/v2/Rail/THSR/DailyTimetable/TrainDate/2026-07-02", "thsr_dailytimetable", "traindate", "2026-07-02"},
	}
	for _, c := range cases {
		got, ok := rawDumpTarget(c.url)
		if !ok {
			t.Errorf("%s: expected ok=true", c.url)
			continue
		}
		want := rawTarget{table: c.table, partCol: c.partCol, partVal: c.partVal}
		if got != want {
			t.Errorf("%s: got %+v, want %+v", c.url, got, want)
		}
	}
}

func TestRawDumpTargetSkipsRealtimeAndUnmapped(t *testing.T) {
	skip := []string{
		"/v2/Bus/EstimatedTimeOfArrival/City/Taipei",
		"/v2/Bus/EstimatedTimeOfArrival/InterCity",
		"/v2/Bus/RealTimeByFrequency/City/Taipei",
		"/v2/Bike/Availability/City/Taipei",
		"/v2/Rail/Metro/LiveBoard/TRTC",
		"/v2/Rail/TRA/LiveBoard",
		"/v2/Rail/TRA/LiveTrainDelay",
		"/v2/Bus/Unknown/City/Taipei",
		"/notv2/Bus/Route/City/Taipei",
	}
	for _, url := range skip {
		if got, ok := rawDumpTarget(url); ok {
			t.Errorf("%s: expected skip, got table=%q ok=true", url, got.table)
		}
	}
}

func TestIngestRaw_FetchesAllBusCityAPIs(t *testing.T) {
	t.Setenv("TDX_CLIENT_ID", "test-id")
	t.Setenv("TDX_CLIENT_SECRET", "test-secret")

	var mu sync.Mutex
	seen := map[string]int{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		seen[r.URL.Path]++
		mu.Unlock()
		w.Header().Set("Last-Modified", "fixture-v1")
		_, _ = w.Write([]byte("[]"))
	}))
	defer srv.Close()

	_ = ingestRaw(context.Background(), testTDXClient(srv.URL))

	for _, city := range cities {
		for _, api := range ingestBusAPIs {
			var path string
			if city == "InterCity" {
				path = "/v2/Bus/" + api + "/InterCity"
			} else {
				path = "/v2/Bus/" + api + "/City/" + city
			}
			// DailyTimeTable is the one bus API TDX does not serve for every
			// city; landing the unserved ones only yields HTTP 400.
			want := 1
			if api == "DailyTimeTable" && busDailyTimetableSkip(city) {
				want = 0
			}
			if got := seen[path]; got != want {
				t.Fatalf("%s fetched %d times, want %d", path, got, want)
			}
		}
	}
}

// TestRawLandingHTTPFixtureCommitsBeforeMarker guards the protocol assumption
// used by the fan-out fixture above: a successful 200 response carries a marker,
// invokes the durable landing callback, and advances the marker only afterward.
// The callback is kept in-memory because dumpRawTDX's database integration is
// covered separately by the DATABASE_URL-gated rawdump tests.
func TestRawLandingHTTPFixtureCommitsBeforeMarker(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Last-Modified", "fixture-v1")
		_, _ = w.Write([]byte(`[1,2,3]`))
	}))
	defer srv.Close()

	var marker string
	store := fakeTDXStore{
		token: "test-token",
		set: func(_ string, value string, _ time.Duration) error {
			marker = value
			return nil
		},
	}
	tdx := shared.NewTDXClient(shared.TDXConfig{
		Store:   store,
		IMSKey:  func(name string) string { return "test:ims:" + name },
		BaseURL: srv.URL,
	})
	committed := false
	result, err := tdx.GetInto(context.Background(), "/raw", "fixture", func(commit shared.TDXIntoCommit) error {
		body := commit.Body
		if marker != "" {
			t.Fatalf("marker advanced before durable callback: %q", marker)
		}
		b, readErr := io.ReadAll(body)
		if readErr != nil {
			return readErr
		}
		if got := string(b); got != `[1,2,3]` {
			t.Fatalf("landing callback body = %q, want [1,2,3]", got)
		}
		committed = true
		return nil
	})
	if err != nil || !result.Modified {
		t.Fatalf("GetInto result=%+v err=%v, want modified/nil", result, err)
	}
	if !committed {
		t.Fatal("durable landing callback was not invoked")
	}
	if marker != "fixture-v1" {
		t.Fatalf("marker after commit = %q, want fixture-v1", marker)
	}
}

// TestIngestRaw_NoOpWithoutCredentials proves the ingestor issues zero requests
// when TDX credentials are absent, so staging/test (empty creds against the
// shared database) neither storms TDX nor races prod's raw_tdx writes.
func TestIngestRaw_NoOpWithoutCredentials(t *testing.T) {
	for _, tc := range []struct {
		name, id, secret string
	}{
		{"both_empty", "", ""},
		{"id_only", "test-id", ""},
		{"secret_only", "", "test-secret"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("TDX_CLIENT_ID", tc.id)
			t.Setenv("TDX_CLIENT_SECRET", tc.secret)

			var calls int32
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				atomic.AddInt32(&calls, 1)
				_, _ = w.Write([]byte("[]"))
			}))
			defer srv.Close()

			_ = ingestRaw(context.Background(), testTDXClient(srv.URL))

			if got := atomic.LoadInt32(&calls); got != 0 {
				t.Fatalf("ingestRaw made %d requests without credentials, want 0", got)
			}
		})
	}
}

func TestIngestRawAggregatesAllFetchFailures(t *testing.T) {
	t.Setenv("TDX_CLIENT_ID", "test-id")
	t.Setenv("TDX_CLIENT_SECRET", "test-secret")
	want := []error{
		errors.New("first fetch failed"),
		errors.New("second fetch failed"),
		errors.New("third fetch failed"),
	}
	var calls atomic.Int64
	fetcher := fakeRawFetcher{getInto: func(_ context.Context, _, _ string, _ func(shared.TDXIntoCommit) error) (shared.TDXIntoResult, error) {
		i := calls.Add(1) - 1
		return shared.TDXIntoResult{}, want[int(i)%len(want)]
	}}
	err := ingestRaw(context.Background(), fetcher)
	for _, target := range want {
		if !errors.Is(err, target) {
			t.Errorf("ingestRaw error = %v, want joined %v", err, target)
		}
	}
	if calls.Load() < int64(len(want)) {
		t.Fatalf("fetch calls = %d, want at least %d", calls.Load(), len(want))
	}
}

func TestIngestRawKeepsThreeRequestConcurrencyLimit(t *testing.T) {
	t.Setenv("TDX_CLIENT_ID", "test-id")
	t.Setenv("TDX_CLIENT_SECRET", "test-secret")
	var active atomic.Int64
	var maximum atomic.Int64
	fetcher := fakeRawFetcher{getInto: func(ctx context.Context, _, _ string, _ func(shared.TDXIntoCommit) error) (shared.TDXIntoResult, error) {
		n := active.Add(1)
		defer active.Add(-1)
		for {
			old := maximum.Load()
			if n <= old || maximum.CompareAndSwap(old, n) {
				break
			}
		}
		select {
		case <-time.After(2 * time.Millisecond):
			return shared.TDXIntoResult{Modified: true}, nil
		case <-ctx.Done():
			return shared.TDXIntoResult{}, fmt.Errorf("fetch canceled: %w", ctx.Err())
		}
	}}
	if err := ingestRaw(context.Background(), fetcher); err != nil {
		t.Fatalf("ingestRaw: %v", err)
	}
	if got := maximum.Load(); got != 3 {
		t.Fatalf("maximum concurrent requests = %d, want 3", got)
	}
}

func TestFetchRawForcesOneEndpointRefetchOnLandingStateMismatch(t *testing.T) {
	var calls, invalidations atomic.Int64
	fetcher := fakeRawFetcher{getInto: func(
		_ context.Context, _, _ string, _ func(shared.TDXIntoCommit) error,
	) (shared.TDXIntoResult, error) {
		if calls.Add(1) == 1 {
			return shared.TDXIntoResult{
				Marker: "MARKER-OLD",
				Invalidate: func() error {
					invalidations.Add(1)
					return nil
				},
			}, nil
		}
		return shared.TDXIntoResult{Modified: true, Marker: "MARKER-NEW"}, nil
	}}
	verify := func(_ context.Context, _ rawTarget, _, cycle string) error {
		if cycle != "cycle-test" {
			t.Fatalf("landing cycle = %q, want cycle-test", cycle)
		}
		return &rawLandingStateMismatchError{Reason: "missing_state"}
	}

	err := fetchRawWithVerifier(
		context.Background(), fetcher, "/v2/Bus/Route/City/Taipei", "bus_route_Taipei", "cycle-test", false, verify,
	)
	if err != nil {
		t.Fatalf("fetchRawWithVerifier: %v", err)
	}
	if calls.Load() != 2 || invalidations.Load() != 1 {
		t.Fatalf("calls=%d invalidations=%d, want 2/1", calls.Load(), invalidations.Load())
	}
}

func TestFetchRawBoundedRefetchFailsClosed(t *testing.T) {
	mismatch := &rawLandingStateMismatchError{Reason: "row_presence"}
	t.Run("second 304 mismatch stops after two requests", func(t *testing.T) {
		var calls, invalidations atomic.Int64
		fetcher := fakeRawFetcher{getInto: func(
			_ context.Context, _, _ string, _ func(shared.TDXIntoCommit) error,
		) (shared.TDXIntoResult, error) {
			calls.Add(1)
			return shared.TDXIntoResult{
				Marker: "MARKER",
				Invalidate: func() error {
					invalidations.Add(1)
					return nil
				},
			}, nil
		}}
		err := fetchRawWithVerifier(
			context.Background(), fetcher, "/v2/Bus/Route/City/Taipei", "bus_route_Taipei", "cycle-test", false,
			func(context.Context, rawTarget, string, string) error { return mismatch },
		)
		if !errors.Is(err, errRawLandingStateMismatch) {
			t.Fatalf("error = %v, want state mismatch", err)
		}
		if calls.Load() != 2 || invalidations.Load() != 1 {
			t.Fatalf("calls=%d invalidations=%d, want bounded 2/1", calls.Load(), invalidations.Load())
		}
	})

	t.Run("invalidation failure prevents refetch", func(t *testing.T) {
		invalidateErr := errors.New("redis delete failed")
		var calls atomic.Int64
		fetcher := fakeRawFetcher{getInto: func(
			_ context.Context, _, _ string, _ func(shared.TDXIntoCommit) error,
		) (shared.TDXIntoResult, error) {
			calls.Add(1)
			return shared.TDXIntoResult{
				Marker:     "MARKER",
				Invalidate: func() error { return invalidateErr },
			}, nil
		}}
		err := fetchRawWithVerifier(
			context.Background(), fetcher, "/v2/Bus/Route/City/Taipei", "bus_route_Taipei", "cycle-test", false,
			func(context.Context, rawTarget, string, string) error { return mismatch },
		)
		if !errors.Is(err, invalidateErr) || !errors.Is(err, errRawLandingStateMismatch) {
			t.Fatalf("error = %v, want invalidation and mismatch", err)
		}
		if calls.Load() != 1 {
			t.Fatalf("fetch calls = %d, want 1", calls.Load())
		}
	})

	t.Run("database verifier error is not invalidated", func(t *testing.T) {
		dbErr := errors.New("database unavailable")
		var invalidations atomic.Int64
		fetcher := fakeRawFetcher{getInto: func(
			_ context.Context, _, _ string, _ func(shared.TDXIntoCommit) error,
		) (shared.TDXIntoResult, error) {
			return shared.TDXIntoResult{
				Marker: "MARKER",
				Invalidate: func() error {
					invalidations.Add(1)
					return nil
				},
			}, nil
		}}
		err := fetchRawWithVerifier(
			context.Background(), fetcher, "/v2/Bus/Route/City/Taipei", "bus_route_Taipei", "cycle-test", false,
			func(context.Context, rawTarget, string, string) error { return dbErr },
		)
		if !errors.Is(err, dbErr) {
			t.Fatalf("error = %v, want %v", err, dbErr)
		}
		if invalidations.Load() != 0 {
			t.Fatalf("invalidations = %d, want 0", invalidations.Load())
		}
	})
}

// TestFetchRawFullReland covers the FDPL-37 weekly re-land: a 304 is refused
// once, the marker is dropped, and the unconditional second pass lands the body
// without ever consulting the landing-state verifier.
func TestFetchRawFullReland(t *testing.T) {
	var calls, invalidations, verifications atomic.Int64
	fetcher := fakeRawFetcher{getInto: func(
		_ context.Context, _, _ string, _ func(shared.TDXIntoCommit) error,
	) (shared.TDXIntoResult, error) {
		if calls.Add(1) == 1 {
			return shared.TDXIntoResult{
				Marker: "MARKER",
				Invalidate: func() error {
					invalidations.Add(1)
					return nil
				},
			}, nil
		}
		return shared.TDXIntoResult{Modified: true, Marker: "MARKER-NEW"}, nil
	}}
	verify := func(context.Context, rawTarget, string, string) error {
		verifications.Add(1)
		return nil
	}

	err := fetchRawWithVerifier(
		context.Background(), fetcher, "/v2/Bus/Route/City/Taipei", "bus_route_Taipei", "cycle-test", true, verify,
	)
	if err != nil {
		t.Fatalf("fetchRawWithVerifier: %v", err)
	}
	if calls.Load() != 2 || invalidations.Load() != 1 || verifications.Load() != 0 {
		t.Fatalf("calls=%d invalidations=%d verifications=%d, want 2/1/0",
			calls.Load(), invalidations.Load(), verifications.Load())
	}
}
