package main

import (
	"testing"
	"time"
)

func TestParseRailDate(t *testing.T) {
	// The app sends 'yyyy-MM-dd'; the router must key/query on that exact date,
	// not the zero time (which yielded train_date='0001-01-01' -> NotFound).
	got := parseRailDate("2026-07-07")
	if got.Format(time.DateOnly) != "2026-07-07" {
		t.Fatalf("DateOnly: got %q, want 2026-07-07", got.Format(time.DateOnly))
	}

	// RFC3339 stays supported for any legacy caller.
	got = parseRailDate("2026-07-07T00:00:00Z")
	if got.Format(time.DateOnly) != "2026-07-07" {
		t.Fatalf("RFC3339: got %q, want 2026-07-07", got.Format(time.DateOnly))
	}

	// Garbage falls back to the zero time.
	if !parseRailDate("nonsense").IsZero() {
		t.Fatal("expected zero time for unparseable date")
	}
}
