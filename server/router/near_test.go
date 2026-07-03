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
	}{
		{"osrm durations and distances used", full, true, 1, true, 1000, 10, 900},
		{"missing distances keeps geodesic dist", osrm{Code: "Ok", Durations: [][]float64{{300}}}, true, 0, true, 1000, 5, 1000},
		{"osrm not ready estimates from geodesic", full, false, 1, true, 800, 10, 800},
		{"station without index estimates from geodesic", full, true, 0, false, 800, 10, 800},
		{"index out of range estimates from geodesic", full, true, 5, true, 800, 10, 800},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			walk, dist := walkAndDist(tt.o, tt.ready, tt.idx, tt.hasIdx, tt.geodesic)
			if walk != tt.walk || dist != tt.dist {
				t.Fatalf("got walk=%d dist=%d, want walk=%d dist=%d", walk, dist, tt.walk, tt.dist)
			}
		})
	}
}
