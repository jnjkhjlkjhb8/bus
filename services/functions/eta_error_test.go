package main

import (
	"testing"
	"time"
)

func TestMatchPredictionActual(t *testing.T) {
	base := time.Date(2026, 7, 6, 8, 0, 0, 0, time.UTC)
	window := 30 * time.Minute

	preds := []predictionRecord{
		// Matches the arrival 5 min later.
		{subRouteUID: "R1", direction: 0, stopUID: "S1", source: sourceModel, predictedAt: base, predictedSecs: 240},
		// No arrival at this stop => dropped.
		{subRouteUID: "R1", direction: 0, stopUID: "S9", source: sourceTDX, predictedAt: base, predictedSecs: 100},
		// Arrival exists but before predictedAt => dropped.
		{subRouteUID: "R2", direction: 1, stopUID: "S2", source: sourcePropagation, predictedAt: base.Add(20 * time.Minute), predictedSecs: 60},
		// Arrival exists but beyond the window => dropped.
		{subRouteUID: "R3", direction: 0, stopUID: "S3", source: sourceSchedule, predictedAt: base, predictedSecs: 60},
	}
	arrivals := []arrivalEvent{
		{subRouteUID: "R1", direction: 0, stopUID: "S1", arrivedAt: base.Add(5 * time.Minute)},
		{subRouteUID: "R2", direction: 1, stopUID: "S2", arrivedAt: base.Add(10 * time.Minute)}, // before pred-at of R2 pred
		{subRouteUID: "R3", direction: 0, stopUID: "S3", arrivedAt: base.Add(45 * time.Minute)}, // beyond window
	}

	got := matchPredictionActual(preds, arrivals, window)
	if len(got) != 1 {
		t.Fatalf("matched %d, want 1: %+v", len(got), got)
	}
	m := got[0]
	if m.subRouteUID != "R1" || m.stopUID != "S1" || m.source != sourceModel {
		t.Fatalf("unexpected match: %+v", m)
	}
	if m.predictedSecs != 240 {
		t.Fatalf("predictedSecs = %d, want 240", m.predictedSecs)
	}
	if m.actualSecs != 300 {
		t.Fatalf("actualSecs = %d, want 300", m.actualSecs)
	}
}

func TestMatchPredictionActual_PicksEarliestArrival(t *testing.T) {
	base := time.Date(2026, 7, 6, 8, 0, 0, 0, time.UTC)
	preds := []predictionRecord{
		{subRouteUID: "R1", direction: 0, stopUID: "S1", source: sourceTDX, predictedAt: base, predictedSecs: 120},
	}
	// Two arrivals after the prediction; the earlier one is the actual.
	arrivals := []arrivalEvent{
		{subRouteUID: "R1", direction: 0, stopUID: "S1", arrivedAt: base.Add(8 * time.Minute)},
		{subRouteUID: "R1", direction: 0, stopUID: "S1", arrivedAt: base.Add(3 * time.Minute)},
	}
	got := matchPredictionActual(preds, arrivals, 30*time.Minute)
	if len(got) != 1 {
		t.Fatalf("matched %d, want 1", len(got))
	}
	if got[0].actualSecs != 180 {
		t.Fatalf("actualSecs = %d, want 180 (earliest arrival)", got[0].actualSecs)
	}
}

func TestAggregateMAE(t *testing.T) {
	errs := []matchedError{
		// R1/model: |100-120|=20, |200-160|=40 => MAE 30 over 2.
		{subRouteUID: "R1", source: sourceModel, predictedSecs: 100, actualSecs: 120},
		{subRouteUID: "R1", source: sourceModel, predictedSecs: 200, actualSecs: 160},
		// R1/propagation: |50-60|=10 => MAE 10 over 1.
		{subRouteUID: "R1", source: sourcePropagation, predictedSecs: 50, actualSecs: 60},
		// R2/tdx: |300-300|=0 => MAE 0 over 1.
		{subRouteUID: "R2", source: sourceTDX, predictedSecs: 300, actualSecs: 300},
	}
	got := aggregateMAE(errs)
	if len(got) != 3 {
		t.Fatalf("groups = %d, want 3: %+v", len(got), got)
	}
	// Sorted by route then source.
	want := []maeStat{
		{subRouteUID: "R1", source: sourceModel, maeSeconds: 30, samples: 2},
		{subRouteUID: "R1", source: sourcePropagation, maeSeconds: 10, samples: 1},
		{subRouteUID: "R2", source: sourceTDX, maeSeconds: 0, samples: 1},
	}
	for i, w := range want {
		g := got[i]
		if g.subRouteUID != w.subRouteUID || g.source != w.source || g.samples != w.samples || g.maeSeconds != w.maeSeconds {
			t.Fatalf("group %d = %+v, want %+v", i, g, w)
		}
	}
}

func TestAggregateMAE_Empty(t *testing.T) {
	if got := aggregateMAE(nil); len(got) != 0 {
		t.Fatalf("want empty, got %+v", got)
	}
}
