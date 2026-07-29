package main

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"testing"
	"time"
)

// fakeExecer records every statement archiveInsert issues so a test can assert
// how a row set was split across INSERTs.
type fakeExecer struct {
	stmts []string
	args  [][]any
	err   error
}

func (f *fakeExecer) ExecContext(_ context.Context, q string, a ...any) (sql.Result, error) {
	f.stmts = append(f.stmts, q)
	f.args = append(f.args, a)
	return nil, f.err
}

// fakeHistory stands in for the MySQL history host. The historySource seam is
// stated in domain rows precisely so tests can do this without a driver.
type fakeHistory struct {
	crossingRows []crossing
	arrivalRows  []arrivalEvent
	err          error
	since        time.Time
}

func (f *fakeHistory) crossings(_ context.Context, _ time.Duration) ([]crossing, error) {
	return f.crossingRows, f.err
}

func (f *fakeHistory) arrivals(_ context.Context, since time.Time) ([]arrivalEvent, error) {
	f.since = since
	return f.arrivalRows, f.err
}

// The interpolated crossing must land proportionally between the two samples:
// an estimate falling 60 → -20 over 40s crosses zero at 75% of the gap.
func TestInterpolateCrossing(t *testing.T) {
	prevAt := time.Date(2026, 7, 30, 8, 0, 0, 0, time.UTC)
	got := interpolateCrossing(prevAt, prevAt.Add(40*time.Second), 60, -20)
	if want := prevAt.Add(30 * time.Second); !got.Equal(want) {
		t.Errorf("crossing = %s, want %s", got, want)
	}
}

// An estimate that lands exactly on zero crossed at the later sample, not
// somewhere before it.
func TestInterpolateCrossingExactZero(t *testing.T) {
	prevAt := time.Date(2026, 7, 30, 8, 0, 0, 0, time.UTC)
	at := prevAt.Add(30 * time.Second)
	if got := interpolateCrossing(prevAt, at, 45, 0); !got.Equal(at) {
		t.Errorf("crossing = %s, want %s", got, at)
	}
}

// With no history host configured the rebuild must not run: upserting from zero
// crossings would look like a successful rebuild that found nothing.
func TestComputeTravelAvgSkipsWithoutHistory(t *testing.T) {
	if err := computeTravelAvg(context.Background(), nil, nil); err != nil {
		t.Errorf("want a silent skip, got %v", err)
	}
}

func TestFillPredictionActualsSkipsWithoutHistory(t *testing.T) {
	n, err := fillPredictionActuals(context.Background(), nil, nil)
	if err != nil || n != 0 {
		t.Errorf("fillPredictionActuals = (%d, %v), want (0, nil)", n, err)
	}
}

func TestArchiveInsertSQL(t *testing.T) {
	got := archiveInsertSQL("bike_availability_history", []string{"a", "b"}, 3)
	want := "INSERT IGNORE INTO bike_availability_history (a,b) VALUES (?,?),(?,?),(?,?)"
	if got != want {
		t.Errorf("archiveInsertSQL:\n got %q\nwant %q", got, want)
	}
}

// archiveInsert must split at archiveRowsPerInsert: MySQL rejects a statement
// past 65535 placeholders, so an unsplit day of ~200k rows would fail outright.
func TestArchiveInsertSplitsBatches(t *testing.T) {
	cols := []string{"a", "b"}
	rows := make([][]any, 2500)
	for i := range rows {
		rows[i] = []any{i, i * 2}
	}
	f := &fakeExecer{}
	if err := archiveInsert(context.Background(), f, "t", cols, rows); err != nil {
		t.Fatalf("archiveInsert: %v", err)
	}
	wantRows := []int{archiveRowsPerInsert, archiveRowsPerInsert, 2500 - 2*archiveRowsPerInsert}
	if len(f.stmts) != len(wantRows) {
		t.Fatalf("statements = %d, want %d", len(f.stmts), len(wantRows))
	}
	for i, n := range wantRows {
		if got := strings.Count(f.stmts[i], "(?,?)"); got != n {
			t.Errorf("statement %d has %d row groups, want %d", i, got, n)
		}
		if got := len(f.args[i]); got != n*len(cols) {
			t.Errorf("statement %d has %d args, want %d", i, got, n*len(cols))
		}
	}
	// Every row must appear exactly once across the batches, in order.
	var flat []any
	for _, a := range f.args {
		flat = append(flat, a...)
	}
	if len(flat) != 5000 {
		t.Fatalf("total args = %d, want 5000", len(flat))
	}
	if flat[0] != 0 || flat[4998] != 2499 {
		t.Errorf("row order lost: first=%v last-pair-head=%v", flat[0], flat[4998])
	}
}

