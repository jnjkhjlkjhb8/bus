package main

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
)

// cleanupBusHistory deletes bus_eta_history rows older than 30 days (the
// retention window) and, piggybacking on the same job, the prediction-error rows
// past the same window. A failure is wrapped as transient so runDaily retries.
func cleanupBusHistory(ctx context.Context, db *pgxpool.Pool) error {
	tag, err := db.Exec(ctx, `DELETE FROM bus_eta_history WHERE recorded_at < NOW() - INTERVAL '30 days'`)
	if err != nil {
		log.Infof("[ETA_HISTORY] cleanup error: %v", err)
		return obs.Transient(fmt.Errorf("cleanup bus history: %w", err))
	}
	log.Infof("[ETA_HISTORY] cleanup deleted %d rows", tag.RowsAffected())

	perrTag, err := db.Exec(ctx, `DELETE FROM bus_eta_prediction_error WHERE predicted_at < NOW() - INTERVAL '30 days'`)
	if err != nil {
		log.Infof("[ETA_ERROR] cleanup error: %v", err)
		return obs.Transient(fmt.Errorf("cleanup prediction error: %w", err))
	}
	log.Infof("[ETA_ERROR] cleanup deleted %d rows", perrTag.RowsAffected())
	return nil
}

// travelAvgRebuildSQL rebuilds every travel-average bucket in one statement.
//
// A stop's live estimate decays toward zero as the bus approaches, so the last
// sample of a descending run is the closest observation of an arrival:
// arrival = recorded_at + estimate. A run ends when the next sample for the same
// (subroute, direction, stop, plate) is missing, more than 90s later, or jumps
// back up by more than a minute — the last two mean the feed dropped out or the
// following bus took over the slot.
//
// plate_numb identifies the vehicle, so an arrival at the route's origin stop is
// that vehicle's actual departure, and every later arrival by the same plate
// belongs to the same trip. Matching on the plate's own departure — rather than
// on the nearest scheduled one — is what keeps travel times off routes whose
// headway is shorter than their run time from collapsing toward zero.
//
// Buckets key on the hour and weekday of the *departure*, matching how predict.go
// reads the table (schedule departure + travel average = arrival). Samples where
// TDX's own timestamp trails the poll by over a minute are dropped: adjustedEstimate
// derives those from stale data. A full 30-day rebuild runs nightly, so the newest
// result always wins the upsert.
const travelAvgRebuildSQL = `
WITH fresh AS (
    SELECT sub_route_uid, direction, stop_uid, stop_sequence, plate_numb,
           estimate, recorded_at,
           recorded_at + make_interval(secs => estimate) AS arrival_at
    FROM bus_eta_history
    WHERE recorded_at >= NOW() - INTERVAL '30 days'
      AND plate_numb IS NOT NULL
      AND (src_update_time IS NULL
           OR recorded_at - src_update_time <= INTERVAL '60 seconds')
), tagged AS (
    SELECT *,
           LEAD(recorded_at) OVER w AS next_at,
           LEAD(estimate)    OVER w AS next_estimate,
           MIN(stop_sequence) OVER (PARTITION BY sub_route_uid, direction) AS origin_sequence
    FROM fresh
    WINDOW w AS (PARTITION BY sub_route_uid, direction, stop_uid, plate_numb
                 ORDER BY recorded_at)
), arrivals AS (
    SELECT sub_route_uid, direction, stop_uid, stop_sequence, origin_sequence,
           plate_numb, arrival_at
    FROM tagged
    WHERE estimate BETWEEN -60 AND 120
      AND (next_at IS NULL
           OR next_at - recorded_at > INTERVAL '90 seconds'
           OR next_estimate > estimate + 60)
), origins AS (
    SELECT sub_route_uid, direction, plate_numb, arrival_at AS departed_at
    FROM arrivals
    WHERE stop_sequence = origin_sequence
), trips AS (
    SELECT a.sub_route_uid, a.direction, a.stop_uid, o.departed_at,
           EXTRACT(EPOCH FROM a.arrival_at - o.departed_at)::int AS travel_seconds
    FROM arrivals a
    JOIN LATERAL (
        SELECT departed_at
        FROM origins o
        WHERE o.sub_route_uid = a.sub_route_uid
          AND o.direction     = a.direction
          AND o.plate_numb    = a.plate_numb
          AND o.departed_at  <= a.arrival_at
        ORDER BY o.departed_at DESC
        LIMIT 1
    ) o ON TRUE
    WHERE a.stop_sequence > a.origin_sequence
)
INSERT INTO bus_travel_avg
    (sub_route_uid, direction, stop_uid, hour, day_of_week, avg_seconds, sample_count, updated_at)
SELECT sub_route_uid, direction, stop_uid,
       EXTRACT(HOUR FROM departed_at AT TIME ZONE 'Asia/Taipei')::smallint,
       EXTRACT(DOW  FROM departed_at AT TIME ZONE 'Asia/Taipei')::smallint,
       percentile_disc(0.5) WITHIN GROUP (ORDER BY travel_seconds)::int,
       count(*),
       NOW()
FROM trips
WHERE travel_seconds BETWEEN 60 AND 7200
GROUP BY 1, 2, 3, 4, 5
HAVING count(*) >= 3
ON CONFLICT (sub_route_uid, direction, stop_uid, hour, day_of_week)
DO UPDATE SET avg_seconds  = EXCLUDED.avg_seconds,
              sample_count = EXCLUDED.sample_count,
              updated_at   = NOW()`

// computeTravelAvg rebuilds bus_travel_avg from the last 30 days of ETA history;
// see travelAvgRebuildSQL for how arrivals and trips are derived. Vehicle plates
// come from the live position feed, so the coverage line tells whether a thin
// result is a plate-matching problem rather than a lack of history. A failure is
// wrapped as transient so runDaily retries.
func computeTravelAvg(ctx context.Context, db *pgxpool.Pool) error {
	log.Infof("[TRAVEL_AVG] start")

	var rowCount, plateCount int64
	if err := db.QueryRow(ctx, `
		SELECT count(*), count(plate_numb)
		FROM bus_eta_history
		WHERE recorded_at >= NOW() - INTERVAL '30 days'`).Scan(&rowCount, &plateCount); err != nil {
		log.Infof("[TRAVEL_AVG] coverage query error: %v", err)
	} else {
		log.Infof("[TRAVEL_AVG] history rows=%d with_plate=%d", rowCount, plateCount)
	}

	tag, err := db.Exec(ctx, travelAvgRebuildSQL)
	if err != nil {
		log.Infof("[TRAVEL_AVG] rebuild error: %v", err)
		return obs.Transient(fmt.Errorf("rebuild travel averages: %w", err))
	}
	log.Infof("[TRAVEL_AVG] complete upserted=%d", tag.RowsAffected())
	return nil
}
