package main

import (
	"math"
	"testing"
	"time"
)

// The sampling window has to be exactly one tick wide. Narrower and a tick that
// fires a second late records nothing at all; wider and two consecutive ticks
// both record, which is the redundancy the sampling exists to remove.
func TestSnapshotTickCoversExactlyOneTickPerInterval(t *testing.T) {
	interval := int64(historySnapshotInterval.Seconds())
	tick := int64(busEtaTickInterval.Seconds())
	// One interval's worth of ticks, from an instant aligned to the interval.
	base := time.Unix(1754110800-1754110800%interval, 0)
	var recorded int
	for at := int64(0); at < interval; at += tick {
		if snapshotTick(base.Add(time.Duration(at)*time.Second), busEtaTickInterval) {
			recorded++
		}
	}
	if recorded != 1 {
		t.Errorf("snapshots per %v = %d, want 1", historySnapshotInterval, recorded)
	}
	// Location must not move the boundary: runCity reads the tick instant in
	// Taipei time and Unix seconds are the same instant either way.
	if snapshotTick(base, busEtaTickInterval) != snapshotTick(base.In(time.UTC), busEtaTickInterval) {
		t.Error("snapshotTick disagrees with itself across zones")
	}
}

// The fast cron (Taipei/NewTaipei, busEtaFastTickInterval) needs the same
// one-snapshot-per-interval property at its own, narrower tick width.
func TestSnapshotTickCoversExactlyOneTickPerIntervalAtFastCadence(t *testing.T) {
	interval := int64(historySnapshotInterval.Seconds())
	tick := int64(busEtaFastTickInterval.Seconds())
	base := time.Unix(1754110800-1754110800%interval, 0)
	var recorded int
	for at := int64(0); at < interval; at += tick {
		if snapshotTick(base.Add(time.Duration(at)*time.Second), busEtaFastTickInterval) {
			recorded++
		}
	}
	if recorded != 1 {
		t.Errorf("snapshots per %v = %d, want 1", historySnapshotInterval, recorded)
	}
}

// Arrivals are the rows measurePredictionError matches a prediction against.
// matchPredictionActual takes the first arrival within 30 minutes, so a sampled-
// away arrival is not a lost sample — it silently scores the prediction against
// the next bus.
func TestRecordsHistoryAlwaysKeepsArrivals(t *testing.T) {
	for _, tc := range []struct {
		estimate int32
		snapshot bool
		want     bool
	}{
		{estimate: 0, snapshot: false, want: true},
		{estimate: 0, snapshot: true, want: true},
		{estimate: 1, snapshot: false, want: false},
		{estimate: 1, snapshot: true, want: true},
		{estimate: 1800, snapshot: false, want: false},
		{estimate: 1800, snapshot: true, want: true},
	} {
		if got := recordsHistory(tc.estimate, tc.snapshot); got != tc.want {
			t.Errorf("recordsHistory(%d, %v) = %v, want %v",
				tc.estimate, tc.snapshot, got, tc.want)
		}
	}
}

func TestHaversine(t *testing.T) {
	d := haversine(35.6762, 139.6503, 34.6937, 135.5023)
	if d < 350000 || d > 450000 {
		t.Errorf("expected ~400km Tokyo-Osaka, got %f", d)
	}
	if haversine(25.0, 121.5, 25.0, 121.5) != 0 {
		t.Error("same point should be 0")
	}
	_ = math.Pi
}
