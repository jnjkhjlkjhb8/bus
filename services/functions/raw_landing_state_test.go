package main

import (
	"bytes"
	"context"
	"errors"
	"regexp"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	pgxmock "github.com/pashagolub/pgxmock/v4"
)

const (
	stateSelectForUpdatePattern = `SELECT last_modified, row_count FROM raw_tdx\.landing_state WHERE table_name=\$1 AND partition_column=\$2 AND partition_value=\$3 FOR UPDATE`
	stateTouchPattern           = `UPDATE raw_tdx\.landing_state SET fetched_at=now\(\), landing_cycle=\$4 WHERE table_name=\$1 AND partition_column=\$2 AND partition_value=\$3`
	stateUpsertPattern          = `INSERT INTO raw_tdx\.landing_state .* ON CONFLICT .* DO UPDATE SET .*`
	stateFreshnessPattern       = `SELECT fetched_at, row_count FROM raw_tdx\.landing_state WHERE table_name=\$1 AND partition_column=\$2 AND partition_value=\$3`
)

func newRawLandingMock(t *testing.T) pgxmock.PgxPoolIface {
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

func expectStateRead(db pgxmock.PgxPoolIface, marker string, rows int64) {
	db.ExpectQuery(stateSelectForUpdatePattern).
		WithArgs("bus_route", "city", "Taipei").
		WillReturnRows(pgxmock.NewRows([]string{"last_modified", "row_count"}).AddRow(marker, rows))
}

func TestVerifyAndTouchRawLandingAcceptsMatchingEmptyAndNonEmpty(t *testing.T) {
	for _, tc := range []struct {
		name     string
		rowCount int64
		hasRows  bool
	}{
		{name: "verified empty", rowCount: 0, hasRows: false},
		{name: "matching nonempty", rowCount: 42, hasRows: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			db := newRawLandingMock(t)
			db.ExpectBegin()
			db.ExpectExec(regexp.QuoteMeta("SET LOCAL lock_timeout = '20s'")).
				WillReturnResult(pgxmock.NewResult("SET", 0))
			expectStateRead(db, "MARKER", tc.rowCount)
			db.ExpectQuery(regexp.QuoteMeta("SELECT EXISTS (SELECT 1 FROM raw_tdx.bus_route WHERE city = $1 LIMIT 1)")).
				WithArgs("Taipei").
				WillReturnRows(pgxmock.NewRows([]string{"exists"}).AddRow(tc.hasRows))
			db.ExpectExec(stateTouchPattern).
				WithArgs("bus_route", "city", "Taipei", "cycle-test").
				WillReturnResult(pgxmock.NewResult("UPDATE", 1))
			db.ExpectCommit()

			if err := verifyAndTouchRawLandingWithDB(
				context.Background(), db, rawTarget{table: "bus_route", partCol: "city", partVal: "Taipei"}, "MARKER", "cycle-test",
			); err != nil {
				t.Fatalf("verifyAndTouchRawLandingWithDB: %v", err)
			}
		})
	}
}

