package main

import (
	"archive/zip"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
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
	// gtfsExportTimeout bounds one build. It is generous because the cost is
	// dominated by one full scan of bus_stopofroute's nested stop arrays.
	gtfsExportTimeout = 15 * time.Minute
	// gtfsOutputDirEnv overrides where feeds are written. The default is a path
	// a volume can be mounted at, since the consumer of these files is another
	// container.
	gtfsOutputDirEnv     = "GTFS_OUT_DIR"
	gtfsDefaultOutputDir = "/data/gtfs"
	// gtfsLatestName is the stable path a planner is pointed at. It is a symlink
	// so that publishing a new feed is one atomic rename rather than a copy.
	gtfsLatestName = "gtfs.zip"
	// gtfsKeepFeeds is how many dated builds survive a prune. Enough to roll back
	// to a known-good feed after a bad one ships, not enough to fill the disk.
	gtfsKeepFeeds = 3
)

// gtfsFile is one entry in the archive. sql must be a complete SELECT; the
// COPY wrapper and CSV framing are added here so no statement can forget them.
type gtfsFile struct {
	name string
	sql  string
}

// gtfsFiles is the feed's contents.
//
// The file set is complete for bus, metro and rail. What is missing is service,
// not structure: Taipei, New Taipei, Tainan and Taoyuan have routes and stops
// but no trips, because building their stop times needs observed segment
// running times the ETA history does not yet cover (FDPL-23, FDPL-26).
func gtfsFiles(version string) []gtfsFile {
	return []gtfsFile{
		{"agency.txt", gtfsAgencySQL},
		{"stops.txt", gtfsStopsSQL},
		{"routes.txt", gtfsRoutesSQL},
		{"calendar_dates.txt", gtfsCalendarDatesSQL},
		{"trips.txt", gtfsTripsSQL},
		{"stop_times.txt", gtfsStopTimesSQL},
		{"frequencies.txt", gtfsFrequenciesSQL},
		{"transfers.txt", gtfsTransfersSQL},
		{"pathways.txt", gtfsPathwaysSQL},
		{"shapes.txt", gtfsShapesSQL},
		{"areas.txt", gtfsAreasSQL},
		{"stop_areas.txt", gtfsStopAreasSQL},
		{"fare_products.txt", gtfsFareProductsSQL},
		{"fare_leg_rules.txt", gtfsFareLegRulesSQL},
		{"translations.txt", gtfsTranslationsSQL},
		{"feed_info.txt", gtfsFeedInfoSQL(version)},
		{"attributions.txt", gtfsAttributionsSQL},
	}
}

func gtfsOutputDir() string {
	if dir := strings.TrimSpace(os.Getenv(gtfsOutputDirEnv)); dir != "" {
		return dir
	}
	return gtfsDefaultOutputDir
}

// runGTFSExport builds one feed and publishes it, logging rather than returning
// an error: it is the last stage of the nightly chain and nothing downstream in
// this process depends on it, so a failed export must not fail the load that
// already succeeded.
func runGTFSExport(db *pgxpool.Pool, runDate time.Time) {
	ctx, cancel := context.WithTimeout(context.Background(), gtfsExportTimeout)
	defer cancel()
	started := time.Now()
	path, rows, err := buildGTFSFeed(ctx, db, gtfsOutputDir(), runDate)
	if err != nil {
		log.Errorf("[GTFS] action=export event=failed error=%v", err)
		return
	}
	log.Infof("[GTFS] action=export event=success path=%s rows=%d elapsed=%s",
		path, rows, time.Since(started).Round(time.Millisecond))
}

// buildGTFSFeed writes a dated feed, points the stable name at it, and prunes
// older builds. It returns the dated path and the total row count.
//
// The archive is written to a temporary name and renamed into place, so a
// consumer polling the directory never observes a half-written zip.
func buildGTFSFeed(ctx context.Context, db *pgxpool.Pool, dir string, runDate time.Time) (string, int64, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", 0, fmt.Errorf("gtfs export: create %s: %w", dir, err)
	}
	version := runDate.Format("20060102-1504")
	final := filepath.Join(dir, "gtfs-"+version+".zip")

	temp, err := os.CreateTemp(dir, ".gtfs-*.zip.tmp")
	if err != nil {
		return "", 0, fmt.Errorf("gtfs export: create temp: %w", err)
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
		return "", 0, fmt.Errorf("gtfs export: sync: %w", err)
	}
	if err := temp.Close(); err != nil {
		return "", 0, fmt.Errorf("gtfs export: close: %w", err)
	}
	if err := os.Rename(tempName, final); err != nil {
		return "", 0, fmt.Errorf("gtfs export: publish %s: %w", final, err)
	}
	if err := linkLatestGTFS(dir, filepath.Base(final)); err != nil {
		return "", 0, err
	}
	if err := pruneGTFSFeeds(dir, gtfsKeepFeeds); err != nil {
		// A failed prune leaves extra files behind; the feed itself is published
		// and usable, so this is reported without failing the build.
		log.Warnf("[GTFS] action=prune event=failed error=%v", err)
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
		return 0, fmt.Errorf("gtfs export: acquire connection: %w", err)
	}
	defer conn.Release()

	tx, err := conn.Begin(ctx)
	if err != nil {
		return 0, fmt.Errorf("gtfs export: begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY"); err != nil {
		return 0, fmt.Errorf("gtfs export: set snapshot: %w", err)
	}

	zw := zip.NewWriter(w)
	var total int64
	for _, file := range gtfsFiles(version) {
		entry, err := zw.Create(file.name)
		if err != nil {
			return 0, fmt.Errorf("gtfs export: create %s: %w", file.name, err)
		}
		tag, err := conn.Conn().PgConn().CopyTo(ctx, entry,
			"COPY ("+file.sql+") TO STDOUT WITH (FORMAT csv, HEADER true)")
		if err != nil {
			return 0, fmt.Errorf("gtfs export: copy %s: %w", file.name, err)
		}
		log.Infof("[GTFS] action=export file=%s rows=%d event=written", file.name, tag.RowsAffected())
		total += tag.RowsAffected()
	}
	if err := zw.Close(); err != nil {
		return 0, fmt.Errorf("gtfs export: finish archive: %w", err)
	}
	return total, nil
}

// linkLatestGTFS repoints the stable name. The symlink is created under a
// temporary name and renamed over the old one, because os.Symlink cannot replace
// an existing path and unlinking first would leave a window with no feed.
func linkLatestGTFS(dir, target string) error {
	temp := filepath.Join(dir, ".gtfs.zip.link")
	_ = os.Remove(temp)
	if err := os.Symlink(target, temp); err != nil {
		return fmt.Errorf("gtfs export: link latest: %w", err)
	}
	if err := os.Rename(temp, filepath.Join(dir, gtfsLatestName)); err != nil {
		_ = os.Remove(temp)
		return fmt.Errorf("gtfs export: publish latest: %w", err)
	}
	return nil
}

// pruneGTFSFeeds keeps the newest keep dated builds and deletes the rest. Names
// are sorted lexically, which is chronological because the timestamp is
// zero-padded and fixed-width.
func pruneGTFSFeeds(dir string, keep int) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return fmt.Errorf("read %s: %w", dir, err)
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
		return fmt.Errorf("remove %s", strings.Join(failures, ", "))
	}
	return nil
}
