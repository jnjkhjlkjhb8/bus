package main

import (
	"context"
	"errors"
	"testing"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
)

func TestRunLiveIsolatesFailingSpec(t *testing.T) {
	// One spec whose run returns an error (or panics) must not prevent the others
	// from running: runLive isolates each job.
	var ran []string
	specs := []liveSpec{
		{key: "ok1", run: func(context.Context, boundFetch, liveSink) error {
			ran = append(ran, "ok1")
			return nil
		}},
		{key: "boom", run: func(context.Context, boundFetch, liveSink) error {
			return errors.New("boom")
		}},
		{key: "panic", run: func(context.Context, boundFetch, liveSink) error {
			panic("kaboom")
		}},
		{key: "ok2", run: func(context.Context, boundFetch, liveSink) error {
			ran = append(ran, "ok2")
			return nil
		}},
	}
	runLive(context.Background(), &fakeLiveSource{}, &captureLiveSink{}, specs, nil)
	if len(ran) != 2 || ran[0] != "ok1" || ran[1] != "ok2" {
		t.Fatalf("healthy specs ran = %v, want [ok1 ok2]", ran)
	}
}

func TestRunLiveFiltersByKey(t *testing.T) {
	// A non-empty keys slice runs only the matching specs.
	var ran []string
	specs := []liveSpec{
		{key: "a", run: func(context.Context, boundFetch, liveSink) error { ran = append(ran, "a"); return nil }},
		{key: "b", run: func(context.Context, boundFetch, liveSink) error { ran = append(ran, "b"); return nil }},
	}
	runLive(context.Background(), &fakeLiveSource{}, &captureLiveSink{}, specs, []string{"b"})
	if len(ran) != 1 || ran[0] != "b" {
		t.Fatalf("ran = %v, want [b]", ran)
	}
}

// TestLiveDemandGateSkipsUnwatchedCityUntilColdCadence covers the whole point
// of the gate (FDPL-90): an unwatched city must be fetched once per cold
// cadence, not once per tick, and a watched one must never be skipped. It runs
// ticks against one sink so the cold marker written by the first tick is the
// one later ticks read back.
func TestLiveDemandGateSkipsUnwatchedCityUntilColdCadence(t *testing.T) {
	ctx := context.Background()

	sink := &captureLiveSink{}
	fetched := 0
	for range 10 {
		if liveDemandGate(ctx, sink, "bus_eta", "YilanCounty") {
			fetched++
		}
	}
	if fetched != 1 {
		t.Fatalf("unwatched city fetched %d times across 10 ticks, want 1", fetched)
	}
	coldKey := shared.LiveColdKey("bus_eta", "YilanCounty")
	if got := sink.strings[coldKey]; got == "" {
		t.Fatalf("cold marker %q not written", coldKey)
	}
	for _, write := range sink.sets {
		if write.key == coldKey && write.ttl != _liveColdCadence {
			t.Fatalf("cold marker TTL = %v, want %v", write.ttl, _liveColdCadence)
		}
	}

	// The marker expiring is what lets the next fetch through; the fake has no
	// clock, so dropping the key is how a tick past the cadence is expressed.
	delete(sink.strings, coldKey)
	if !liveDemandGate(ctx, sink, "bus_eta", "YilanCounty") {
		t.Fatal("expired cold marker did not release the next fetch")
	}

	watched := &captureLiveSink{
		strings: map[string]string{shared.LiveDemandKey("bus_eta", "YilanCounty"): "1"},
	}
	for range 10 {
		if !liveDemandGate(ctx, watched, "bus_eta", "YilanCounty") {
			t.Fatal("watched city was skipped")
		}
	}
	if len(watched.sets) != 0 {
		t.Fatalf("watched city wrote %d cold markers, want 0", len(watched.sets))
	}

	// A city gated under one dataset must not silence the other: the two jobs
	// poll independently and share nothing but the city name.
	if !liveDemandGate(ctx, sink, "bike", "YilanCounty") {
		t.Fatal("bike was gated by the bus_eta cold marker")
	}
}

// TestLiveDemandGateFetchesWhenRedisFails proves the gate degrades to polling
// rather than to silence: a Redis read failure must not be read as "nobody is
// watching", which would stall every city at once.
func TestLiveDemandGateFetchesWhenRedisFails(t *testing.T) {
	sink := &errStringLiveSink{captureLiveSink: &captureLiveSink{}, err: errors.New("redis down")}
	if !liveDemandGate(context.Background(), sink, "bus_eta", "YilanCounty") {
		t.Fatal("gate skipped the city on a Redis read failure")
	}
}

// errStringLiveSink is a captureLiveSink whose reads always fail.
type errStringLiveSink struct {
	*captureLiveSink
	err error
}

func (s *errStringLiveSink) getString(context.Context, string) (string, error) {
	return "", s.err
}

// TestBusEtaSnapshotTickIgnoresDemandGate covers the interaction the demand
// gate would otherwise break silently (FDPL-90).
//
// snapshotTick is a fixed 30s window per 10 minutes of wall clock, so a
// reduced-cadence fetch lands inside it only about one time in twenty. Gating
// snapshot ticks would cost an unwatched city roughly nine tenths of its
// bus_eta_history rows, and those are the only input segmentsByEstimate
// reduces into bus_segment_time — the observed running times the ETA
// prediction leans on hardest in exactly the rural cities nobody streams.
func TestBusEtaSnapshotTickIgnoresDemandGate(t *testing.T) {
	ctx := context.Background()
	sink := &captureLiveSink{}

	// Go cold first, so the gate alone would skip every later tick.
	if !liveDemandGate(ctx, sink, "bus_eta", "YilanCounty") {
		t.Fatal("first tick was skipped")
	}
	if liveDemandGate(ctx, sink, "bus_eta", "YilanCounty") {
		t.Fatal("second tick was not skipped, so the city is not cold")
	}

	snapshot := busLiveJob{sink: sink, demandDataset: "bus_eta", snapshot: true}
	if !snapshot.shouldRunCity(ctx, "YilanCounty") {
		t.Fatal("a snapshot tick was gated away; bus_eta_history would lose the city")
	}

	// The same job on an ordinary tick is still gated, or the gate saves nothing.
	ordinary := busLiveJob{sink: sink, demandDataset: "bus_eta"}
	if ordinary.shouldRunCity(ctx, "YilanCounty") {
		t.Fatal("a cold city ran on an ordinary tick")
	}

	// busEtaFast carries no dataset, so it is never gated at all.
	fast := busLiveJob{sink: sink}
	if !fast.shouldRunCity(ctx, "YilanCounty") {
		t.Fatal("the ungated Data.taipei job was gated")
	}
}
