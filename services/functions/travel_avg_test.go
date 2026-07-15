package main

import (
	"context"
	"errors"
	"regexp"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	pgxmock "github.com/pashagolub/pgxmock/v4"
)

// newTravelAvgMock returns a pgxmock pool using the library's default regexp
// matcher (the batched departure query spans multiple lines, so an exact-text
// matcher would be brittle) and fails the test on any unmet expectation.
func newTravelAvgMock(t *testing.T) pgxmock.PgxPoolIface {
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

const depBatchQueryPattern = `SELECT k\.sub_route_uid, k\.direction, k\.day_of_week, dep\.dep\s+FROM unnest`

// TestBatchDepartureTimesIssuesOneQueryForManyTuples is the query-count guard
// for the getDepTimes N+1: computeTravelAvg previously issued one
// origin-departure query per distinct (sub_route_uid, direction, day_of_week)
// tuple. With three distinct cache-missed tuples requested at once,
// batchDepartureTimes must issue exactly one query carrying all three, not
// three separate round trips.
func TestBatchDepartureTimesIssuesOneQueryForManyTuples(t *testing.T) {
	db := newTravelAvgMock(t)
	keys := []depKey{
		{subRouteUID: "R1", direction: 0, dayOfWeek: 1},
		{subRouteUID: "R2", direction: 1, dayOfWeek: 2},
		{subRouteUID: "R3", direction: 0, dayOfWeek: 3},
	}

	db.ExpectQuery(depBatchQueryPattern).
		WithArgs(
			[]string{"R1", "R2", "R3"},
			[]int16{0, 1, 0},
			[]int16{1, 2, 3},
			[]int16{1 << ((1 + 6) % 7), 1 << ((2 + 6) % 7), 1 << ((3 + 6) % 7)},
		).
		WillReturnRows(pgxmock.NewRows([]string{"sub_route_uid", "direction", "day_of_week", "dep"}).
			AddRow("R1", int16(0), int16(1), mustParseClock(t, "08:00:00")))

	result, err := batchDepartureTimes(context.Background(), db, keys)
	if err != nil {
		t.Fatalf("batchDepartureTimes: %v", err)
	}
	if got := len(result[depKey{subRouteUID: "R1", direction: 0, dayOfWeek: 1}]); got != 1 {
		t.Errorf("R1 departures = %d, want 1", got)
	}
}

// TestBatchDepartureTimesMapsResultsDeterministically pins the tuple-to-result
// mapping: a batch response mixing rows for several keys, including a key with
// multiple departures and a key with none, must be regrouped back onto the
// exact key it belongs to and nothing else.
func TestBatchDepartureTimesMapsResultsDeterministically(t *testing.T) {
	db := newTravelAvgMock(t)
	keyA := depKey{subRouteUID: "R1", direction: 0, dayOfWeek: 1}
	keyB := depKey{subRouteUID: "R2", direction: 0, dayOfWeek: 1}
	keyC := depKey{subRouteUID: "R3", direction: 1, dayOfWeek: 5}

	db.ExpectQuery(depBatchQueryPattern).
		WithArgs(pgxmock.AnyArg(), pgxmock.AnyArg(), pgxmock.AnyArg(), pgxmock.AnyArg()).
		WillReturnRows(pgxmock.NewRows([]string{"sub_route_uid", "direction", "day_of_week", "dep"}).
			AddRow("R1", int16(0), int16(1), mustParseClock(t, "08:00:00")).
			AddRow("R2", int16(0), int16(1), mustParseClock(t, "08:10:00")).
			AddRow("R2", int16(0), int16(1), mustParseClock(t, "08:40:00")))

	result, err := batchDepartureTimes(context.Background(), db, []depKey{keyA, keyB, keyC})
	if err != nil {
		t.Fatalf("batchDepartureTimes: %v", err)
	}
	if got := len(result[keyA]); got != 1 {
		t.Errorf("keyA departures = %d, want 1", got)
	}
	if got := len(result[keyB]); got != 2 {
		t.Errorf("keyB departures = %d, want 2", got)
	}
	if got := len(result[keyC]); got != 0 {
		t.Errorf("keyC (no matching rows) departures = %d, want 0", got)
	}
}

// TestBatchDepartureTimesEmptyKeysSkipsQuery guards against issuing a query
// with empty arrays when there is nothing to look up.
func TestBatchDepartureTimesEmptyKeysSkipsQuery(t *testing.T) {
	db := newTravelAvgMock(t)
	result, err := batchDepartureTimes(context.Background(), db, nil)
	if err != nil {
		t.Fatalf("batchDepartureTimes: %v", err)
	}
	if len(result) != 0 {
		t.Errorf("result = %v, want empty", result)
	}
}

func mustParseClock(t *testing.T, s string) time.Time {
	t.Helper()
	tm, err := time.Parse(time.TimeOnly, s)
	if err != nil {
		t.Fatalf("parse clock %q: %v", s, err)
	}
	return tm
}

// TestCleanupBusHistoryCapsDeleteBatches guards the retention rewrite: a
// single unbounded 30-day DELETE is replaced with capped batches. With more
// stale rows than one batch holds, cleanupBusHistory must issue more than one
// DELETE against bus_eta_history, each bounded by the batch-size argument.
func TestCleanupBusHistoryCapsDeleteBatches(t *testing.T) {
	db := newTravelAvgMock(t)

	historyDelete := regexp.QuoteMeta("bus_eta_history")
	db.ExpectExec(historyDelete).
		WithArgs(cleanupBatchSize).
		WillReturnResult(pgxmock.NewResult("DELETE", int64(cleanupBatchSize)))
	db.ExpectExec(historyDelete).
		WithArgs(cleanupBatchSize).
		WillReturnResult(pgxmock.NewResult("DELETE", 37))

	perrDelete := regexp.QuoteMeta("bus_eta_prediction_error")
	db.ExpectExec(perrDelete).
		WithArgs(cleanupBatchSize).
		WillReturnResult(pgxmock.NewResult("DELETE", 0))

	if err := cleanupBusHistory(context.Background(), db); err != nil {
		t.Fatalf("cleanupBusHistory: %v", err)
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

// TestCleanupBusHistoryStopsOnContextCancellation proves the batch loop checks
// ctx between batches instead of looping until the table is empty regardless
// of cancellation, and that the cancellation surfaces as an error rather than
// being reported as a clean success.
func TestCleanupBusHistoryStopsOnContextCancellation(t *testing.T) {
	db := newTravelAvgMock(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	wrapped := &cancelAfterExec{PgxPoolIface: db, cancel: cancel, cancelAt: 1}

	// First bus_eta_history batch reports a full batch (the loop wants to
	// continue); cancellation lands immediately after, so the second batch of
	// bus_eta_history, and the bus_eta_prediction_error cleanup entirely, must
	// never issue an Exec.
	historyDelete := regexp.QuoteMeta("bus_eta_history")
	db.ExpectExec(historyDelete).
		WithArgs(cleanupBatchSize).
		WillReturnResult(pgxmock.NewResult("DELETE", int64(cleanupBatchSize)))

	err := cleanupBusHistory(ctx, wrapped)
	if err == nil {
		t.Fatal("cleanupBusHistory: want error on context cancellation, got nil")
	}
	if !errors.Is(err, context.Canceled) {
		t.Errorf("cleanupBusHistory error = %v, want context.Canceled in chain", err)
	}
}

// TestCleanupBusHistoryReportsPartialFailure proves a failure deleting the
// prediction-error table is not swallowed just because bus_eta_history's
// cleanup succeeded: both are independent retention targets and a caller
// relying on the returned error to gate a completion marker must see it.
func TestCleanupBusHistoryReportsPartialFailure(t *testing.T) {
	db := newTravelAvgMock(t)

	historyDelete := regexp.QuoteMeta("bus_eta_history")
	db.ExpectExec(historyDelete).
		WithArgs(cleanupBatchSize).
		WillReturnResult(pgxmock.NewResult("DELETE", 5))

	perrDelete := regexp.QuoteMeta("bus_eta_prediction_error")
	wantErr := errors.New("connection reset")
	db.ExpectExec(perrDelete).
		WithArgs(cleanupBatchSize).
		WillReturnError(wantErr)

	err := cleanupBusHistory(context.Background(), db)
	if err == nil {
		t.Fatal("cleanupBusHistory: want error when prediction-error cleanup fails, got nil")
	}
	if !errors.Is(err, wantErr) {
		t.Errorf("cleanupBusHistory error = %v, want to wrap %v", err, wantErr)
	}
}
