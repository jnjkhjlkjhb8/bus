package obs

import (
	"errors"
	"fmt"
	"testing"
)

func TestTransientWrapping(t *testing.T) {
	base := errors.New("conn refused")
	err := Transient(base)
	if !errors.Is(err, ErrTransient) {
		t.Fatal("expected ErrTransient")
	}
	if !errors.Is(err, base) {
		t.Fatal("expected base error preserved")
	}
	wrapped := fmt.Errorf("ingest bus: %w", err)
	if !errors.Is(wrapped, ErrTransient) {
		t.Fatal("expected ErrTransient through extra wrap")
	}
}

func TestTransientNil(t *testing.T) {
	if Transient(nil) != nil {
		t.Fatal("expected nil")
	}
}

func TestNotFoundWrapping(t *testing.T) {
	base := errors.New("no rows")
	err := NotFound(base)
	if !errors.Is(err, ErrNotFound) {
		t.Fatal("expected ErrNotFound")
	}
	if NotFound(nil) != nil {
		t.Fatal("expected nil")
	}
}
