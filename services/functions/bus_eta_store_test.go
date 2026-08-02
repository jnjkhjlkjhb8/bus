package main

import (
	"context"
	"testing"
	"time"
)

func TestBusEtaFlusherRunsTaskOffTheCallersContext(t *testing.T) {
	f := &busEtaFlusher{queue: make(chan busEtaFlush, 1), workers: 1, timeout: time.Minute}
	// Checked inside the write, because the flusher cancels the context as soon
	// as the write returns.
	type seen struct {
		err      error
		deadline bool
	}
	ran := make(chan seen, 1)
	f.submit(busEtaFlush{table: "t", rows: 1, write: func(ctx context.Context) {
		_, ok := ctx.Deadline()
		ran <- seen{err: ctx.Err(), deadline: ok}
	}})

	select {
	case got := <-ran:
		if got.err != nil {
			t.Fatalf("flush context = %v, want live", got.err)
		}
		if !got.deadline {
			t.Fatal("flush context has no deadline")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("flush never ran")
	}
}

// A database that cannot keep up must drop batches rather than queue an
// unbounded backlog of increasingly stale rows.
func TestBusEtaFlusherDropsWhenQueueFull(t *testing.T) {
	// Zero workers: nothing drains, so the queue state is deterministic.
	f := &busEtaFlusher{queue: make(chan busEtaFlush, 2), timeout: time.Minute}
	for i := range 5 {
		f.submit(busEtaFlush{table: "t", rows: i, write: func(context.Context) {}})
	}
	if len(f.queue) != 2 {
		t.Fatalf("queued = %d, want 2", len(f.queue))
	}
}
