package main

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestWithTimeout_CancelsSlowJob(t *testing.T) {
	var gotErr error
	withTimeout(50*time.Millisecond, func(ctx context.Context) {
		select {
		case <-time.After(2 * time.Second):
			gotErr = nil
		case <-ctx.Done():
			gotErr = ctx.Err()
		}
	})
	if !errors.Is(gotErr, context.DeadlineExceeded) {
		t.Fatalf("expected DeadlineExceeded, got %v", gotErr)
	}
}

func TestWithTimeout_LetsFastJobFinish(t *testing.T) {
	ran := false
	withTimeout(1*time.Second, func(ctx context.Context) { ran = true })
	if !ran {
		t.Fatal("fast job did not run")
	}
}
