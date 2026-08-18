package main

import (
	"archive/zip"
	"context"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// The GTFS static feed builder.
//
// It runs inside the loader process, immediately after the vector refresh, for
// the same reason changetovector does (ADR-0013): the whole load -> derive chain
// stays in one container. A fourth container on a 6 GB host would buy nothing —
// this is a few minutes of streaming COPY once a day.
//
// The zip is streamed: each file's rows go straight from a COPY on the server
// into the zip writer, so no file is ever materialised in memory. stops.txt
// alone is a few hundred thousand rows and would otherwise be the largest
// allocation this process makes.

const (
	// _gtfsExportTimeout bounds one build.
	//
	// 15 minutes was not enough and the export had been failing on it: measured
	// against prod on 2026-08-06, stop_times.txt alone streams for ten of them
	// and shapes.txt for two more. The budget is the whole nightly window, not a
	// request, so this is set well clear of the ~20 minutes a build takes rather
	// than close to it — a slow night must not cost the feed.
	_gtfsExportTimeout = 45 * time.Minute
	// _gtfsOutputDirEnv overrides where feeds are written. The default is a path
	// a volume can be mounted at, since the consumer of these files is another
	// container.
	_gtfsOutputDirEnv     = "GTFS_OUT_DIR"
	_gtfsDefaultOutputDir = "/data/gtfs"
	// _gtfsLatestName is the stable path a planner is pointed at. It is a symlink
	// so that publishing a new feed is one atomic rename rather than a copy.
	_gtfsLatestName = "gtfs.zip"
	// _gtfsKeepFeeds is how many dated builds survive a prune. Enough to roll back
	// to a known-good feed after a bad one ships, not enough to fill the disk.
	_gtfsKeepFeeds = 3
)

// gtfsFile is one entry in the archive. sql must be a complete SELECT; the
// COPY wrapper and CSV framing are added here so no statement can forget them.
type gtfsFile struct {
	name string
	sql  string
}

// gtfsTempTable is a derived set materialized once and read by name afterwards.
//
// Two separate problems make this necessary, both measured against the Azure
// B1ms on 2026-08-06.
//
// The planner has no statistics for a lateral expansion of JSONB, so it costs
// one at a hundred rows whatever it really returns. Fed a fare source it thinks
// is small, it chose a plan that had not finished counting the 1.75M bus fare
// legs after 15 minutes — while the same legs, joined out of two analyzed temp
// tables, count in 26 seconds. The materialize is not a cache here, it is what
// gives the planner the row counts it is choosing on.
//
// And the fare files re-derive the same sets: gtfsFarePricedSQL is read by all
// four of them, the section zones by all four, and the emitted stop set by those
// plus stops.txt and pathways.txt. Inline, each of those is a fresh execution.
//
// indexOn is a column list to build an index over before ANALYZE, for the sets
// something joins to per-row rather than scans.
type gtfsTempTable struct {
	name    string
	sql     string
	indexOn string
}

// gtfsTempTables lists the materialized sets in dependency order: each may read
// the ones before it.
func gtfsTempTables() []gtfsTempTable {
	return []gtfsTempTable{
		// The calls come first because both of the sets after them are defined by
		// what is in here: trips.txt is restricted to the trips that have calls
		// (gtfsStopTimesSQL drops the ones whose times it cannot state), and
		// stops.txt to the stops those calls name.
		{name: _gtfsStopTimeTable, sql: _gtfsStopTimesSQL, indexOn: "trip_id"},
		// stop_areas.txt looks a stop up per fare area, so this one is indexed
		// even though every other reader of it scans.
		{name: _gtfsStopTable, sql: _gtfsStopsSQL, indexOn: "stop_id"},
		// Rail geometry: the clipped segments first, then the trip-to-shape
		// mapping shapes.txt and trips.txt both read. Both are joined to per stop
		// pair and per trip rather than scanned, hence the indexes.
		{name: _gtfsRailSegTable, sql: gtfsRailSegSQL, indexOn: "from_stop, to_stop"},
		{name: _gtfsRailTripShapeTable, sql: gtfsRailTripShapeSQL, indexOn: "trip_id"},
		{name: _gtfsFareSrcTable, sql: _busFareSourceSQL, indexOn: "city, routeid"},
		{name: _gtfsStopUIDTable, sql: _busStopUIDSQL, indexOn: "city, stop_id"},
		{name: _gtfsStopSeqTable, sql: _busStopSeqSQL, indexOn: "subrouteuid, direction, stop_id"},
		{name: _gtfsFarePairTable, sql: _busFarePairSQL, indexOn: "routeuid, from_uid, to_uid"},
		{name: _gtfsFareLegTable, sql: _busFareLegSQL},
		{name: _gtfsFarePricedTable, sql: _gtfsFarePricedSQL},
		{name: _gtfsFareZoneTable, sql: _gtfsFareZoneSQL},
	}
}

// gtfsFiles is the feed's contents.
//
// The file set is complete for bus, metro and rail. What is missing is service,
// not structure: Taipei, New Taipei, Tainan and Taoyuan have routes and stops
// but no trips, because building their stop times needs observed segment
// running times the ETA history does not yet cover (FDPL-23, FDPL-26).
func gtfsFiles(version string) []gtfsFile {
	return []gtfsFile{
		{"agency.txt", _gtfsAgencySQL},
		// stops.txt is the materialized set itself, not a second evaluation of
		// the query behind it: the fare files filter against these exact ids.
		{"stops.txt", "SELECT * FROM " + _gtfsStopTable},
		{"routes.txt", _gtfsRoutesSQL},
		{"calendar_dates.txt", _gtfsCalendarDatesSQL},
		{"trips.txt", _gtfsTripsSQL},
		{"stop_times.txt", "SELECT * FROM " + _gtfsStopTimeTable},
		{"frequencies.txt", _gtfsFrequenciesSQL},
		{"transfers.txt", _gtfsTransfersSQL},
		{"pathways.txt", _gtfsPathwaysSQL},
		{"shapes.txt", _gtfsShapesSQL},
		{"areas.txt", _gtfsAreasSQL},
		{"stop_areas.txt", _gtfsStopAreasSQL},
		{"fare_products.txt", _gtfsFareProductsSQL},
		{"fare_leg_rules.txt", _gtfsFareLegRulesSQL},
		{"translations.txt", _gtfsTranslationsSQL},
		{"feed_info.txt", gtfsFeedInfoSQL(version)},
		{"attributions.txt", _gtfsAttributionsSQL},
	}
}

func gtfsOutputDir() string {
	if dir := strings.TrimSpace(os.Getenv(_gtfsOutputDirEnv)); dir != "" {
		return dir
	}
	return _gtfsDefaultOutputDir
}

// runGTFSExport builds one feed and publishes it, logging rather than returning
// an error: it is the last stage of the nightly chain and nothing downstream in
// this process depends on it, so a failed export must not fail the load that
// already succeeded.
func runGTFSExport(db *pgxpool.Pool, runDate time.Time) {
	ctx, cancel := context.WithTimeout(context.Background(), _gtfsExportTimeout)
	defer cancel()
	started := time.Now()
	path, rows, err := buildGTFSFeed(ctx, db, gtfsOutputDir(), runDate)
	if err != nil {
		zap.S().Errorw("failed", "component", "gtfs", "action", "export", "event", "failed", "err", err)
		return
	}
	zap.S().Infow("success",
		"component", "gtfs",
		"action", "export",
		"event", "success",
		"path", path,
		"rows", rows,
		"elapsed", time.Since(started).Round(time.Millisecond),
	)
}

// buildGTFSFeed writes a dated feed, points the stable name at it, and prunes
// older builds. It returns the dated path and the total row count.
//
// The archive is written to a temporary name and renamed into place, so a
// consumer polling the directory never observes a half-written zip.
func buildGTFSFeed(ctx context.Context, db *pgxpool.Pool, dir string, runDate time.Time) (string, int64, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", 0, _oops.With("dir", dir).Wrapf(err, "gtfs export: create")
	}
	version := runDate.Format("20060102-1504")
	final := filepath.Join(dir, "gtfs-"+version+".zip")

	temp, err := os.CreateTemp(dir, ".gtfs-*.zip.tmp")
	if err != nil {
		return "", 0, _oops.Wrapf(err, "gtfs export: create temp")
	}
	tempName := temp.Name()
	// Removing the temp file is a no-op once it has been renamed away.
	defer func() {
		_ = temp.Close()
		_ = os.Remove(tempName)
	}()

	rows, err := writeGTFSArchive(ctx, db, temp, version)
	if err != nil {
		return "", 0, err
	}
	// fsync before the rename: a crash between the two would otherwise publish a
	// name that points at unflushed content.
	if err := temp.Sync(); err != nil {
		return "", 0, _oops.Wrapf(err, "gtfs export: sync")
	}
	if err := temp.Close(); err != nil {
		return "", 0, _oops.Wrapf(err, "gtfs export: close")
	}
	if err := os.Chmod(tempName, 0o644); err != nil {
		return "", 0, _oops.With("temp", tempName).Wrapf(err, "gtfs export: chmod")
	}
	if err := os.Rename(tempName, final); err != nil {
		return "", 0, _oops.With("final", final).Wrapf(err, "gtfs export: publish")
	}
	if err := linkLatestGTFS(dir, filepath.Base(final)); err != nil {
		return "", 0, err
	}
	if err := pruneGTFSFeeds(dir, _gtfsKeepFeeds); err != nil {
		// A failed prune leaves extra files behind; the feed itself is published
		// and usable, so this is reported without failing the build.
		zap.S().Warnw("failed", "component", "gtfs", "action", "prune", "event", "failed", "err", err)
	}
	return final, rows, nil
}