func TestVerifyAndTouchRawLandingRejectsMissingMarkerAndPresenceMismatch(t *testing.T) {
	t.Run("missing state", func(t *testing.T) {
		db := newRawLandingMock(t)
		db.ExpectBegin()
		db.ExpectExec(regexp.QuoteMeta("SET LOCAL lock_timeout = '20s'")).
			WillReturnResult(pgxmock.NewResult("SET", 0))
		db.ExpectQuery(stateSelectForUpdatePattern).
			WithArgs("bus_route", "city", "Taipei").
			WillReturnRows(pgxmock.NewRows([]string{"last_modified", "row_count"}))
		db.ExpectRollback()

		err := verifyAndTouchRawLandingWithDB(
			context.Background(), db, rawTarget{table: "bus_route", partCol: "city", partVal: "Taipei"}, "MARKER", "cycle-test",
		)
		assertLandingMismatch(t, err, "missing_state")
	})

	t.Run("marker mismatch", func(t *testing.T) {
		db := newRawLandingMock(t)
		db.ExpectBegin()
		db.ExpectExec(regexp.QuoteMeta("SET LOCAL lock_timeout = '20s'")).
			WillReturnResult(pgxmock.NewResult("SET", 0))
		expectStateRead(db, "DB-MARKER", 1)
		db.ExpectRollback()

		err := verifyAndTouchRawLandingWithDB(
			context.Background(), db, rawTarget{table: "bus_route", partCol: "city", partVal: "Taipei"}, "HTTP-MARKER", "cycle-test",
		)
		assertLandingMismatch(t, err, "marker")
	})

	for _, tc := range []struct {
		name    string
		rows    int64
		hasRows bool
	}{
		{name: "state empty but raw exists", rows: 0, hasRows: true},
		{name: "state nonempty but raw missing", rows: 3, hasRows: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			db := newRawLandingMock(t)
			db.ExpectBegin()
			db.ExpectExec(regexp.QuoteMeta("SET LOCAL lock_timeout = '20s'")).
				WillReturnResult(pgxmock.NewResult("SET", 0))
			expectStateRead(db, "MARKER", tc.rows)
			db.ExpectQuery(regexp.QuoteMeta("SELECT EXISTS (SELECT 1 FROM raw_tdx.bus_route WHERE city = $1 LIMIT 1)")).
				WithArgs("Taipei").
				WillReturnRows(pgxmock.NewRows([]string{"exists"}).AddRow(tc.hasRows))
			db.ExpectRollback()

			err := verifyAndTouchRawLandingWithDB(
				context.Background(), db, rawTarget{table: "bus_route", partCol: "city", partVal: "Taipei"}, "MARKER", "cycle-test",
			)
			assertLandingMismatch(t, err, "row_presence")
		})
	}

	t.Run("state touch updates exactly one row", func(t *testing.T) {
		db := newRawLandingMock(t)
		db.ExpectBegin()
		db.ExpectExec(regexp.QuoteMeta("SET LOCAL lock_timeout = '20s'")).
			WillReturnResult(pgxmock.NewResult("SET", 0))
		expectStateRead(db, "MARKER", 1)
		db.ExpectQuery(regexp.QuoteMeta("SELECT EXISTS (SELECT 1 FROM raw_tdx.bus_route WHERE city = $1 LIMIT 1)")).
			WithArgs("Taipei").
			WillReturnRows(pgxmock.NewRows([]string{"exists"}).AddRow(true))
		db.ExpectExec(stateTouchPattern).
			WithArgs("bus_route", "city", "Taipei", "cycle-test").
			WillReturnResult(pgxmock.NewResult("UPDATE", 0))
		db.ExpectRollback()

		err := verifyAndTouchRawLandingWithDB(
			context.Background(), db, rawTarget{table: "bus_route", partCol: "city", partVal: "Taipei"}, "MARKER", "cycle-test",
		)
		assertLandingMismatch(t, err, "state_update")
	})
}

func assertLandingMismatch(t *testing.T, err error, reason string) {
	t.Helper()
	if !errors.Is(err, errRawLandingStateMismatch) {
		t.Fatalf("error = %v, want errRawLandingStateMismatch", err)
	}
	var mismatch *rawLandingStateMismatchError
	if !errors.As(err, &mismatch) {
		t.Fatalf("error type = %T, want *rawLandingStateMismatchError", err)
	}
	if mismatch.Reason != reason {
		t.Fatalf("mismatch reason = %q, want %q", mismatch.Reason, reason)
	}
}

func TestLandRawTDXCommitsRowsAndStateAtomically(t *testing.T) {
	db := newRawLandingMock(t)
	db.ExpectBegin()
	db.ExpectExec(regexp.QuoteMeta("SET LOCAL lock_timeout = '20s'")).
		WillReturnResult(pgxmock.NewResult("SET", 0))
	db.ExpectExec(regexp.QuoteMeta(rawDeleteSQL(rawTarget{table: "bus_route", partCol: "city"}))).
		WithArgs("Taipei").
		WillReturnResult(pgxmock.NewResult("DELETE", 3))
	db.ExpectExec(regexp.QuoteMeta(rawInsertSQL("bus_route"))).
		WithArgs(`{"city":"Taipei"}`, []byte("[]")).
		WillReturnResult(pgxmock.NewResult("INSERT", 0))
	db.ExpectExec(stateUpsertPattern).
		WithArgs("bus_route", "city", "Taipei", "MARKER-EMPTY", int64(0), "cycle-test").
		WillReturnResult(pgxmock.NewResult("INSERT", 1))
	db.ExpectCommit()

	err := landRawTDXWithDB(
		context.Background(), db, rawTarget{table: "bus_route", partCol: "city", partVal: "Taipei"}, "MARKER-EMPTY", "cycle-test", bytes.NewBufferString("[]"),
	)
	if err != nil {
		t.Fatalf("landRawTDXWithDB: %v", err)
	}
}

