package history

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"go.uber.org/zap"
)

// Partition maintenance for the archive host: create the coming months, drop the
// expired ones.
//
// Both halves matter and only one is obvious. Dropping is the retention policy
// (ADR-0023) — DROP PARTITION rather than DELETE, because a nightly DELETE of a
// day of bus payloads writes an equal volume of undo log and returns no space to
// the OS. Creating is the part nobody scheduled: partition lists in this repo
// have been written by hand and left to expire, and
// migrations/mysql/2026-08-02-history-partitions.sql says so in as many words —
// bus_eta_history's list ends on 2027-08-01, after which every row lands in
// p_max, pruning quietly stops working, and nothing fails.

// _archivePartitionTables is every partitioned table on the archive host and how
// long its rows are kept. A zero retention means indefinite: the table still gets
// its future partitions created, it just never loses one.
//
// The retention class is the table rather than a column because DROP PARTITION
// takes every dataset in the partition with it — a partition cannot be dropped
// for the bus streams and kept for the metro ones, which is why live_archive and
// live_archive_bus are two tables.
var _archivePartitionTables = []struct {
	table     string
	retention time.Duration
}{
	{table: "live_archive_bus", retention: 90 * 24 * time.Hour},
	{table: "live_archive"},
	{table: "bus_eta_history"},
	{table: "bike_availability_history"},
}

// _archiveMonthsAhead is how far ahead partitions are created. Three months of
// headroom means the job can fail every night for a season before rows start
// piling into p_max, which is the failure this is here to prevent in the first
// place.
const _archiveMonthsAhead = 3

// archivePartition is one RANGE partition: its name and its exclusive upper
// bound, expressed as the month it stops at.
type archivePartition struct {
	name  string
	upper time.Time
}

// archiveAdmin is what partition maintenance needs from the archive host. It is
// stated in domain rows rather than *sql.Rows so tests can supply fixtures
// instead of a driver-level mock, the same shape Source takes.
type archiveAdmin interface {
	Execer
	partitions(ctx context.Context, table string) ([]archivePartition, error)
}

// mysqlArchiveAdmin is the production archiveAdmin.
type mysqlArchiveAdmin struct{ db *sql.DB }

func (a *archiver) admin() archiveAdmin {
	if a == nil {
		return nil
	}
	return mysqlArchiveAdmin{db: a.db}
}

// AdminTarget exposes the process-wide archiver's admin view to the cron
// registered in main.go.
func AdminTarget() archiveAdmin {
	return _archive.admin()
}

func (m mysqlArchiveAdmin) ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error) {
	return m.db.ExecContext(ctx, query, args...)
}

// partitions reads the table's RANGE partitions in bound order.
//
// partition_description holds the TO_DAYS(...) expression's value as text, and
// MAXVALUE for the catch-all. The day number is converted back to a date rather
// than parsed out of the partition name: the name is a label this job chose and
// could drift, while the bound is what MySQL actually routes rows by.
func (m mysqlArchiveAdmin) partitions(ctx context.Context, table string) ([]archivePartition, error) {
	rows, err := m.db.QueryContext(ctx, `
		SELECT partition_name, partition_description
		  FROM information_schema.partitions
		 WHERE table_schema = DATABASE() AND table_name = ? AND partition_name IS NOT NULL
		 ORDER BY partition_ordinal_position`, table)
	if err != nil {
		return nil, _oops.With("table", table).Wrapf(err, "read partitions")
	}
	defer func() { _ = rows.Close() }()
	var out []archivePartition
	for rows.Next() {
		var name, desc string
		if err := rows.Scan(&name, &desc); err != nil {
			return nil, _oops.With("table", table).Wrapf(err, "scan partition")
		}
		if strings.EqualFold(strings.TrimSpace(desc), "MAXVALUE") {
			continue
		}
		days, err := strconv.Atoi(strings.TrimSpace(desc))
		if err != nil {
			return nil, _oops.With("table", table).With("partition", name).Wrapf(err, "parse partition bound")
		}
		out = append(out, archivePartition{name: name, upper: fromMySQLDays(days)})
	}
	if err := rows.Err(); err != nil {
		return nil, _oops.With("table", table).Wrapf(err, "iterate partitions")
	}
	return out, nil
}

// _mysqlDaysAtUnixEpoch is TO_DAYS('1970-01-01'), the bridge between MySQL's day
// count and Go's clock.
//
// The conversion is anchored at the Unix epoch rather than at TO_DAYS' own year
// zero because time.Duration is an int64 of nanoseconds and saturates at about
// 292 years: subtracting a year-0 origin silently returns a clamped value, which
// turns every partition bound into the same wrong date and makes the retention
// cutoff meaningless. Unix seconds have no such ceiling.
const (
	_mysqlDaysAtUnixEpoch = 719528
	_secondsPerDay        = 86400
)

func fromMySQLDays(days int) time.Time {
	return time.Unix(int64(days-_mysqlDaysAtUnixEpoch)*_secondsPerDay, 0).UTC()
}

