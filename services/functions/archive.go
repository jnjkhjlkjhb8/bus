package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

// The MySQL host owns the observation history outright — it is the primary
// store for bus_eta_history, not a copy of it. Postgres holds the static and
// derived tables (bus_schedule, bus_travel_avg, bus_eta_prediction_error);
// anything that grows by ~200k rows a day lives here instead, off the 2 GB
// Azure server. ARCHIVE_MYSQL_DSN empty disables the path entirely, which is
// how test runs; on prod an unreachable archive means the ETA training loop
// stops collecting, so initArchive refuses to start rather than degrade quietly.
var archiveDB *sql.DB

// archiveRowsPerInsert bounds one multi-row INSERT. MySQL caps a statement at
// 65535 placeholders, so bus_eta_history's 20 columns put the hard ceiling at
// 3276 rows; 1000 stays clear of that and of max_allowed_packet.
const archiveRowsPerInsert = 1000

// archiveExecer is the write seam. *sql.DB satisfies it; tests substitute a
// recorder to assert batching without a live MySQL.
type archiveExecer interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

// crossing is one detected arrival: the moment a stop's estimate fell through
// zero, already interpolated, with the bucket key it belongs to.
type crossing struct {
	subRouteUID string
	direction   int16
	stopUID     string
	hour        int16
	dayOfWeek   int16
	crossingAt  time.Time
}

// historySource is what the daily jobs need from the history host, stated in
// domain rows rather than *sql.Rows. The SQL type is concrete and cannot be
// faked, so a seam shaped like the query would force a driver-level mock into
// every test of computeTravelAvg and fillPredictionActuals; this shape lets them
// take fixtures instead.
type historySource interface {
	crossings(ctx context.Context, window time.Duration) ([]crossing, error)
	arrivals(ctx context.Context, since time.Time) ([]arrivalEvent, error)
}

// mysqlHistory is the production historySource, reading bus_eta_history off the
// MySQL host. recorded_at is stored UTC throughout, so every bound is either an
// explicit UTC instant or UTC_TIMESTAMP() — never NOW(), which follows the
// session time zone.
type mysqlHistory struct{ db *sql.DB }

// crossings scans the last window of history for estimates falling through
// zero. The interpolation Postgres once did inline (make_interval +
// EXTRACT(EPOCH)) happens in Go — see interpolateCrossing — which keeps the
// dialect difference down to the window frame and the interval literal, and
// makes the arithmetic unit-testable.
func (m mysqlHistory) crossings(ctx context.Context, window time.Duration) ([]crossing, error) {
	rows, err := m.db.QueryContext(ctx, `
		WITH ordered AS (
			SELECT sub_route_uid, direction, stop_uid, hour, day_of_week, estimate, recorded_at,
			       LAG(estimate)    OVER w AS prev_est,
			       LAG(recorded_at) OVER w AS prev_at
			FROM bus_eta_history
			WHERE recorded_at >= UTC_TIMESTAMP() - INTERVAL ? SECOND
			WINDOW w AS (PARTITION BY sub_route_uid, direction, stop_uid ORDER BY recorded_at)
		)
		SELECT sub_route_uid, direction, stop_uid, hour, day_of_week,
		       prev_at, recorded_at, prev_est, estimate
		FROM ordered
		WHERE prev_est > 0 AND estimate <= 0
		  AND TIMESTAMPDIFF(SECOND, prev_at, recorded_at) < 300`,
		int64(window.Seconds()))
	if err != nil {
		return nil, fmt.Errorf("query travel crossings: %w", err)
	}
	defer func() { _ = rows.Close() }()
	var out []crossing
	for rows.Next() {
		var c crossing
		var prevAt, at time.Time
		var prevEst, est int
		if err := rows.Scan(&c.subRouteUID, &c.direction, &c.stopUID,
			&c.hour, &c.dayOfWeek, &prevAt, &at, &prevEst, &est); err != nil {
			return nil, fmt.Errorf("scan travel crossing: %w", err)
		}
		c.crossingAt = interpolateCrossing(prevAt, at, prevEst, est)
		out = append(out, c)
	}
	return out, rows.Err()
}

