package main

import (
	"strings"
	"testing"
)

func TestMask(t *testing.T) {
	got := mask(true, false, true, false, false, false, true)
	want := uint8((1 << 0) | (1 << 2) | (1 << 6))
	if got != want {
		t.Fatalf("mask() = %d, want %d", got, want)
	}
}

func TestMask2(t *testing.T) {
	got := mask2(0, 1, 0, 0, 0, 1, 0)
	want := uint8((1 << 1) | (1 << 5))
	if got != want {
		t.Fatalf("mask2() = %d, want %d", got, want)
	}
}

func TestBusRouteEtaKey(t *testing.T) {
	got := busRouteEtaKey("THB1234")
	want := "bus_eta_route:THB1234"
	if got != want {
		t.Fatalf("busRouteEtaKey() = %q, want %q", got, want)
	}
}

func TestBusStaticUpsertsDeduplicateConflictKeys(t *testing.T) {
	for _, tc := range []struct {
		name string
		sql  string
		want string
	}{
		{
			name: "shape",
			sql:  busSubroutesUpsertSQL,
			want: "SELECT DISTINCT ON (uid, d)",
		},
		{
			name: "schedule",
			sql:  busScheduleUpsertSQL,
			want: "SELECT DISTINCT ON (uid, dir, type, sdays, id, stopuid)",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if !strings.Contains(tc.sql, tc.want) {
				t.Fatalf("upsert SQL missing %q", tc.want)
			}
		})
	}
}

func TestBusCityCompleteQueryChecksCityAndStops(t *testing.T) {
	for _, want := range []string{"FROM bus_subroutes WHERE city = $1", "cardinality(stops) = 0"} {
		if !strings.Contains(busCityCompleteSQL, want) {
			t.Fatalf("city complete SQL missing %q", want)
		}
	}
}
