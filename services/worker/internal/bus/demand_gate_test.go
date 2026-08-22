package bus

import (
	"context"
	"testing"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/pipeline"
)

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
	if !pipeline.LiveDemandGate(ctx, sink, "bus_eta", "YilanCounty") {
		t.Fatal("first tick was skipped")
	}
	if pipeline.LiveDemandGate(ctx, sink, "bus_eta", "YilanCounty") {
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
