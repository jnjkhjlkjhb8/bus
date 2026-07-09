package main

import (
	"encoding/json"
	"testing"
)

// TestMrtTravelGraph exercises the TRTC OD travel-time graph: two lines joined by
// an interchange transfer, verifying shortest-path seconds (including the cross-
// line path through the transfer edge) and the minute rounding used by the loader.
// Inputs are decoded from JSON so the case-insensitive struct tags are covered too
// (the landing lowercases the keys before the loader ever sees them).
func TestMrtTravelGraph(t *testing.T) {
	// Line BL: BL01 -(110s)- BL02 -(125s)- BL03. Line R: R01 -(100s)- R02.
	// Transfer BL02 <-> R01 = 3 min = 180s. Keys lowercased as landing emits them.
	var lines []mrtS2SRow
	if err := json.Unmarshal([]byte(`[{"traveltimes":[
		{"fromstationid":"BL01","tostationid":"BL02","runtime":90,"stoptime":20},
		{"fromstationid":"BL02","tostationid":"BL03","runtime":100,"stoptime":25},
		{"fromstationid":"R01","tostationid":"R02","runtime":80,"stoptime":20}]}]`), &lines); err != nil {
		t.Fatal(err)
	}
	var transfers []mrtLineTransfer
	if err := json.Unmarshal([]byte(`[{"fromstationid":"BL02","tostationid":"R01","transfertime":3}]`), &transfers); err != nil {
		t.Fatal(err)
	}

	stations, dist, segs, xfers := mrtTravelGraph(lines, transfers)
	if segs != 3 || xfers != 1 {
		t.Fatalf("edge counts: segs=%d xfers=%d, want 3/1", segs, xfers)
	}
	pos := map[string]int{}
	for i, s := range stations {
		pos[s] = i
	}
	sec := func(a, b string) int { return dist[pos[a]][pos[b]] }

	cases := []struct {
		from, to         string
		wantSec, wantMin int
	}{
		{"BL01", "BL03", 235, 4}, // 110 + 125
		{"BL01", "R02", 390, 7},  // 110 + 180 (transfer) + 100
		{"R02", "BL01", 390, 7},  // undirected
	}
	for _, c := range cases {
		if got := sec(c.from, c.to); got != c.wantSec {
			t.Errorf("%s->%s seconds = %d, want %d", c.from, c.to, got, c.wantSec)
		} else if mins := max((got+30)/60, 1); mins != c.wantMin {
			t.Errorf("%s->%s minutes = %d, want %d", c.from, c.to, mins, c.wantMin)
		}
	}
}
