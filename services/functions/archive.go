package main

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	_ "github.com/go-sql-driver/mysql"
	"go.uber.org/zap"
)

// The MySQL host owns the observation history outright — it is the primary
// store for bus_eta_history, not a copy of it. Postgres holds the static and
// derived tables (bus_schedule, bus_segment_time, bus_eta_prediction_error);
// anything that grows by ~200k rows a day lives here instead, off the 2 GB
// Azure server. ARCHIVE_MYSQL_DSN empty disables the path entirely, which is
// how test runs; on prod an unreachable archive means the ETA training loop
// stops collecting, so initArchive refuses to start rather than degrade quietly.
//
// archiver holds the single process-wide MySQL pool. initArchive constructs
// one; main.go stores the result here once at startup. Tests never reassign
// this var — they exercise the pure helpers and the archiveExecer/historySource
// seams directly instead.
type archiver struct {
	db *sql.DB
}

var _archive *archiver

// _archiveRowsPerInsert bounds one multi-row INSERT. MySQL caps a statement at
// 65535 placeholders, so bus_eta_history's 20 columns put the hard ceiling at
// 3276 rows; 1000 stays clear of that and of max_allowed_packet.
const _archiveRowsPerInsert = 1000

// archiveExecer is the write seam. *sql.DB satisfies it; tests substitute a
// recorder to assert batching without a live MySQL.
type archiveExecer interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

// segmentObs is one hop's running time, already reduced to a median over the
// observations behind it. It is the whole result of a segment rebuild: the
// aggregation happens on the history host, and only these rows cross the wire.
//
// bus_segment_time lives on PostgreSQL while the observations live on MySQL, so
// a rebuild can no longer be the single INSERT ... SELECT it once was. Splitting
// it at the aggregate rather than at the raw row is what keeps the transfer
// small — one row per (sub_route_uid, direction, from_stop_uid, to_stop_uid)
// instead of the millions of history rows they were derived from.
type segmentObs struct {
	subRouteUID string
	direction   int16
	fromStopUID string
	toStopUID   string
	secs        int
	sampleCount int
}

// historySource is what the daily jobs need from the history host, stated in
// domain rows rather than *sql.Rows. The SQL type is concrete and cannot be
// faked, so a seam shaped like the query would force a driver-level mock into
// every test of fillPredictionActuals; this shape lets it take fixtures
// instead.
type historySource interface {
	arrivals(ctx context.Context, since time.Time) ([]arrivalEvent, error)
	segmentsByEstimate(ctx context.Context, window time.Duration) ([]segmentObs, error)
}

// mysqlHistory is the production historySource, reading bus_eta_history off the
// MySQL host. recorded_at is stored UTC throughout, so every bound is either an
// explicit UTC instant or UTC_TIMESTAMP() — never NOW(), which follows the
// session time zone.
type mysqlHistory struct{ db *sql.DB }

// _segmentMedianTail reduces a `kept` CTE of (key..., secs) observations to one
// median row per key, and is the tail of the segment query.
//
// MySQL has no percentile_cont, so the middle one or two values are picked by
// rank and averaged — for an odd count that is the middle value, for an even one
// the mean of the two straddling the middle, which is exactly what
// percentile_cont(0.5) returned while these rebuilds ran on PostgreSQL. Keeping
// the definition identical is what makes the figures before and after the move
// comparable; a different median would look like the buses got faster.
//
// The two windows differ deliberately. n is counted over a partition with no
// ORDER BY, because a counting window that carries one produces a running total
// rather than the group size — sample_count would then be wrong on every row
// while still looking like a plausible number.
const _segmentMedianTail = `
	), ranked AS (
		SELECT sub_route_uid, direction, from_stop_uid, to_stop_uid, secs,
		       ROW_NUMBER() OVER gs AS rn,
		       COUNT(*)     OVER g  AS n
		FROM kept
		WINDOW g  AS (PARTITION BY sub_route_uid, direction, from_stop_uid, to_stop_uid),
		       gs AS (g ORDER BY secs)
	)
	SELECT sub_route_uid, direction, from_stop_uid, to_stop_uid,
	       CAST(ROUND(AVG(secs)) AS SIGNED), MAX(n)
	FROM ranked
	WHERE rn IN (FLOOR((n + 1) / 2), CEILING((n + 1) / 2))
	GROUP BY sub_route_uid, direction, from_stop_uid, to_stop_uid`

// segmentsByEstimate differences adjacent stops' estimates within one snapshot,
// returning one median running time per hop.
//
// At a single instant TDX gives the seconds-to-arrival for every stop the
// approaching bus still has ahead of it, so the difference between two adjacent
// stops' estimates is that bus's running time between them — one row, no pairing,
// no vehicle identity. That is why this pass reaches the operators that publish
// no plate at all.
//
// A pair is kept only when the later stop's estimate is the larger one. A bus
// approaching a stop is always further from the stop after it, so a non-positive
// difference means the two estimates describe different vehicles — most often a
// following bus reported at the later stop — and differencing them would be
// meaningless.
func (m mysqlHistory) segmentsByEstimate(ctx context.Context, window time.Duration) ([]segmentObs, error) {
	rows, err := m.db.QueryContext(ctx, `
		WITH kept AS (
			SELECT sub_route_uid, direction, stop_uid AS from_stop_uid,
			       next_stop_uid AS to_stop_uid, next_estimate - estimate AS secs
			FROM (
				-- One snapshot of one subroute, read along the stop sequence. The
				-- partition is the instant itself: every row in it was written by
				-- the same pass over the same TDX response.
				SELECT sub_route_uid, direction, stop_uid, stop_sequence, estimate,
				       LEAD(stop_uid)      OVER w AS next_stop_uid,
				       LEAD(stop_sequence) OVER w AS next_stop_sequence,
				       LEAD(estimate)      OVER w AS next_estimate
				FROM bus_eta_history
				WHERE recorded_at >= UTC_TIMESTAMP() - INTERVAL ? SECOND
				WINDOW w AS (PARTITION BY sub_route_uid, direction, recorded_at
				             ORDER BY stop_sequence)
			) ordered
			WHERE next_stop_uid IS NOT NULL
			  -- Adjacent stops only, matching segmentsByPlate: a gap would record
			  -- several hops' running time as one.
			  AND next_stop_sequence = stop_sequence + 1
			  AND next_estimate - estimate BETWEEN ? AND ?`+_segmentMedianTail,
		int64(window.Seconds()), _segmentDiffMinSecs, _segmentDiffMaxSecs)
	if err != nil {
		return nil, _oops.Wrapf(err, "query estimate segments")
	}
	return scanSegmentObs(rows)
}

