package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestDecodeBusEtaArray(t *testing.T) {
	tests := []struct {
		name         string
		body         string
		wantLen      int
		wantComplete bool
	}{
		{"full array", `[{"StopUID":"A","EstimateTime":60},{"StopUID":"B","EstimateTime":120}]`, 2, true},
		{"empty array is complete", `[]`, 0, true},
		{"truncated mid-element", `[{"StopUID":"A","EstimateTime":60},{"StopUID":"B",`, 1, false},
		{"missing closing bracket", `[{"StopUID":"A","EstimateTime":60}`, 1, false},
		{"not an array", `garbage`, 0, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dec := json.NewDecoder(strings.NewReader(tt.body))
			eat, complete := decodeBusEtaArray(dec)
			if complete != tt.wantComplete {
				t.Fatalf("complete = %v, want %v", complete, tt.wantComplete)
			}
			if len(eat) != tt.wantLen {
				t.Fatalf("len(eat) = %d, want %d", len(eat), tt.wantLen)
			}
		})
	}
}

// Bodies below are verbatim TDX v2 EstimatedTimeOfArrival elements. Asserting on
// the decoded *values* (not just the element count) is the point: the seconds
// field is spelled "EstimateTime", and a struct tag reading "EstimatedTime"
// decodes every arrival to a silent zero — every stop shows a blank ETA while the
// job still reports a healthy eat_count. Keelung names the subroute; Taipei and
// NewTaipei identify the arrival by route only.
func TestDecodeBusEtaArrayFieldNames(t *testing.T) {
	t.Run("Keelung names the subroute", func(t *testing.T) {
		body := `[{"PlateNumb":"FAC-156","StopUID":"KEE306194","RouteUID":"KEE0211","SubRouteUID":"KEE021101","Direction":0,"EstimateTime":1118,"StopStatus":0,"UpdateTime":"2026-07-12T20:20:34+08:00"}]`
		eat, complete := decodeBusEtaArray(json.NewDecoder(strings.NewReader(body)))
		if !complete || len(eat) != 1 {
			t.Fatalf("complete=%v len=%d, want true/1", complete, len(eat))
		}
		if eat[0].EstimatedTime != 1118 {
			t.Errorf("EstimatedTime = %d, want 1118 — the TDX field is EstimateTime", eat[0].EstimatedTime)
		}
		if eat[0].SubRouteUID != "KEE021101" || eat[0].RouteUID != "KEE0211" {
			t.Errorf("uids = %q/%q, want KEE021101/KEE0211", eat[0].SubRouteUID, eat[0].RouteUID)
		}
	})

	t.Run("Taipei identifies the arrival by route only", func(t *testing.T) {
		body := `[{"StopUID":"TPE36407","RouteUID":"TPE10442","RouteID":"10442","Direction":1,"EstimateTime":864,"StopStatus":0,"SrcUpdateTime":"2026-07-12T20:20:30+08:00"}]`
		eat, complete := decodeBusEtaArray(json.NewDecoder(strings.NewReader(body)))
		if !complete || len(eat) != 1 {
			t.Fatalf("complete=%v len=%d, want true/1", complete, len(eat))
		}
		if eat[0].EstimatedTime != 864 {
			t.Errorf("EstimatedTime = %d, want 864 — the TDX field is EstimateTime", eat[0].EstimatedTime)
		}
		if eat[0].SubRouteUID != "" {
			t.Errorf("SubRouteUID = %q, want empty: Taipei omits it, which is what buildBusEtaMap's route fan-out exists for", eat[0].SubRouteUID)
		}
		if eat[0].RouteUID != "TPE10442" {
			t.Errorf("RouteUID = %q, want TPE10442", eat[0].RouteUID)
		}
	})
}

// Every city iterated by the ingestion loops must resolve to a non-empty UID
// prefix. An empty prefix makes busEta skip the city outright (reason=no_prefix,
// so it publishes no bus_eta_route keys at all) and degrades the partition
// patterns built from it into LIKE '%', which deletes every city's rows from
// bus_station_stop_map and bus_schedule — nationwide ETA loss from one unmapped
// city. Asserting over `cities` itself, rather than a hand-kept allowlist, is
// what makes a citymap/cities divergence fail here instead of in production.
func TestServedCityPrefixesResolve(t *testing.T) {
	for _, c := range cities {
		if citymap[c] == "" {
			t.Errorf("city %q from cities has no citymap prefix: bus ETA would be skipped for it, and its LIKE '%%' partition delete would wipe every other city's stop-map and schedule rows", c)
		}
	}
}

// citymap and citymap2 must stay a strict inverse pair: citymap2 resolves a
// prefix back to a TDX city code, so its values have to be keys of citymap.
func TestCityMapsAreInverse(t *testing.T) {
	for city, prefix := range citymap {
		if got := citymap2[prefix]; got != city {
			t.Errorf("citymap2[%q] = %q, want %q", prefix, got, city)
		}
	}
	if len(citymap) != len(citymap2) {
		t.Errorf("citymap has %d entries, citymap2 has %d", len(citymap), len(citymap2))
	}
}

func TestPickBusEstimate(t *testing.T) {
	tests := []struct {
		name string
		prev rawBusEsimated
		next rawBusEsimated
		want rawBusEsimated
	}{
		{
			name: "status 0 beats status 1",
			prev: rawBusEsimated{StopStatus: 1, EstimatedTime: 10},
			next: rawBusEsimated{StopStatus: 0, EstimatedTime: 300},
			want: rawBusEsimated{StopStatus: 0, EstimatedTime: 300},
		},
		{
			name: "existing status 0 kept over incoming status 1",
			prev: rawBusEsimated{StopStatus: 0, EstimatedTime: 120},
			next: rawBusEsimated{StopStatus: 1, EstimatedTime: 5},
			want: rawBusEsimated{StopStatus: 0, EstimatedTime: 120},
		},
		{
			name: "smaller estimate wins among status 0",
			prev: rawBusEsimated{StopStatus: 0, EstimatedTime: 300},
			next: rawBusEsimated{StopStatus: 0, EstimatedTime: 60},
			want: rawBusEsimated{StopStatus: 0, EstimatedTime: 60},
		},
		{
			name: "larger estimate rejected among status 0",
			prev: rawBusEsimated{StopStatus: 0, EstimatedTime: 60},
			next: rawBusEsimated{StopStatus: 0, EstimatedTime: 300},
			want: rawBusEsimated{StopStatus: 0, EstimatedTime: 60},
		},
		{
			name: "first seen kept when all non-zero",
			prev: rawBusEsimated{StopStatus: 1, EstimatedTime: 200},
			next: rawBusEsimated{StopStatus: 1, EstimatedTime: 5},
			want: rawBusEsimated{StopStatus: 1, EstimatedTime: 200},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := pickBusEstimate(tt.prev, tt.next)
			if got != tt.want {
				t.Fatalf("pickBusEstimate() = %+v, want %+v", got, tt.want)
			}
		})
	}
}

func TestBusArrivalDispatchRequiresUsableETA(t *testing.T) {
	for _, tc := range []struct {
		name   string
		found  bool
		status uint8
		eta    int32
		want   bool
	}{
		{"missing", false, 0, 60, false},
		{"unavailable status", true, 1, 60, false},
		{"zero", true, 0, 0, false},
		{"negative", true, 0, -1, false},
		{"usable", true, 0, 60, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := shouldDispatchBusArrival(tc.found, tc.status, tc.eta); got != tc.want {
				t.Fatalf("got=%v want=%v", got, tc.want)
			}
		})
	}
}