// writeGTFSArchive streams every file into one zip.
//
// One connection serves the whole archive so all files observe the same
// snapshot within a transaction — without it a load committing mid-build could
// produce a routes.txt referencing an agency that stops.txt never saw.
func writeGTFSArchive(ctx context.Context, db *pgxpool.Pool, w io.Writer, version string) (int64, error) {
	conn, err := db.Acquire(ctx)
	if err != nil {
		return 0, _oops.Wrapf(err, "gtfs export: acquire connection")
	}
	defer conn.Release()

	tx, err := conn.Begin(ctx)
	if err != nil {
		return 0, _oops.Wrapf(err, "gtfs export: begin")
	}
	defer func() { _ = tx.Rollback(ctx) }()
	// REPEATABLE READ is what makes the files agree with each other. READ ONLY
	// used to be asserted beside it and cannot be: PostgreSQL refuses CREATE
	// TABLE AS in a read-only transaction, and the export now materializes its
	// shared sets into temp tables. Nothing here writes anything else — every
	// file is a COPY of a SELECT.
	if _, err := tx.Exec(ctx, "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ"); err != nil {
		return 0, _oops.Wrapf(err, "gtfs export: set snapshot")
	}
	if err := createGTFSTempTables(ctx, tx, true /* withData */); err != nil {
		return 0, err
	}

	zw := zip.NewWriter(w)
	var total int64
	for _, file := range gtfsFiles(version) {
		entry, err := zw.Create(file.name)
		if err != nil {
			return 0, _oops.With("file_name", file.name).Wrapf(err, "gtfs export: create")
		}
		tag, err := conn.Conn().PgConn().CopyTo(ctx, entry,
			"COPY ("+file.sql+") TO STDOUT WITH (FORMAT csv, HEADER true)")
		if err != nil {
			return 0, _oops.With("file_name", file.name).Wrapf(err, "gtfs export: copy")
		}
		zap.S().Infow("written",
			"component", "gtfs",
			"action", "export",
			"file", file.name,
			"rows", tag.RowsAffected(),
			"event", "written",
		)
		total += tag.RowsAffected()
	}
	if err := zw.Close(); err != nil {
		return 0, _oops.Wrapf(err, "gtfs export: finish archive")
	}
	return total, nil
}

