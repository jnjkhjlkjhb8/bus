package main

import "testing"

func TestWalkAndDist(t *testing.T) {
	full := osrm{
		Code:      "Ok",
		Durations: [][]float64{{300, 600}},
		Distances: [][]float64{{450, 900}},
	}
	tests := []struct {
		name     string
		o        osrm
		ready    bool
		idx      int
		hasIdx   bool
		geodesic float64
		walk     int32
		dist     int32
		routed   bool
	}{
		{"osrm durations and distances used", full, true, 1, true, 1000, 10, 900, true},
		{"missing distances keeps geodesic dist", osrm{Code: "Ok", Durations: [][]float64{{300}}}, true, 0, true, 1000, 5, 1000, true},
		{"osrm not ready estimates from geodesic", full, false, 1, true, 800, 10, 800, false},
		{"station without index estimates from geodesic", full, true, 0, false, 800, 10, 800, false},
		{"index out of range estimates from geodesic", full, true, 5, true, 800, 10, 800, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			walk, dist, routed := walkAndDist(tt.o, tt.ready, tt.idx, tt.hasIdx, tt.geodesic)
			if walk != tt.walk || dist != tt.dist || routed != tt.routed {
				t.Fatalf("got walk=%d dist=%d routed=%t, want walk=%d dist=%d routed=%t", walk, dist, routed, tt.walk, tt.dist, tt.routed)
			}
		})
	}
}