// arrivals returns observed arrivals — history rows whose estimate reached zero
// — since an instant, for matching against open predictions.
func (m mysqlHistory) arrivals(ctx context.Context, since time.Time) ([]arrivalEvent, error) {
	rows, err := m.db.QueryContext(ctx, `
		SELECT sub_route_uid, direction, stop_uid, recorded_at
		FROM bus_eta_history
		WHERE estimate <= 0 AND recorded_at >= ?`, since.UTC())
	if err != nil {
		return nil, fmt.Errorf("query arrivals: %w", err)
	}
	defer func() { _ = rows.Close() }()
	var out []arrivalEvent
	for rows.Next() {
		var a arrivalEvent
		if err := rows.Scan(&a.subRouteUID, &a.direction, &a.stopUID, &a.arrivedAt); err != nil {
			return nil, fmt.Errorf("scan arrival: %w", err)
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// initArchive opens the MySQL history pool. An empty DSN leaves archiveDB nil,
// which every archive call treats as "disabled" rather than an error; a DSN that
// is set but unusable is fatal, since bus_eta_history has no other home and
// silently not recording is the one outcome worth refusing to start over. The
// pool is deliberately small: the writers are the 30s ETA job and two daily
// readers, none of them concurrent with each other.
func initArchive(ctx context.Context, dsn string) error {
	if strings.TrimSpace(dsn) == "" {
		log.Infof("[ARCHIVE] event=disabled reason=empty_dsn")
		return nil
	}
	// Without parseTime the driver hands DATETIME back as []byte and every
	// history read fails at scan time — at 04:00, in a cron, a day after the
	// deploy. Refuse at startup instead.
	if !strings.Contains(dsn, "parseTime=true") {
		return errors.New("archive DSN must set parseTime=true (DATETIME columns are scanned into time.Time)")
	}
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return fmt.Errorf("open archive: %w", err)
	}
	db.SetMaxOpenConns(4)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(time.Hour)
	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := db.PingContext(pingCtx); err != nil {
		return fmt.Errorf("ping archive: %w", errors.Join(err, db.Close()))
	}
	archiveDB = db
	log.Infof("[ARCHIVE] event=ready")
	return nil
}

// archiveTarget and archiveHistory return the write and read seams, or a true nil
// interface when archiving is disabled. Handing callers archiveDB directly would
// give them a non-nil interface wrapping a nil *sql.DB, so every `== nil` guard
// downstream would silently read false.
func archiveTarget() archiveExecer {
	if archiveDB == nil {
		return nil
	}
	return archiveDB
}

func archiveHistory() historySource {
	if archiveDB == nil {
		return nil
	}
	return mysqlHistory{db: archiveDB}
}

// archiveInsertSQL builds the multi-row INSERT IGNORE for n rows of cols.
// table and cols come from package-level constants only, never external input.
func archiveInsertSQL(table string, cols []string, n int) string {
	one := "(" + strings.TrimSuffix(strings.Repeat("?,", len(cols)), ",") + ")"
	return "INSERT IGNORE INTO " + table + " (" + strings.Join(cols, ",") + ") VALUES " +
		strings.TrimSuffix(strings.Repeat(one+",", n), ",")
}

// archiveInsert appends rows to a MySQL history table in bounded batches, every
// timestamp normalized to UTC on the way out (see archiveUTC). IGNORE covers the
// tables that carry a natural unique key — for the append-only observation
// tables, whose id is auto-assigned, it never fires.
func archiveInsert(ctx context.Context, db archiveExecer, table string, cols []string, rows [][]any) error {
	if db == nil || len(rows) == 0 {
		return nil
	}
	for start := 0; start < len(rows); start += archiveRowsPerInsert {
		end := min(start+archiveRowsPerInsert, len(rows))
		batch := rows[start:end]
		args := make([]any, 0, len(batch)*len(cols))
		for _, r := range batch {
			if len(r) != len(cols) {
				return fmt.Errorf("archive %s: row has %d values, want %d", table, len(r), len(cols))
			}
			args = append(args, archiveUTC(r)...)
		}
		if _, err := db.ExecContext(ctx, archiveInsertSQL(table, cols, len(batch)), args...); err != nil {
			return fmt.Errorf("archive %s rows %d..%d: %w", table, start, end, err)
		}
	}
	return nil
}

// archiveUTC normalizes every timestamp in a row to UTC. MySQL DATETIME carries
// no zone, so the conversion happens before the value leaves Go rather than
// being left to whatever `loc` the DSN happens to set.
func archiveUTC(vals []any) []any {
	for i, v := range vals {
		if t, ok := v.(time.Time); ok {
			vals[i] = t.UTC()
		}
	}
	return vals
}