// createGTFSTempTables materializes every derived set the files read by name.
//
// ON COMMIT DROP ties their lifetime to the export transaction, so a build that
// fails partway leaves nothing behind for the next one to collide with.
//
// withData false creates them empty (WITH NO DATA). The columns and types are
// still declared, which is all a statement needs to plan, so a test can check
// that every file resolves without paying for the sets it resolves against.
func createGTFSTempTables(ctx context.Context, tx pgx.Tx, withData bool) error {
	for _, table := range gtfsTempTables() {
		started := time.Now()
		create := "CREATE TEMP TABLE " + table.name + " ON COMMIT DROP AS " + table.sql
		if !withData {
			if _, err := tx.Exec(ctx, create+" WITH NO DATA"); err != nil {
				return _oops.With("table_name", table.name).Wrapf(err, "gtfs export: declare")
			}
			continue
		}
		if _, err := tx.Exec(ctx, create); err != nil {
			return _oops.With("table_name", table.name).Wrapf(err, "gtfs export: materialize")
		}
		if table.indexOn != "" {
			if _, err := tx.Exec(ctx, "CREATE INDEX ON "+table.name+" ("+table.indexOn+")"); err != nil {
				return _oops.With("table_name", table.name).Wrapf(err, "gtfs export: index")
			}
		}
		// Without this the temp table is as opaque to the planner as the
		// expansion it replaced, and the whole point is lost.
		if _, err := tx.Exec(ctx, "ANALYZE "+table.name); err != nil {
			return _oops.With("table_name", table.name).Wrapf(err, "gtfs export: analyze")
		}
		zap.S().Infow("materialized",
			"component", "gtfs",
			"action", "export",
			"table", table.name,
			"elapsed", time.Since(started).Round(time.Millisecond),
			"event", "materialized",
		)
	}
	return nil
}

