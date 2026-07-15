package main

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
)

// cleanupBusHistory deletes bus_eta_history rows older than 30 days (the
// retention window) and, piggybacking on the same job, the prediction-error rows
// past the same window. A failure is wrapped as transient so runDaily retries.
func cleanupBusHistory(ctx context.Context, db *pgxpool.Pool) error {
	tag, err := db.Exec(ctx, `DELETE FROM bus_eta_history WHERE recorded_at < NOW() - INTERVAL '30 days'`)
	if err != nil {
		log.Errorf("[ETA_HISTORY] cleanup error: %v", err)
		return obs.Transient(fmt.Errorf("cleanup bus history: %w", err))
	}
	log.Infof("[ETA_HISTORY] cleanup deleted %d rows", tag.RowsAffected())

	perrTag, err := db.Exec(ctx, `DELETE FROM bus_eta_prediction_error WHERE predicted_at < NOW() - INTERVAL '30 days'`)
	if err != nil {
		log.Errorf("[ETA_ERROR] cleanup error: %v", err)
		return obs.Transient(fmt.Errorf("cleanup prediction error: %w", err))
	}
	log.Infof("[ETA_ERROR] cleanup deleted %d rows", perrTag.RowsAffected())
	return nil
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
func computeTravelAvg(ctx context.Context, db *pgxpool.Pool) error {
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
	type depKey struct {
		subRouteUID string
		direction   int16
		dayOfWeek   int16
	}
	depCache := make(map[depKey][]time.Time)
	getDepTimes := func(key depKey) []time.Time {
		if cached, ok := depCache[key]; ok {
			return cached
		}
		// Origin-stop departures of each timetable trip that runs on this
		// day of week. type=false rows are the per-stop timetable; the origin
		// is the lowest stopsequence per trip (DISTINCT ON tripid). Frequency
		// rows (type=true, stopsequence=-1) are windows, not observed trips, so
		// they are excluded from travel-average computation. service_day is a
		// Mon..Sun bitmask (Monday=bit0); day_of_week follows time.Weekday
		// (Sunday=0), hence 1 << ((dow+6)%7).
		mask := int16(1) << uint16((key.dayOfWeek+6)%7)
		drows, err := db.Query(ctx, `
			SELECT dep FROM (
				SELECT DISTINCT ON (tripid) "arrival_time/StartTime" AS dep
				FROM bus_schedule
				WHERE sub_route_uid = $1 AND direction = $2
				  AND type = false AND service_day & $3 <> 0
				ORDER BY tripid, stopsequence
			) t
			ORDER BY dep`,
			key.subRouteUID, key.direction, mask)
		if err != nil {
			log.Errorf("[TRAVEL_AVG] dep query error sub=%s dir=%d: %v", key.subRouteUID, key.direction, err)
			depCache[key] = []time.Time{}
			return nil
		}
		defer drows.Close()
		var times []time.Time
		for drows.Next() {
			var t time.Time
			if drows.Scan(&t) == nil {
				times = append(times, t)
			}
		}
		if err := drows.Err(); err != nil {
			log.Errorf("[TRAVEL_AVG] dep rows error sub=%s dir=%d: %v", key.subRouteUID, key.direction, err)
			depCache[key] = []time.Time{}
			return nil
		}
		depCache[key] = times
		return times
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
		depTimes := getDepTimes(dkey)
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
