package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"sync"
	"testing"
)

// The hourly landing must stay one dataset wide: the whole point of the extra
// cadence is that it costs ~23 conditional GETs, not a second full run.
func TestIngestRawLandsOnlySelectedTables(t *testing.T) {
	t.Setenv("TDX_CLIENT_ID", "test-id")
	t.Setenv("TDX_CLIENT_SECRET", "test-secret")

	var mu sync.Mutex
	var seen []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		seen = append(seen, r.URL.Path)
		mu.Unlock()
		w.Header().Set("Last-Modified", "fixture-v1")
		_, _ = w.Write([]byte("[]"))
	}))
	defer srv.Close()

	_ = ingestRaw(context.Background(), testTDXClient(srv.URL), "bus_dailytimetable")

	mu.Lock()
	defer mu.Unlock()
	if len(seen) != len(cities) {
		t.Fatalf("fetched %d endpoints, want one per city (%d)", len(seen), len(cities))
	}
	for _, path := range seen {
		if !strings.HasPrefix(path, "/v2/Bus/DailyTimeTable/") {
			t.Errorf("fetched %s, want only /v2/Bus/DailyTimeTable/*", path)
		}
	}
}

func TestBusDailyPendingCities(t *testing.T) {
	markers := map[string]string{
		"Taoyuan":     "v2",
		"Taichung":    "v1",
		"Kaohsiung":   "v3",
		"Taipei":      "v9", // TDX serves no daily timetable for Taipei
		"HsinchuCity": "v1",
	}
	tests := []struct {
		name   string
		loaded map[string]string
		want   []string
	}{
		{
			name:   "fresh process loads every served city",
			loaded: map[string]string{},
			want:   []string{"HsinchuCity", "Kaohsiung", "Taichung", "Taoyuan"},
		},
		{
			name: "only the cities whose marker moved",
			loaded: map[string]string{
				"Taoyuan": "v1", "Taichung": "v1", "Kaohsiung": "v3", "HsinchuCity": "v1",
			},
			want: []string{"Taoyuan"},
		},
		{
			name: "quiet hour transforms nothing",
			loaded: map[string]string{
				"Taoyuan": "v2", "Taichung": "v1", "Kaohsiung": "v3", "HsinchuCity": "v1",
			},
			want: []string{},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := busDailyPendingCities(markers, tt.loaded)
			if !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("busDailyPendingCities() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestBusDailyTimetableSpecComesFromRegistry(t *testing.T) {
	spec, err := busDailyTimetableSpec(nil)
	if err != nil {
		t.Fatalf("busDailyTimetableSpec() error = %v", err)
	}
	if spec.table != "bus_dailytimetable" || spec.partCol != "city" || spec.load == nil {
		t.Fatalf("spec = %+v, want the registry's bus_dailytimetable recipe", spec)
	}
}
