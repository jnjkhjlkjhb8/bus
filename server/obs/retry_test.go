package obs

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestRetryTransientEventuallySucceeds(t *testing.T) {
	calls := 0
	err := Retry(context.Background(), 3, time.Millisecond, func() error {
		calls++
		if calls < 3 {
			return Transient(errors.New("flaky"))
		}
		return nil
	})
	if err != nil {
		t.Fatalf("expected success, got %v", err)
	}
	if calls != 3 {
		t.Fatalf("expected 3 calls, got %d", calls)
	}
}

func TestRetryPermanentFailsImmediately(t *testing.T) {
	calls := 0
	err := Retry(context.Background(), 3, time.Millisecond, func() error {
		calls++
		return errors.New("bad data")
	})
	if err == nil || calls != 1 {
		t.Fatalf("expected 1 call with error, got calls=%d err=%v", calls, err)
	}
}

func TestRetryExhaustsAttempts(t *testing.T) {
	calls := 0
	err := Retry(context.Background(), 3, time.Millisecond, func() error {
		calls++
		return Transient(errors.New("down"))
	})
	if !errors.Is(err, ErrTransient) || calls != 3 {
		t.Fatalf("expected 3 calls transient error, got calls=%d err=%v", calls, err)
	}
}

func TestRetryCtxCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	err := Retry(ctx, 3, time.Hour, func() error {
		return Transient(errors.New("down"))
	})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("expected context.Canceled, got %v", err)
	}
}
