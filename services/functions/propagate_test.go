package main

import (
	"math"
	"testing"
	"time"
)

func TestDecayDelay(t *testing.T) {
	tests := []struct {
		name   string
		delay  float64
		seqGap int
		want   float64
	}{
		{"zero gap unchanged", 100, 0, 100},
		{"negative gap unchanged", 100, -2, 100},
		{"one stop", 100, 1, 90},
		{"two stops", 100, 2, 81},
		{"three stops", 100, 3, 72.9},
		{"negative delay decays too", -50, 2, -40.5},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := decayDelay(tt.delay, tt.seqGap)
			if math.Abs(got-tt.want) > 1e-6 {
				t.Fatalf("decayDelay(%v, %d) = %v, want %v", tt.delay, tt.seqGap, got, tt.want)
			}
		})
	}
}

func TestLatestUpstreamDelay(t *testing.T) {
	now := time.Date(2026, 7, 6, 8, 0, 0, 0, taipei)
	fresh := now.Add(-1 * time.Minute)
	stale := now.Add(-5 * time.Minute)

	tests := []struct {
		name      string
		obs       []upstreamObs
		targetSeq int
		wantOK    bool
		wantSeq   int
		wantDelay float64
	}{
		{
			name:      "no observations",
			obs:       nil,
			targetSeq: 5,
			wantOK:    false,
		},
		{
			name: "picks closest upstream",
			obs: []upstreamObs{
				{stopSequence: 1, delaySeconds: 30, observedAt: fresh},
				{stopSequence: 3, delaySeconds: 60, observedAt: fresh},
				{stopSequence: 2, delaySeconds: 45, observedAt: fresh},
			},
			targetSeq: 5,
			wantOK:    true,
			wantSeq:   3,
			wantDelay: 60,
		},
		{
			name: "ignores observation at target",
			obs: []upstreamObs{
				{stopSequence: 5, delaySeconds: 99, observedAt: fresh},
				{stopSequence: 2, delaySeconds: 45, observedAt: fresh},
			},
			targetSeq: 5,
			wantOK:    true,
			wantSeq:   2,
			wantDelay: 45,
		},
		{
			name: "ignores observation past target",
			obs: []upstreamObs{
				{stopSequence: 7, delaySeconds: 99, observedAt: fresh},
			},
			targetSeq: 5,
			wantOK:    false,
		},
		{
			name: "skips stale, keeps fresh",
			obs: []upstreamObs{
				{stopSequence: 4, delaySeconds: 99, observedAt: stale},
				{stopSequence: 1, delaySeconds: 20, observedAt: fresh},
			},
			targetSeq: 5,
			wantOK:    true,
			wantSeq:   1,
			wantDelay: 20,
		},
		{
			name: "all stale yields nothing",
			obs: []upstreamObs{
				{stopSequence: 4, delaySeconds: 99, observedAt: stale},
			},
			targetSeq: 5,
			wantOK:    false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			delay, seq, ok := latestUpstreamDelay(tt.obs, tt.targetSeq, now)
			if ok != tt.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tt.wantOK)
			}
			if !tt.wantOK {
				return
			}
			if seq != tt.wantSeq {
				t.Fatalf("seq = %d, want %d", seq, tt.wantSeq)
			}
			if delay != tt.wantDelay {
				t.Fatalf("delay = %v, want %v", delay, tt.wantDelay)
			}
		})
	}
}

func TestPropagateDelay(t *testing.T) {
	now := time.Date(2026, 7, 6, 8, 0, 0, 0, taipei)
	baseline := now.Add(10 * time.Minute) // downstream schedule+avg arrival

	t.Run("zero baseline returns not ok", func(t *testing.T) {
		_, ok := propagateDelay(time.Time{}, 5, []upstreamObs{
			{stopSequence: 1, delaySeconds: 60, observedAt: now},
		}, now)
		if ok {
			t.Fatal("want not ok for zero baseline")
		}
	})

	t.Run("no upstream returns not ok", func(t *testing.T) {
		_, ok := propagateDelay(baseline, 5, nil, now)
		if ok {
			t.Fatal("want not ok with no observations")
		}
	})

	t.Run("adds decayed delay to baseline", func(t *testing.T) {
		// Observed at seq 2, target seq 5 => gap 3 => 90s * 0.9^3 = 65.61s.
		got, ok := propagateDelay(baseline, 5, []upstreamObs{
			{stopSequence: 2, delaySeconds: 90, observedAt: now},
		}, now)
		if !ok {
			t.Fatal("want ok")
		}
		wantOffset := time.Duration(90*math.Pow(0.9, 3)) * time.Second
		want := baseline.Add(wantOffset)
		if got.Unix() != want.Unix() {
			t.Fatalf("got %v, want %v", got, want)
		}
	})

	t.Run("negative delay pulls arrival earlier", func(t *testing.T) {
		got, ok := propagateDelay(baseline, 3, []upstreamObs{
			{stopSequence: 2, delaySeconds: -60, observedAt: now},
		}, now)
		if !ok {
			t.Fatal("want ok")
		}
		if !got.Before(baseline) {
			t.Fatalf("expected arrival before baseline, got %v (baseline %v)", got, baseline)
		}
	})
}
