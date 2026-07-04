package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
)

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
		"COALESCE(",
		"'[]'::jsonb",
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
	var mu sync.Mutex
	seen := map[string]int{}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		seen[r.URL.Path]++
		mu.Unlock()
		_, _ = w.Write([]byte("[]"))
	}))
	defer srv.Close()

	c := resty.New().SetBaseURL(srv.URL).SetDoNotParseResponse(true)
	rc := redis.NewClient(&redis.Options{
		Addr:         "127.0.0.1:1",
		DialTimeout:  1 * time.Millisecond,
		ReadTimeout:  1 * time.Millisecond,
		WriteTimeout: 1 * time.Millisecond,
		MaxRetries:   0,
	})
	defer rc.Close()

	ingestRaw(context.Background(), c, rc)

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
