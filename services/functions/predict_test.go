package main

import (
	"testing"
	"time"

	"github.com/dmitryikh/leaves"
)

func TestDedupRouteDirPairs(t *testing.T) {
	in := []routeDirKey{
		{"TPE1", 0},
		{"TPE1", 0},
		{"TPE1", 1},
		{"TPE2", 0},
	}
	got := dedupRouteDirPairs(in)
	if len(got) != 3 {
		t.Fatalf("dedupRouteDirPairs len = %d, want 3", len(got))
	}
	seen := map[routeDirKey]bool{}
	for _, k := range got {
		if seen[k] {
			t.Fatalf("duplicate key in output: %+v", k)
		}
		seen[k] = true
	}
}

func TestPredictNextBusTime_NoModelReturnsEmpty(t *testing.T) {
	old := etaModel
	etaModel = nil
	t.Cleanup(func() { etaModel = old })

	got := predictNextBusTime(nil, busStopCtx{}, predictionInputs{nextDep: time.Now()})
	if got != "" {
		t.Fatalf("want empty, got %q", got)
	}
}

func TestPredictNextBusTime_NoDepartureReturnsEmpty(t *testing.T) {
	old := etaModel
	etaModel = &leaves.Ensemble{}
	t.Cleanup(func() { etaModel = old })

	got := predictNextBusTime(nil, busStopCtx{}, predictionInputs{})
	if got != "" {
		t.Fatalf("want empty, got %q", got)
	}
}

func TestPredictNextBusTime_NoTravelAverageReturnsDeparture(t *testing.T) {
	old := etaModel
	etaModel = &leaves.Ensemble{}
	t.Cleanup(func() { etaModel = old })

	now := time.Date(2026, 7, 3, 8, 0, 0, 0, taipei)
	dep := time.Date(2026, 1, 1, 9, 30, 0, 0, taipei)
	got := predictNextBusTime(nil, busStopCtx{}, predictionInputs{
		now:       now,
		nextDep:   dep,
		travelAvg: 0,
	})
	want := time.Date(2026, 7, 3, 9, 30, 0, 0, taipei).Format(time.RFC3339)
	if got != want {
		t.Fatalf("want %q, got %q", want, got)
	}
}

func TestBaselineArrival(t *testing.T) {
	now := time.Date(2026, 7, 6, 8, 0, 0, 0, taipei)
	dep := time.Date(2026, 1, 1, 8, 5, 0, 0, taipei)

	t.Run("no departure yields zero time", func(t *testing.T) {
		if got := baselineArrival(busStopCtx{}, predictionInputs{now: now}); !got.IsZero() {
			t.Fatalf("want zero time, got %v", got)
		}
	})

	t.Run("departure plus travel average", func(t *testing.T) {
		got := baselineArrival(busStopCtx{}, predictionInputs{
			now: now, nextDep: dep, travelAvg: 120, hasTravelAvg: true,
		})
		want := time.Date(2026, 7, 6, 8, 7, 0, 0, taipei)
		if !got.Equal(want) {
			t.Fatalf("got %v, want %v", got, want)
		}
	})

	t.Run("no travel average and no max yields bare departure", func(t *testing.T) {
		got := baselineArrival(busStopCtx{}, predictionInputs{now: now, nextDep: dep})
		want := time.Date(2026, 7, 6, 8, 5, 0, 0, taipei)
		if !got.Equal(want) {
			t.Fatalf("got %v, want %v", got, want)
		}
	})

	t.Run("interpolates from route max by sequence ratio", func(t *testing.T) {
		got := baselineArrival(
			busStopCtx{stopSequence: 5, totalStops: 10},
			predictionInputs{now: now, nextDep: dep, maxTravelAvg: 600},
		)
		want := time.Date(2026, 7, 6, 8, 10, 0, 0, taipei)
		if !got.Equal(want) {
			t.Fatalf("got %v, want %v", got, want)
		}
	})
}

func TestBoolToFloat64(t *testing.T) {
	if got := boolToFloat64(true); got != 1 {
		t.Fatalf("true = %v, want 1", got)
	}
	if got := boolToFloat64(false); got != 0 {
		t.Fatalf("false = %v, want 0", got)
	}
}