func scanSegmentObs(rows *sql.Rows) ([]segmentObs, error) {
	defer func() { _ = rows.Close() }()
	var out []segmentObs
	for rows.Next() {
		var s segmentObs
		if err := rows.Scan(&s.subRouteUID, &s.direction, &s.fromStopUID,
			&s.toStopUID, &s.secs, &s.sampleCount); err != nil {
			return nil, _oops.Wrapf(err, "scan segment observation")
		}
		out = append(out, s)
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
		return nil, _oops.Wrapf(err, "query arrivals")
	}
	defer func() { _ = rows.Close() }()
	var out []arrivalEvent
	for rows.Next() {
		var a arrivalEvent
		if err := rows.Scan(&a.subRouteUID, &a.direction, &a.stopUID, &a.arrivedAt); err != nil {
			return nil, _oops.Wrapf(err, "scan arrival")
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// initArchive opens the MySQL history pool. An empty DSN reports the path
// disabled by returning a nil *archiver, which every archive call treats as
// "disabled" rather than an error; a DSN that is set but unusable is fatal,
// since bus_eta_history has no other home and silently not recording is the
// one outcome worth refusing to start over. The pool is deliberately small:
// the writers are the 30s ETA job and two daily readers, none of them
// concurrent with each other.
func initArchive(ctx context.Context, dsn string) (*archiver, error) {
	if strings.TrimSpace(dsn) == "" {
		zap.S().Infow("disabled", "component", "archive", "event", "disabled", "reason", "empty_dsn")
		return nil, nil
	}
	// Without parseTime the driver hands DATETIME back as []byte and every
	// history read fails at scan time — at 04:00, in a cron, a day after the
	// deploy. Refuse at startup instead.
	if !strings.Contains(dsn, "parseTime=true") {
		return nil, errors.New("archive DSN must set parseTime=true (DATETIME columns are scanned into time.Time)")
	}
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, _oops.Wrapf(err, "open archive")
	}
	db.SetMaxOpenConns(4)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(time.Hour)
	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := db.PingContext(pingCtx); err != nil {
		return nil, _oops.Wrapf(errors.Join(err, db.Close()), "ping archive")
	}
	zap.S().Infow("ready", "component", "archive", "event", "ready")
	return &archiver{db: db}, nil
}

// Close closes the pool, or is a no-op on a disabled (nil) archiver.
func (a *archiver) Close() error {
	if a == nil {
		return nil
	}
	return a.db.Close()
}

// target and history return the write and read seams, or a true nil interface
// when archiving is disabled. Handing callers a.db directly would give them a
// non-nil interface wrapping a nil *sql.DB, so every `== nil` guard downstream
// would silently read false — these stay nil-safe on a nil *archiver receiver
// instead.
func (a *archiver) target() archiveExecer {
	if a == nil {
		return nil
	}
	return a.db
}

func (a *archiver) history() historySource {
	if a == nil {
		return nil
	}
	return mysqlHistory{db: a.db}
}

// archiveTarget and archiveHistory expose the process-wide archiver to this
// package's free-function call sites (cron jobs registered in main.go).
func archiveTarget() archiveExecer {
	return _archive.target()
}

func archiveHistory() historySource {
	return _archive.history()
}

// resolveHistory returns where observations are read from, or nil when there is
// nowhere to read them.
//
// There is only one source now. This used to choose between MySQL and a
// PostgreSQL fallback while the history was mid-move; the drop migration
// (2026-07-30-drop-bus-eta-history.sql) removed the PostgreSQL table, so the
// fallback could only ever report the table missing and was deleted with it.
//
// nil means the rows are genuinely nowhere rather than merely not where the
// reader looked, and callers log a skip instead of writing a figure built from
// no observations.
func resolveHistory() historySource {
	h := archiveHistory()
	if h == nil {
		zap.S().Warnw("log",
			"component", "history",
			"action", "resolve",
			"source", "none",
			"reason", "archive_disabled",
		)
		return nil
	}
	zap.S().Infow("log", "component", "history", "action", "resolve", "source", "mysql")
	return h
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
	for start := 0; start < len(rows); start += _archiveRowsPerInsert {
		end := min(start+_archiveRowsPerInsert, len(rows))
		batch := rows[start:end]
		args := make([]any, 0, len(batch)*len(cols))
		for _, r := range batch {
			if len(r) != len(cols) {
				return _oops.With("table", table).With("values", len(r)).With("cols", len(cols)).Errorf("row width does not match column count")
			}
			args = append(args, archiveUTC(r)...)
		}
		if _, err := db.ExecContext(ctx, archiveInsertSQL(table, cols, len(batch)), args...); err != nil {
			return _oops.With("table", table).With("start", start).With("end", end).Wrapf(err, "archive rows ..")
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
