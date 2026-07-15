package main

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
)

// travelAvgDB is the narrow query/exec seam computeTravelAvg and
// cleanupBusHistory need. *pgxpool.Pool satisfies it structurally; unit tests
// drive both functions through a pgxmock pool instead of a live database.
type travelAvgDB interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
}

// depKey identifies one origin-departure lookup: a sub-route, direction, and
// day of week. computeTravelAvg looks up departures per key, not per
// crossing, since many crossings share the same key.
type depKey struct {
	subRouteUID string
	direction   int16
	dayOfWeek   int16
}

// batchDepartureTimes resolves origin-stop departure times for every key in
// one round trip instead of one query per key. keys is deduplicated by the
// caller; an empty slice short-circuits without issuing a query. The keys are
// sent as parallel arrays and joined against bus_schedule with unnest, so N
// distinct (sub_route_uid, direction, day_of_week) tuples cost exactly one
// query regardless of N.
//
// Per key: origin-stop departures of each timetable trip that runs on that
// day of week. type=false rows are the per-stop timetable; the origin is the
// lowest stopsequence per trip (DISTINCT ON tripid). Frequency rows
// (type=true, stopsequence=-1) are windows, not observed trips, so they are
// excluded. service_day is a Mon..Sun bitmask (Monday=bit0); day_of_week
// follows time.Weekday (Sunday=0), hence 1 << ((dow+6)%7).
func batchDepartureTimes(ctx context.Context, db travelAvgDB, keys []depKey) (map[depKey][]time.Time, error) {
	result := make(map[depKey][]time.Time, len(keys))
	if len(keys) == 0 {
		return result, nil
	}

	subRouteUIDs := make([]string, len(keys))
	directions := make([]int16, len(keys))
	daysOfWeek := make([]int16, len(keys))
	masks := make([]int16, len(keys))
	for i, k := range keys {
		subRouteUIDs[i] = k.subRouteUID
		directions[i] = k.direction
		daysOfWeek[i] = k.dayOfWeek
		masks[i] = int16(1) << uint16((k.dayOfWeek+6)%7)
	}

	rows, err := db.Query(ctx, `
		SELECT k.sub_route_uid, k.direction, k.day_of_week, dep.dep
		FROM unnest($1::text[], $2::smallint[], $3::smallint[], $4::smallint[])
		       AS k(sub_route_uid, direction, day_of_week, mask)
		JOIN LATERAL (
			SELECT DISTINCT ON (tripid) "arrival_time/StartTime" AS dep
			FROM bus_schedule
			WHERE sub_route_uid = k.sub_route_uid AND direction = k.direction
			  AND type = false AND service_day & k.mask <> 0
			ORDER BY tripid, stopsequence
		) dep ON true
		ORDER BY k.sub_route_uid, k.direction, k.day_of_week, dep.dep`,
		subRouteUIDs, directions, daysOfWeek, masks)
	if err != nil {
		return nil, fmt.Errorf("query travel departures: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var key depKey
		var dep time.Time
		if err := rows.Scan(&key.subRouteUID, &key.direction, &key.dayOfWeek, &dep); err != nil {
			log.Errorf("[TRAVEL_AVG] dep batch scan error: %v", err)
			continue
		}
		result[key] = append(result[key], dep)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("scan travel departures: %w", err)
	}
	return result, nil
}

// cleanupBatchSize bounds each retention DELETE so cleanup never holds a
// single very-large transaction/lock against a live table. It repeats until a
// batch comes back under this size (nothing left to delete) or ctx is
// canceled.
const cleanupBatchSize = 5000

// batchDeleteOlderThan repeatedly deletes up to cleanupBatchSize rows from
// table matching cutoffColumn < NOW() - retention, checking ctx before every
// batch so a canceled run stops between batches instead of racing to finish
// or blocking a single oversized DELETE. ctid selection (rather than an id
// column) works regardless of the table's primary key shape. Returns the
// total rows deleted so far even when it returns an error, since prior
// batches already committed.
func batchDeleteOlderThan(ctx context.Context, db travelAvgDB, table, cutoffColumn, retention string) (int64, error) {
	sql := fmt.Sprintf(`
		WITH victims AS (
			SELECT ctid FROM %s WHERE %s < NOW() - INTERVAL '%s' LIMIT $1
		)
		DELETE FROM %s WHERE ctid IN (SELECT ctid FROM victims)`,
		table, cutoffColumn, retention, table)

	var total int64
	for {
		if err := ctx.Err(); err != nil {
			return total, err
		}
		tag, err := db.Exec(ctx, sql, cleanupBatchSize)
		if err != nil {
			return total, err
		}
		total += tag.RowsAffected()
		if tag.RowsAffected() < cleanupBatchSize {
			return total, nil
		}
	}
}

// cleanupBusHistory deletes bus_eta_history rows older than 30 days (the
// retention window) and, piggybacking on the same job, the prediction-error
// rows past the same window, in capped batches rather than one unbounded
// DELETE. The two targets are independent: a failure on one does not skip the
// other, and both failures are joined (not swallowed) so the caller's
// completion marker only advances once both retention targets fully succeed.
func cleanupBusHistory(ctx context.Context, db travelAvgDB) error {
	var errs []error

	historyDeleted, err := batchDeleteOlderThan(ctx, db, "bus_eta_history", "recorded_at", "30 days")
	if err != nil {
		log.Errorf("[ETA_HISTORY] cleanup error deleted=%d: %v", historyDeleted, err)
		errs = append(errs, fmt.Errorf("cleanup bus history: %w", err))
	} else {
		log.Infof("[ETA_HISTORY] cleanup deleted %d rows", historyDeleted)
	}

	perrDeleted, err := batchDeleteOlderThan(ctx, db, "bus_eta_prediction_error", "predicted_at", "30 days")
	if err != nil {
		log.Errorf("[ETA_ERROR] cleanup error deleted=%d: %v", perrDeleted, err)
		errs = append(errs, fmt.Errorf("cleanup prediction error: %w", err))
	} else {
		log.Infof("[ETA_ERROR] cleanup deleted %d rows", perrDeleted)
	}

	if len(errs) == 0 {
		return nil
	}
	return obs.Transient(errors.Join(errs...))
}

// computeTravelAvg rebuilds bus_travel_avg from the last 7 days of ETA history.
// It detects each arrival by finding where a stop's estimate crosses from
// positive to non-positive between consecutive samples and linearly interpolates
// the crossing instant (the SQL query). Each crossing is matched to the latest
// scheduled origin departure at or before it to derive an origin-to-stop travel
// time; samples outside 0..7200s are discarded as noise. Per (subroute,
// direction, stop, hour, day-of-week) bucket with at least 10 samples, it upserts
// the median, and only overwrites an existing average when this run has more
// samples. Query/upsert failures are wrapped transient so runDaily retries.
func computeTravelAvg(ctx context.Context, db travelAvgDB) error {
	log.Infof("[TRAVEL_AVG] start")

	type crossingRow struct {
		subRouteUID string
		direction   int16
		stopUID     string
		hour        int16
		dayOfWeek   int16
		crossingAt  time.Time
	}

	rows, err := db.Query(ctx, `
		WITH ordered AS (
			SELECT sub_route_uid, direction, stop_uid, hour, day_of_week, estimate, recorded_at,
			       LAG(estimate)    OVER w AS prev_est,
			       LAG(recorded_at) OVER w AS prev_at
			FROM bus_eta_history
			WHERE recorded_at >= NOW() - INTERVAL '7 days'
			WINDOW w AS (PARTITION BY sub_route_uid, direction, stop_uid ORDER BY recorded_at)
		)
		SELECT sub_route_uid, direction, stop_uid, hour, day_of_week,
		       prev_at + make_interval(secs =>
		           EXTRACT(EPOCH FROM recorded_at - prev_at) *
		           prev_est::float / (prev_est - estimate)::float
		       ) AS crossing_at
		FROM ordered
		WHERE prev_est > 0 AND estimate <= 0
		  AND EXTRACT(EPOCH FROM recorded_at - prev_at) < 300`)
	if err != nil {
		log.Errorf("[TRAVEL_AVG] crossing query error: %v", err)
		return obs.Transient(fmt.Errorf("query travel crossings: %w", err))
	}

	var crossings []crossingRow
	for rows.Next() {
		var c crossingRow
		if err := rows.Scan(&c.subRouteUID, &c.direction, &c.stopUID,
			&c.hour, &c.dayOfWeek, &c.crossingAt); err != nil {
			log.Errorf("[TRAVEL_AVG] scan error: %v", err)
		} else {
			crossings = append(crossings, c)
		}
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return obs.Transient(fmt.Errorf("scan travel crossings: %w", err))
	}
	rows.Close()
	log.Infof("[TRAVEL_AVG] detected %d arrival events", len(crossings))

	seenDepKeys := make(map[depKey]bool)
	var depKeys []depKey
	for _, c := range crossings {
		dkey := depKey{subRouteUID: c.subRouteUID, direction: c.direction, dayOfWeek: c.dayOfWeek}
		if !seenDepKeys[dkey] {
			seenDepKeys[dkey] = true
			depKeys = append(depKeys, dkey)
		}
	}
	depTimesByKey, err := batchDepartureTimes(ctx, db, depKeys)
	if err != nil {
		log.Errorf("[TRAVEL_AVG] dep batch query error keys=%d: %v", len(depKeys), err)
		return obs.Transient(fmt.Errorf("query travel departures: %w", err))
	}

	type aggKey struct {
		subRouteUID string
		direction   int16
		stopUID     string
		hour        int16
		dayOfWeek   int16
	}
	samples := make(map[aggKey][]int)

	for _, c := range crossings {
		dkey := depKey{subRouteUID: c.subRouteUID, direction: c.direction, dayOfWeek: c.dayOfWeek}
		depTimes := depTimesByKey[dkey]
		if len(depTimes) == 0 {
			continue
		}
		crossLocal := c.crossingAt.In(taipei)
		todSecs := crossLocal.Hour()*3600 + crossLocal.Minute()*60 + crossLocal.Second()

		var bestDep time.Time
		for _, dt := range depTimes {
			depSecs := dt.Hour()*3600 + dt.Minute()*60 + dt.Second()
			if depSecs <= todSecs {
				bestDep = dt
			}
		}
		if bestDep.IsZero() {
			continue
		}
		depFull := time.Date(crossLocal.Year(), crossLocal.Month(), crossLocal.Day(),
			bestDep.Hour(), bestDep.Minute(), bestDep.Second(), 0, taipei)
		travelSec := int(c.crossingAt.Sub(depFull).Seconds())
		if travelSec < 0 || travelSec > 7200 {
			continue
		}
		key := aggKey{subRouteUID: c.subRouteUID, direction: c.direction, stopUID: c.stopUID, hour: c.hour, dayOfWeek: c.dayOfWeek}
		samples[key] = append(samples[key], travelSec)
	}

	upserted := 0
	for key, vals := range samples {
		if len(vals) < 10 {
			continue
		}
		sort.Ints(vals)
		median := vals[len(vals)/2]
		_, err := db.Exec(ctx, `
			INSERT INTO bus_travel_avg
			  (sub_route_uid, direction, stop_uid, hour, day_of_week, avg_seconds, sample_count, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
			ON CONFLICT (sub_route_uid, direction, stop_uid, hour, day_of_week)
			DO UPDATE SET avg_seconds = EXCLUDED.avg_seconds,
			              sample_count = EXCLUDED.sample_count,
			              updated_at   = NOW()
			WHERE bus_travel_avg.sample_count = 0
			   OR EXCLUDED.sample_count > bus_travel_avg.sample_count`,
			key.subRouteUID, key.direction, key.stopUID,
			key.hour, key.dayOfWeek, median, len(vals))
		if err != nil {
			log.Errorf("[TRAVEL_AVG] upsert error: %v", err)
			return obs.Transient(fmt.Errorf("upsert travel average: %w", err))
		} else {
			upserted++
		}
	}
	log.Infof("[TRAVEL_AVG] complete crossings=%d upserted=%d", len(crossings), upserted)
	return nil
}