func TestLandRawTDXRollsBackWhenStateUpsertFails(t *testing.T) {
	db := newRawLandingMock(t)
	stateErr := errors.New("state write failed")
	db.ExpectBegin()
	db.ExpectExec(regexp.QuoteMeta("SET LOCAL lock_timeout = '20s'")).
		WillReturnResult(pgxmock.NewResult("SET", 0))
	db.ExpectExec(regexp.QuoteMeta(rawDeleteSQL(rawTarget{table: "bus_route", partCol: "city"}))).
		WithArgs("Taipei").
		WillReturnResult(pgxmock.NewResult("DELETE", 1))
	db.ExpectExec(regexp.QuoteMeta(rawInsertSQL("bus_route"))).
		WithArgs(`{"city":"Taipei"}`, []byte("[]")).
		WillReturnResult(pgxmock.NewResult("INSERT", 0))
	db.ExpectExec(stateUpsertPattern).
		WithArgs("bus_route", "city", "Taipei", "MARKER", int64(0), "cycle-test").
		WillReturnError(stateErr)
	db.ExpectRollback()

	err := landRawTDXWithDB(
		context.Background(), db, rawTarget{table: "bus_route", partCol: "city", partVal: "Taipei"}, "MARKER", "cycle-test", bytes.NewBufferString("[]"),
	)
	if !errors.Is(err, stateErr) {
		t.Fatalf("land error = %v, want %v", err, stateErr)
	}
}

func TestRawLandingPersistsSharedCycleForFullAndVerified304(t *testing.T) {
	t.Run("full verified empty landing", func(t *testing.T) {
		db := newRawLandingMock(t)
		db.ExpectBegin()
		db.ExpectExec(regexp.QuoteMeta("SET LOCAL lock_timeout = '20s'")).
			WillReturnResult(pgxmock.NewResult("SET", 0))
		db.ExpectExec(regexp.QuoteMeta(rawDeleteSQL(rawTarget{table: "bus_route", partCol: "city"}))).
			WithArgs("Taipei").
			WillReturnResult(pgxmock.NewResult("DELETE", 3))
		db.ExpectExec(regexp.QuoteMeta(rawInsertSQL("bus_route"))).
			WithArgs(`{"city":"Taipei"}`, []byte("[]")).
			WillReturnResult(pgxmock.NewResult("INSERT", 0))
		db.ExpectExec(`INSERT INTO raw_tdx\.landing_state .*landing_cycle.*ON CONFLICT.*landing_cycle=EXCLUDED\.landing_cycle`).
			WithArgs("bus_route", "city", "Taipei", "MARKER-EMPTY", int64(0), "cycle-shared").
			WillReturnResult(pgxmock.NewResult("INSERT", 1))
		db.ExpectCommit()

		err := landRawTDXWithDB(
			context.Background(), db, rawTarget{table: "bus_route", partCol: "city", partVal: "Taipei"}, "MARKER-EMPTY", "cycle-shared", bytes.NewBufferString("[]"),
		)
		if err != nil {
			t.Fatalf("landRawTDXWithDB: %v", err)
		}
	})

	t.Run("verified 304", func(t *testing.T) {
		db := newRawLandingMock(t)
		db.ExpectBegin()
		db.ExpectExec(regexp.QuoteMeta("SET LOCAL lock_timeout = '20s'")).
			WillReturnResult(pgxmock.NewResult("SET", 0))
		expectStateRead(db, "MARKER", 0)
		db.ExpectQuery(regexp.QuoteMeta("SELECT EXISTS (SELECT 1 FROM raw_tdx.bus_route WHERE city = $1 LIMIT 1)")).
			WithArgs("Taipei").
			WillReturnRows(pgxmock.NewRows([]string{"exists"}).AddRow(false))
		db.ExpectExec(`UPDATE raw_tdx\.landing_state SET fetched_at=now\(\), landing_cycle=\$4 WHERE table_name=\$1 AND partition_column=\$2 AND partition_value=\$3`).
			WithArgs("bus_route", "city", "Taipei", "cycle-shared").
			WillReturnResult(pgxmock.NewResult("UPDATE", 1))
		db.ExpectCommit()

		if err := verifyAndTouchRawLandingWithDB(
			context.Background(), db, rawTarget{table: "bus_route", partCol: "city", partVal: "Taipei"}, "MARKER", "cycle-shared",
		); err != nil {
			t.Fatalf("verifyAndTouchRawLandingWithDB: %v", err)
		}
	})
}

