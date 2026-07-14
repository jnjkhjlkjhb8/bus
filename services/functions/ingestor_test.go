package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
)

// fakeTDXStore is an in-memory shared.TDXStore for the ingestor fan-out tests: it
// returns a cached token so the client never does a real client_credentials
// exchange, and empty values (never an error) for every other key so the
// conditional-GET sends no If-Modified-Since. Writes are dropped.
type fakeTDXStore struct {
	token string
	set   func(key, value string, ttl time.Duration) error
}

func (f fakeTDXStore) Get(key string) (string, error) {
	if key == shared.TDXTokenKey || key == shared.TDXTokenKeyLegacy {
		return f.token, nil
	}
	return "", nil
}
func (f fakeTDXStore) Set(key, value string, ttl time.Duration) error {
	if f.set != nil {
		return f.set(key, value, ttl)
	}
	return nil
}
func (fakeTDXStore) Del(...string) error { return nil }

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
		if err := validateRawTarget(v.table, v.part); err != nil {
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
		if err := validateRawTarget(b.table, b.part); err == nil {
			t.Errorf("validateRawTarget(%q,%q) expected error, got nil", b.table, b.part)
		}
	}
}

func TestRawDeleteSQL(t *testing.T) {
	got := rawDeleteSQL("bus_route", "city")
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
		table, partCol, partVal, ok := rawDumpTarget(c.url)
		if !ok {
			t.Errorf("%s: expected ok=true", c.url)
			continue
		}
		if table != c.table || partCol != c.partCol || partVal != c.partVal {
			t.Errorf("%s: got (%q,%q,%q), want (%q,%q,%q)",
				c.url, table, partCol, partVal, c.table, c.partCol, c.partVal)
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
		if table, _, _, ok := rawDumpTarget(url); ok {
			t.Errorf("%s: expected skip, got table=%q ok=true", url, table)
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

	ingestRaw(context.Background(), testTDXClient(srv.URL))

	for _, city := range cities {
		for _, api := range ingestBusAPIs {
			var path string
			if city == "InterCity" {
				path = "/v2/Bus/" + api + "/InterCity"
			} else {
				path = "/v2/Bus/" + api + "/City/" + city
			}
			if got := seen[path]; got != 1 {
				t.Fatalf("%s fetched %d times, want 1", path, got)
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
	modified, err := tdx.GetInto("/raw", "fixture", func(body []byte) error {
		if marker != "" {
			t.Fatalf("marker advanced before durable callback: %q", marker)
		}
		if got := string(body); got != `[1,2,3]` {
			t.Fatalf("landing callback body = %q, want [1,2,3]", got)
		}
		committed = true
		return nil
	})
	if err != nil || !modified {
		t.Fatalf("GetInto modified=%v err=%v, want true/nil", modified, err)
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

			ingestRaw(context.Background(), testTDXClient(srv.URL))

			if got := atomic.LoadInt32(&calls); got != 0 {
				t.Fatalf("ingestRaw made %d requests without credentials, want 0", got)
			}
		})
	}
}