func TestArchiveInsertNoopWhenDisabled(t *testing.T) {
	if err := archiveInsert(context.Background(), nil, "t", []string{"a"}, [][]any{{1}}); err != nil {
		t.Errorf("nil archive should be a no-op, got %v", err)
	}
	f := &fakeExecer{}
	if err := archiveInsert(context.Background(), f, "t", []string{"a"}, nil); err != nil {
		t.Errorf("empty rows should be a no-op, got %v", err)
	}
	if len(f.stmts) != 0 {
		t.Errorf("empty rows issued %d statements, want 0", len(f.stmts))
	}
}

// A row whose width does not match cols would silently shift every later value
// into the wrong column, so it must fail loudly instead.
func TestArchiveInsertRejectsRowWidthMismatch(t *testing.T) {
	f := &fakeExecer{}
	err := archiveInsert(context.Background(), f, "t", []string{"a", "b"}, [][]any{{1, 2}, {3}})
	if err == nil {
		t.Fatal("want error on short row, got nil")
	}
	if !strings.Contains(err.Error(), "want 2") {
		t.Errorf("error should name the expected width, got %v", err)
	}
}

func TestArchiveInsertWrapsExecError(t *testing.T) {
	sentinel := errors.New("boom")
	f := &fakeExecer{err: sentinel}
	err := archiveInsert(context.Background(), f, "t", []string{"a"}, [][]any{{1}})
	if !errors.Is(err, sentinel) {
		t.Errorf("error = %v, want it to wrap %v", err, sentinel)
	}
}

// MySQL DATETIME carries no zone, so timestamps must leave Go already in UTC
// rather than relying on the driver's loc setting.
func TestArchiveUTC(t *testing.T) {
	local := time.Date(2026, 7, 30, 8, 0, 0, 0, taipei)
	got := archiveUTC([]any{"x", local, nil, int32(3)})
	ts, ok := got[1].(time.Time)
	if !ok {
		t.Fatalf("value 1 = %T, want time.Time", got[1])
	}
	if ts.Location() != time.UTC {
		t.Errorf("location = %v, want UTC", ts.Location())
	}
	if !ts.Equal(local) {
		t.Errorf("instant changed: %s != %s", ts, local)
	}
	if got[0] != "x" || got[2] != nil || got[3] != int32(3) {
		t.Errorf("non-time values altered: %v", got)
	}
}

// A batch must never exceed MySQL's placeholder cap; the column count is the
// half of that product most likely to drift.
func TestBusEtaHistoryColsFitPlaceholderCeiling(t *testing.T) {
	if n := len(busEtaHistoryCols); n != 20 {
		t.Errorf("bus_eta_history insert columns = %d, want 20", n)
	}
	if got := archiveRowsPerInsert * len(busEtaHistoryCols); got > 65535 {
		t.Errorf("batch would bind %d placeholders, over MySQL's 65535 cap", got)
	}
}

// archiveInsert must normalize timestamps itself: a caller that forgets would
// otherwise write local-clock values into a zone-less DATETIME column.
func TestArchiveInsertNormalizesTimestamps(t *testing.T) {
	local := time.Date(2026, 7, 30, 8, 0, 0, 0, taipei)
	f := &fakeExecer{}
	if err := archiveInsert(context.Background(), f, "t", []string{"a"}, [][]any{{local}}); err != nil {
		t.Fatalf("archiveInsert: %v", err)
	}
	ts, ok := f.args[0][0].(time.Time)
	if !ok {
		t.Fatalf("arg = %T, want time.Time", f.args[0][0])
	}
	if ts.Location() != time.UTC {
		t.Errorf("location = %v, want UTC", ts.Location())
	}
}