// linkLatestGTFS repoints the stable name. The symlink is created under a
// temporary name and renamed over the old one, because os.Symlink cannot replace
// an existing path and unlinking first would leave a window with no feed.
func linkLatestGTFS(dir, target string) error {
	temp := filepath.Join(dir, ".gtfs.zip.link")
	_ = os.Remove(temp)
	if err := os.Symlink(target, temp); err != nil {
		return _oops.Wrapf(err, "gtfs export: link latest")
	}
	if err := os.Rename(temp, filepath.Join(dir, _gtfsLatestName)); err != nil {
		_ = os.Remove(temp)
		return _oops.Wrapf(err, "gtfs export: publish latest")
	}
	return nil
}

// pruneGTFSFeeds keeps the newest keep dated builds and deletes the rest. Names
// are sorted lexically, which is chronological because the timestamp is
// zero-padded and fixed-width.
func pruneGTFSFeeds(dir string, keep int) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return _oops.With("dir", dir).Wrapf(err, "read")
	}
	var feeds []string
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || !strings.HasPrefix(name, "gtfs-") || !strings.HasSuffix(name, ".zip") {
			continue
		}
		feeds = append(feeds, name)
	}
	if len(feeds) <= keep {
		return nil
	}
	sort.Sort(sort.Reverse(sort.StringSlice(feeds)))
	var failures []string
	for _, name := range feeds[keep:] {
		if err := os.Remove(filepath.Join(dir, name)); err != nil {
			failures = append(failures, name)
		}
	}
	if len(failures) > 0 {
		return _oops.With("failures", strings.Join(failures, ", ")).Errorf("remove")
	}
	return nil
}