func TestRawTDXSourceUsesLandingStateForFreshEmptyAndCountIntegrity(t *testing.T) {
	readOptions := pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}
	t.Run("verified empty is fresh", func(t *testing.T) {
		db := newRawLandingMock(t)
		fresh := time.Now().UTC().Truncate(time.Microsecond)
		db.ExpectBeginTx(readOptions)
		db.ExpectQuery(stateFreshnessPattern).
			WithArgs("bus_route", "city", "Taipei").
			WillReturnRows(pgxmock.NewRows([]string{"fetched_at", "row_count"}).AddRow(fresh, int64(0)))
		db.ExpectQuery(`SELECT .* FROM raw_tdx\.bus_route t WHERE city = \$1`).
			WithArgs("Taipei").
			WillReturnRows(pgxmock.NewRows([]string{"row"}))
		db.ExpectCommit()

		body, fetchedAt, err := (rawTDXSource{pool: db}).datasetJSON(
			context.Background(), "bus_route", "city", "Taipei",
		)
		if err != nil {
			t.Fatalf("datasetJSON: %v", err)
		}
		if string(body) != "[]" || !fetchedAt.Equal(fresh) {
			t.Fatalf("body=%s fetchedAt=%s, want []/%s", body, fetchedAt, fresh)
		}
	})

	t.Run("missing state never consumes legacy raw rows", func(t *testing.T) {
		db := newRawLandingMock(t)
		db.ExpectBeginTx(readOptions)
		db.ExpectQuery(stateFreshnessPattern).
			WithArgs("bus_route", "city", "Taipei").
			WillReturnRows(pgxmock.NewRows([]string{"fetched_at", "row_count"}))
		db.ExpectRollback()

		body, fetchedAt, err := (rawTDXSource{pool: db}).datasetJSON(
			context.Background(), "bus_route", "city", "Taipei",
		)
		if err != nil || string(body) != "[]" || !fetchedAt.IsZero() {
			t.Fatalf("body=%s fetchedAt=%s err=%v, want []/zero/nil", body, fetchedAt, err)
		}
	})

	t.Run("exact count mismatch fails closed", func(t *testing.T) {
		db := newRawLandingMock(t)
		db.ExpectBeginTx(readOptions)
		db.ExpectQuery(stateFreshnessPattern).
			WithArgs("bus_route", "city", "Taipei").
			WillReturnRows(pgxmock.NewRows([]string{"fetched_at", "row_count"}).AddRow(time.Now(), int64(2)))
		db.ExpectQuery(`SELECT .* FROM raw_tdx\.bus_route t WHERE city = \$1`).
			WithArgs("Taipei").
			WillReturnRows(pgxmock.NewRows([]string{"row"}).AddRow([]byte(`{"routeuid":"R1"}`)))
		db.ExpectRollback()

		_, _, err := (rawTDXSource{pool: db}).datasetJSON(
			context.Background(), "bus_route", "city", "Taipei",
		)
		assertLandingMismatch(t, err, "loader_row_count")
	})
}

func TestRawTDXSourceReturnsLandingCycleFromSameReadTransaction(t *testing.T) {
	readOptions := pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}
	db := newRawLandingMock(t)
	fresh := time.Now().UTC().Truncate(time.Microsecond)
	db.ExpectBeginTx(readOptions)
	db.ExpectQuery(`SELECT fetched_at, row_count, COALESCE\(landing_cycle, ''\) FROM raw_tdx\.landing_state`).
		WithArgs("bus_route", "city", "Taipei").
		WillReturnRows(pgxmock.NewRows([]string{"fetched_at", "row_count", "landing_cycle"}).AddRow(fresh, int64(0), "cycle-shared"))
	db.ExpectQuery(`SELECT .* FROM raw_tdx\.bus_route t WHERE city = \$1`).
		WithArgs("Taipei").
		WillReturnRows(pgxmock.NewRows([]string{"row"}))
	db.ExpectCommit()

	body, fetchedAt, cycle, err := (rawTDXSource{pool: db}).datasetJSONWithLandingCycle(
		context.Background(), "bus_route", "city", "Taipei",
	)
	if err != nil {
		t.Fatalf("datasetJSONWithLandingCycle: %v", err)
	}
	if string(body) != "[]" || !fetchedAt.Equal(fresh) || cycle != "cycle-shared" {
		t.Fatalf("body/fetched/cycle = %s/%s/%q, want []/%s/cycle-shared", body, fetchedAt, cycle, fresh)
	}
}
