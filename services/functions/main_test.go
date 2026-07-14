package main

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func TestVectorRefreshJobPropagatesError(t *testing.T) {
	wantErr := errors.New("watermark unavailable")
	job := vectorRefreshJob(
		&testVectorRedis{getErr: wantErr},
		nil,
		&stubEmbeddingClient{},
	)
	if err := job(context.Background()); !errors.Is(err, wantErr) {
		t.Fatalf("vectorRefreshJob() error = %v, want wrapped %v", err, wantErr)
	}
}

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

func TestBusSubroutesUpsertDeduplicatesConflictKeys(t *testing.T) {
	if !strings.Contains(busSubroutesUpsertSQL, "SELECT DISTINCT ON (uid, d)") {
		t.Fatalf("bus_subroutes upsert SQL missing DISTINCT ON dedup")
	}
}

// TestBusScheduleInsertKeepsDuplicates locks in the partition-replace contract:
// bus_schedule is rebuilt per city by DELETE + plain INSERT, so the schedule
// insert must NOT dedup (no DISTINCT ON) and must NOT upsert (no ON CONFLICT).
// A circular route visits the same stop twice per trip, colliding on the old
// natural key; those rows are intentionally kept now.
func TestBusScheduleInsertKeepsDuplicates(t *testing.T) {
	for _, banned := range []string{"DISTINCT ON", "ON CONFLICT"} {
		if strings.Contains(busScheduleInsertSQL, banned) {
			t.Fatalf("bus_schedule insert SQL must not contain %q (partition-replace keeps duplicate rows)", banned)
		}
	}
}
