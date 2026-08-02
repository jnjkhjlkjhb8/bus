package main

import (
	"context"
	"errors"
	"regexp"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
	pgxmock "github.com/pashagolub/pgxmock/v4"
)

// newRetentionMock returns a pgxmock pool using the library's default regexp
// matcher (the batched delete spans multiple lines, so an exact-text matcher
// would be brittle) and fails the test on any unmet expectation.
func newRetentionMock(t *testing.T) pgxmock.PgxPoolIface {
	t.Helper()
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatalf("pgxmock.NewPool: %v", err)
	}
	t.Cleanup(func() {
		if err := db.ExpectationsWereMet(); err != nil {
			t.Errorf("unmet database expectation: %v", err)
		}
		db.Close()
	})
	return db
}

// TestCleanupPredictionErrorsCapsDeleteBatches guards the retention rewrite: a
// single unbounded 30-day DELETE is replaced with capped batches. With more
// stale rows than one batch holds, cleanupPredictionErrors must issue more than
// one DELETE, each bounded by the batch-size argument.
func TestCleanupPredictionErrorsCapsDeleteBatches(t *testing.T) {
	db := newRetentionMock(t)

	perrDelete := regexp.QuoteMeta("bus_eta_prediction_error")
	db.ExpectExec(perrDelete).
		WithArgs(cleanupBatchSize).
		WillReturnResult(pgxmock.NewResult("DELETE", int64(cleanupBatchSize)))
	db.ExpectExec(perrDelete).
		WithArgs(cleanupBatchSize).
		WillReturnResult(pgxmock.NewResult("DELETE", 37))

	if err := cleanupPredictionErrors(context.Background(), db); err != nil {
		t.Fatalf("cleanupPredictionErrors: %v", err)
	}
}

// cancelAfterExec cancels its own context after a chosen number of Exec calls
// land on the wrapped pgxmock pool, so a test can simulate cancellation
// arriving strictly between two batches of the same cleanup loop rather than
// before the run starts.
type cancelAfterExec struct {
	pgxmock.PgxPoolIface
	cancel   context.CancelFunc
	cancelAt int
	execs    int
}

func (d *cancelAfterExec) Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error) {
	tag, err := d.PgxPoolIface.Exec(ctx, sql, args...)
	d.execs++
	if d.execs == d.cancelAt {
		d.cancel()
	}
	return tag, err
}

// TestCleanupPredictionErrorsStopsOnContextCancellation proves the batch loop
// checks ctx between batches instead of looping until the table is empty
// regardless of cancellation, and that the cancellation surfaces as an error
// rather than being reported as a clean success.
func TestCleanupPredictionErrorsStopsOnContextCancellation(t *testing.T) {
	db := newRetentionMock(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	wrapped := &cancelAfterExec{PgxPoolIface: db, cancel: cancel, cancelAt: 1}

	// The first batch reports a full batch, so the loop wants to continue;
	// cancellation lands immediately after, so no second Exec may issue.
	db.ExpectExec(regexp.QuoteMeta("bus_eta_prediction_error")).
		WithArgs(cleanupBatchSize).
		WillReturnResult(pgxmock.NewResult("DELETE", int64(cleanupBatchSize)))

	err := cleanupPredictionErrors(ctx, wrapped)
	if err == nil {
		t.Fatal("cleanupPredictionErrors: want error on context cancellation, got nil")
	}
	if !errors.Is(err, context.Canceled) {
		t.Errorf("cleanupPredictionErrors error = %v, want context.Canceled in chain", err)
	}
}

// A delete failure must reach the caller: runDaily gates its retry on the
// returned error, so swallowing it would silently stop retention.
func TestCleanupPredictionErrorsReportsFailure(t *testing.T) {
	db := newRetentionMock(t)
	wantErr := errors.New("connection reset")
	db.ExpectExec(regexp.QuoteMeta("bus_eta_prediction_error")).
		WithArgs(cleanupBatchSize).
		WillReturnError(wantErr)

	err := cleanupPredictionErrors(context.Background(), db)
	if err == nil {
		t.Fatal("cleanupPredictionErrors: want error when the delete fails, got nil")
	}
	if !errors.Is(err, wantErr) {
		t.Errorf("cleanupPredictionErrors error = %v, want to wrap %v", err, wantErr)
	}
}
