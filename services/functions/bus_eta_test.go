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
		{"full array", `[{"StopUID":"A","EstimatedTime":60},{"StopUID":"B","EstimatedTime":120}]`, 2, true},
		{"empty array is complete", `[]`, 0, true},
		{"truncated mid-element", `[{"StopUID":"A","EstimatedTime":60},{"StopUID":"B",`, 1, false},
		{"missing closing bracket", `[{"StopUID":"A","EstimatedTime":60}`, 1, false},
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

// Every city whose bus ETA must work has to resolve to a non-empty UID prefix.
// An empty prefix makes busstaticmp match every city's stops (LIKE '%'), whose
// blank cross-city rows then clobber the shared, non-city-scoped bus_eta_route
// keys — the Taoyuan-route-blanks-out bug. Guards against a citymap rename
// silently dropping a served city back to the empty prefix.
func TestServedCityPrefixesResolve(t *testing.T) {
	mustServe := []string{
		"Taipei", "NewTaipei", "Taoyuan", "Taichung", "Tainan", "Kaohsiung",
		"Keelung", "Hsinchu", "HsinchuCounty", "Chiayi", "ChiayiCounty", "InterCity",
	}
	for _, c := range mustServe {
		if citymap[c] == "" {
			t.Errorf("city %q has empty prefix: its bus ETA would load the nationwide static map and clobber other cities' route keys", c)
		}
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
