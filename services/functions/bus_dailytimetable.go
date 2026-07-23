package main

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/robfig/cron/v3"
)

// busDailyHourlyTimeout bounds one hourly bus_dailytimetable load. Only the
// cities whose landing marker moved are transformed, so a quiet hour costs one
// landing_state query and the full-refresh hour stays well inside this budget.
const busDailyHourlyTimeout = 15 * time.Minute

// registerBusDailyTimetableCron schedules the hourly bus_dailytimetable load
// that pairs with the ingestor's hourly landing (:00 lands, :10 loads). The
// 03:30 full load still covers this dataset; this cron only shortens the gap
// between a TDX revision and Redis.
//
// loaded is the in-process record of the landing marker each city was last
// loaded from, and is what keeps an hourly cadence affordable: without it every
// tick would rebuild ~17 cities of timetable JSON out of Azure raw_tdx whether
// or not anything changed. It is deliberately not durable — a loader restart
// costs one redundant full pass, which is cheaper than owning shared state for
// it. Only this cron entry touches the map, and addStaticCron's
// SkipIfStillRunning keeps one entry from overlapping itself.
func registerBusDailyTimetableCron(r *cron.Cron, rawPool, db *pgxpool.Pool, rc *redis.Client) {
	src := rawTDXSource{pool: rawPool}
	runner := newStaticPipelineRunner(rawPool, busDailyHourlyTimeout)
	loaded := map[string]string{}
	_, _ = addStaticCron(r, "0 10 * * * *", func() {
		err := runner.Run(context.Background(), func(ctx context.Context) error {
			return loadChangedBusDailyTimetables(ctx, rawPool, src, db, rc, loaded)
		})
		if err != nil {
			log.Errorf("[LOAD] action=bus_dailytimetable_hourly event=failed error=%v", err)
		}
	})
}

// rawMarkerQuerier is the narrow read the hourly load needs from raw_tdx,
// kept separate from *pgxpool.Pool so the marker query is testable.
type rawMarkerQuerier interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
}

// busDailyLandingMarkers returns each landed city's durable Last-Modified
// marker for bus_dailytimetable. last_modified is the only change signal
// available: a 304 still advances landing_state.fetched_at (it records that the
// landing ran), so freshness cannot stand in for "the payload changed".
func busDailyLandingMarkers(ctx context.Context, q rawMarkerQuerier) (map[string]string, error) {
	rows, err := q.Query(ctx, `
		SELECT partition_value, last_modified
		FROM raw_tdx.landing_state
		WHERE table_name='bus_dailytimetable' AND partition_column='city'`)
	if err != nil {
		return nil, fmt.Errorf("read bus_dailytimetable landing markers: %w", err)
	}
	defer rows.Close()
	markers := make(map[string]string, 32)
	for rows.Next() {
		var city, marker string
		if err := rows.Scan(&city, &marker); err != nil {
			return nil, fmt.Errorf("read bus_dailytimetable landing markers: scan: %w", err)
		}
		markers[city] = marker
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("read bus_dailytimetable landing markers: rows: %w", err)
	}
	return markers, nil
}

// busDailyPendingCities returns the cities to transform this tick, sorted: those
// whose landing marker differs from the one they were last loaded from, minus
// the cities TDX serves no daily timetable for. An empty loaded map (fresh
// process) yields every landed city, which is the intended first pass.
func busDailyPendingCities(markers, loaded map[string]string) []string {
	pending := make([]string, 0, len(markers))
	for city, marker := range markers {
		if busDailyTimetableSkip(city) || loaded[city] == marker {
			continue
		}
		pending = append(pending, city)
	}
	sort.Strings(pending)
	return pending
}

// loadChangedBusDailyTimetables transforms one city per changed landing marker.
// Each city runs as its own single-partition spec so a failure is recorded per
// city: its marker stays unrecorded and the next tick retries it, while the
// cities that succeeded are not reloaded.
func loadChangedBusDailyTimetables(
	ctx context.Context,
	q rawMarkerQuerier,
	src loadSource,
	db *pgxpool.Pool,
	rc *redis.Client,
	loaded map[string]string,
) error {
	markers, err := busDailyLandingMarkers(ctx, q)
	if err != nil {
		return err
	}
	base, err := busDailyTimetableSpec(src)
	if err != nil {
		return err
	}
	pending := busDailyPendingCities(markers, loaded)
	var failures []error
	for _, city := range pending {
		spec := base
		spec.partitions = func() []string { return []string{city} }
		if _, err := runLoadSpecs(ctx, src, db, rc, []loadSpec{spec}); err != nil {
			failures = append(failures, err)
			continue
		}
		loaded[city] = markers[city]
	}
	log.Infof("[LOAD] action=bus_dailytimetable_hourly event=done changed=%d failed=%d", len(pending), len(failures))
	return errors.Join(failures...)
}

// busDailyTimetableSpec pulls the daily-timetable loader recipe out of the
// registry so the hourly path reuses the same transform, staleness rule and
// partition column as the 03:30 run.
func busDailyTimetableSpec(src loadSource) (loadSpec, error) {
	for _, spec := range loaderRegistry(src) {
		if spec.key == "bus_dailytimetable" {
			return spec, nil
		}
	}
	return loadSpec{}, errors.New("bus daily timetable: loader spec missing from registry")
}
