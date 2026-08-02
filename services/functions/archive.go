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
// derived tables (bus_schedule, bus_segment_time, bus_eta_prediction_error);
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
	segmentsByPlate(ctx context.Context, window time.Duration) ([]segmentObs, error)
	segmentsByEstimate(ctx context.Context, window time.Duration) ([]segmentObs, error)
}

// mysqlHistory is the production historySource, reading bus_eta_history off the
// MySQL host. recorded_at is stored UTC throughout, so every bound is either an
// explicit UTC instant or UTC_TIMESTAMP() — never NOW(), which follows the
// session time zone.
type mysqlHistory struct{ db *sql.DB }

// segmentMedianTail reduces a `kept` CTE of (key..., secs) observations to one
// median row per key, and is the tail of both segment queries.
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
const segmentMedianTail = `
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

// segmentsByPlate reconstructs each vehicle's run from plate_numb and differences
// consecutive arrivals, returning one median running time per hop.
//
// A history row is only written while a bus is en route, so the arrival itself is
// never recorded: TDX flips StopStatus on arrival and the writer stops. The end
// of an approach therefore has to stand in for it — the last estimate a plate
// reported at a stop before going quiet, placed at the moment that estimate was
// pointing to.
//
// plate_numb is what makes this sound: it separates buses converging on one stop,
// so a run is one vehicle's approach rather than several interleaved. Where the
// operator publishes no plate, this pass finds nothing and segmentsByEstimate
// covers the hop instead.
func (m mysqlHistory) segmentsByPlate(ctx context.Context, window time.Duration) ([]segmentObs, error) {
	rows, err := m.db.QueryContext(ctx, `
		WITH ordered AS (
			SELECT sub_route_uid, direction, stop_uid, stop_sequence, estimate,
			       recorded_at, plate_numb,
			       LEAD(recorded_at) OVER p AS next_plate_at
			FROM bus_eta_history
			WHERE recorded_at >= UTC_TIMESTAMP() - INTERVAL ? SECOND
			  AND plate_numb IS NOT NULL
			WINDOW p AS (PARTITION BY sub_route_uid, direction, stop_uid, plate_numb
			             ORDER BY recorded_at)
		), arrival AS (
			-- The end of one vehicle's approach to one stop, placed at the moment
			-- its last estimate was pointing to.
			SELECT sub_route_uid, direction, plate_numb, stop_uid, stop_sequence,
			       recorded_at + INTERVAL estimate SECOND AS arrived_at
			FROM ordered
			WHERE estimate BETWEEN 1 AND ?
			  AND (next_plate_at IS NULL
			       OR TIMESTAMPDIFF(SECOND, recorded_at, next_plate_at) > ?)
		), kept AS (
			SELECT sub_route_uid, direction, from_stop_uid, to_stop_uid, secs
			FROM (
				SELECT sub_route_uid, direction,
				       LAG(stop_uid) OVER w AS from_stop_uid,
				       stop_uid AS to_stop_uid,
				       stop_sequence - LAG(stop_sequence) OVER w AS seq_gap,
				       TIMESTAMPDIFF(SECOND, LAG(arrived_at) OVER w, arrived_at) AS secs
				FROM arrival
				WINDOW w AS (PARTITION BY sub_route_uid, direction, plate_numb
				             ORDER BY stop_sequence, arrived_at)
			) segment
			WHERE from_stop_uid IS NOT NULL
			  -- Adjacent stops only. A gap means the vehicle was not seen at the
			  -- stops between, and spanning them would record one hop's time for
			  -- several.
			  AND seq_gap = 1
			  AND secs BETWEEN ? AND ?`+segmentMedianTail,
		int64(window.Seconds()), segmentApproachSecs, segmentGapSecs,
		segmentMinSecs, segmentMaxSecs)
	if err != nil {
		return nil, fmt.Errorf("query plate segments: %w", err)
	}
	return scanSegmentObs(rows)
}

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
			  AND next_estimate - estimate BETWEEN ? AND ?`+segmentMedianTail,
		int64(window.Seconds()), segmentDiffMinSecs, segmentDiffMaxSecs)
	if err != nil {
		return nil, fmt.Errorf("query estimate segments: %w", err)
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
			return nil, fmt.Errorf("scan segment observation: %w", err)
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
		log.Warnf("[HISTORY] action=resolve source=none reason=archive_disabled")
		return nil
	}
	log.Infof("[HISTORY] action=resolve source=mysql")
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
