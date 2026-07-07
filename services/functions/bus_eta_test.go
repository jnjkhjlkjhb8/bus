package main

import "testing"

// Every polled city must resolve to a UID prefix. An empty prefix makes
// busstaticmp's LIKE match every subroute nationwide, so that city's ETA cycle
// rewrites every bus_eta_route:* snapshot with empty (status 67) entries,
// clobbering other cities' live ETAs — and the static loader's
// LIKE-prefix DELETEs wipe whole tables the same way.
func TestCitymapCoversAllCities(t *testing.T) {
	for _, city := range cities {
		if citymap[city] == "" {
			t.Errorf("citymap[%q] is empty", city)
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