func toMySQLDays(t time.Time) int {
	return int(t.UTC().Unix()/_secondsPerDay) + _mysqlDaysAtUnixEpoch
}

// MaintainPartitions brings every managed table's partitions in line with
// now: the coming months created, the expired ones dropped.
//
// A nil target (ARCHIVE_MYSQL_DSN empty, which is every environment but prod) is
// a no-op rather than an error. Per-table failures are collected and the run
// continues, because one table's partition list being unreadable is no reason to
// leave the others unmaintained.
func MaintainPartitions(ctx context.Context, db archiveAdmin, now time.Time) error {
	if db == nil {
		return nil
	}
	var errs []error
	for _, spec := range _archivePartitionTables {
		existing, err := db.partitions(ctx, spec.table)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		if err := addArchivePartitions(ctx, db, spec.table, existing, now); err != nil {
			errs = append(errs, err)
			continue
		}
		if spec.retention == 0 {
			continue
		}
		if err := dropArchivePartitions(ctx, db, spec.table, existing, now.Add(-spec.retention)); err != nil {
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

// addArchivePartitions reorganizes p_max into the months missing between the
// last declared bound and monthsAhead from now.
//
// REORGANIZE rewrites only the partitions it names, and p_max is empty whenever
// this job has been keeping up, so the usual run is a catalog change that returns
// immediately. It is expensive exactly once: the first run after the job has been
// failing long enough for rows to reach p_max.
func addArchivePartitions(ctx context.Context, db Execer, table string, existing []archivePartition, now time.Time) error {
	// Bounds, not months: a partition bounded by the first of month N holds
	// month N-1. Holding the next _archiveMonthsAhead months therefore means
	// declaring bounds up to _archiveMonthsAhead+1 months out.
	limit := monthStart(now).AddDate(0, _archiveMonthsAhead+1, 0)
	next := monthStart(now).AddDate(0, 1, 0)
	if last, ok := lastBound(existing); ok && !last.Before(next) {
		// REORGANIZE requires the new bounds to rise past every declared one, so
		// continue from the month after the last, never from it.
		next = last.AddDate(0, 1, 0)
	}
	var defs []string
	for b := next; !b.After(limit); b = b.AddDate(0, 1, 0) {
		defs = append(defs, fmt.Sprintf("PARTITION %s VALUES LESS THAN (%d)", partitionName(b), toMySQLDays(b)))
	}
	if len(defs) == 0 {
		return nil
	}
	defs = append(defs, "PARTITION p_max VALUES LESS THAN MAXVALUE")
	stmt := fmt.Sprintf("ALTER TABLE %s REORGANIZE PARTITION p_max INTO (%s)", table, strings.Join(defs, ", "))
	if _, err := db.ExecContext(ctx, stmt); err != nil {
		return _oops.With("table", table).With("partitions", len(defs)-1).Wrapf(err, "add partitions")
	}
	zap.S().Infow("added partitions",
		"component", "archive_partitions", "action", "add", "table", table, "partitions", len(defs)-1)
	return nil
}

// dropArchivePartitions drops every partition that ends at or before cutoff, so
// only whole expired months are removed. A partition still holding rows newer
// than cutoff is left alone — the month is the granularity, and over-keeping is
// the safe direction.
func dropArchivePartitions(ctx context.Context, db Execer, table string, existing []archivePartition, cutoff time.Time) error {
	var names []string
	for _, p := range existing {
		if !p.upper.After(cutoff) {
			names = append(names, p.name)
		}
	}
	if len(names) == 0 {
		return nil
	}
	sort.Strings(names)
	stmt := fmt.Sprintf("ALTER TABLE %s DROP PARTITION %s", table, strings.Join(names, ", "))
	if _, err := db.ExecContext(ctx, stmt); err != nil {
		return _oops.With("table", table).With("partitions", len(names)).Wrapf(err, "drop partitions")
	}
	zap.S().Infow("dropped partitions",
		"component", "archive_partitions", "action", "drop",
		"table", table, "partitions", strings.Join(names, ","), "cutoff", cutoff.UTC().Format(time.DateOnly))
	return nil
}

// lastBound returns the newest declared upper bound, which is where new months
// have to continue from: REORGANIZE requires the new partitions' bounds to rise
// past everything already declared.
func lastBound(existing []archivePartition) (time.Time, bool) {
	var last time.Time
	for _, p := range existing {
		if p.upper.After(last) {
			last = p.upper
		}
	}
	return last, !last.IsZero()
}

// partitionName labels a partition by the month it holds, not the month it stops
// at: a partition bounded by 2026-10-01 holds September, and is named p2026_09.
// This matches the names in migrations/mysql/2026-08-02-history-partitions.sql.
func partitionName(upper time.Time) string {
	held := upper.AddDate(0, -1, 0)
	return fmt.Sprintf("p%04d_%02d", held.Year(), int(held.Month()))
}

func monthStart(t time.Time) time.Time {
	u := t.UTC()
	return time.Date(u.Year(), u.Month(), 1, 0, 0, 0, 0, time.UTC)
}
