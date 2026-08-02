package main

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
)

// Observed running time between consecutive stops, rebuilt from ETA history.
// This is the only shape the observations support, and the one both ETA
// prediction and the GTFS export accumulate along the stop sequence.
//
// It replaced a cumulative measure (bus_travel_avg, dropped 2026-07-31) that
// recorded seconds from a subroute's departure to a stop. That needs a departure
// time to measure from, so every observation had to match a bus_schedule row and
// was discarded when none lined up — over seven days it reached 34 subroutes
// against 2,395 here. A segment needs only two arrivals by the same vehicle.
//
// Segments are also what a timetable wants. Laying out a trip means accumulating
// them along the stop sequence, and an unobserved segment leaves a gap at one
// hop rather than invalidating everything after it.
//
// The reduction runs on the history host and only the medians come back. The
// observations live on MySQL and bus_segment_time on PostgreSQL, so a rebuild
// cannot be the single INSERT ... SELECT it was while both sat in one database;
// aggregating remotely keeps what crosses the wire at one row per hop rather than
// the millions of history rows behind them.
const (
	// segmentWindow is how much history one rebuild considers. Seven days keeps
	// every day of week represented while bounding the scan.
	segmentWindow = 7 * 24 * time.Hour
	// segmentApproachSecs bounds how early a final estimate may be and still
	// count as an arrival.
	//
	// A history row is only written while a bus is en route, so the arrival is
	// never recorded directly (see mysqlHistory.segmentsByPlate) and it has to be
	// inferred from the last estimate before the vehicle stops being reported. TDX usually
	// stops well before arrival: of 467,462 approaches over a week, only 10.7%
	// end within two minutes, while 24.4% end within five.
	//
	// Five minutes trades a little accuracy for more than double the coverage.
	// What is being measured is a running time between stops, not a timetable to
	// the second, and taking the median over observations absorbs the error in
	// any one estimate.
	segmentApproachSecs = 300
	// segmentGapSecs is how long a plate must go unreported at a stop before its
	// run is considered finished. It matches the polling cadence's tolerance.
	segmentGapSecs = 300
	// segmentUpsertBatch bounds one upsert into bus_segment_time. The rebuild
	// produces on the order of 150k hops and the target is a 2 GB Azure server, so
	// the rows go over in batches rather than as one statement carrying every
	// array. Each batch is one round trip; the medians are already computed.
	segmentUpsertBatch = 2000
	// Segments outside these bounds are dropped rather than recorded. Below five
	// seconds is two stops sharing a position; above thirty minutes is a vehicle
	// that went out of service, or two runs of one plate stitched together.
	segmentMinSecs = 5
	segmentMaxSecs = 1800
)

// computeSegmentTimes rebuilds bus_segment_time from the last window of history.
//
// Rows are written from a single observation upward, with sample_count stored
// alongside. A lone observation is still a real measurement — TDX's own estimate
// at under five minutes out, differenced against the next stop's — and holding
// them back would cut coverage from 2,395 subroutes to 514. Readers that want
// more certainty filter on sample_count; that judgement does not belong here.
func computeSegmentTimes(ctx context.Context, db *pgxpool.Pool, hist historySource) error {
	if db == nil {
		return nil
	}
	if hist == nil {
		log.Warnf("[SEGMENT_TIME] skipped reason=history_disabled")
		return nil
	}
	log.Infof("[SEGMENT_TIME] start")
	started := time.Now()
	segs, err := hist.segmentsByPlate(ctx, segmentWindow)
	if err != nil {
		return obs.Transient(fmt.Errorf("read plate segments: %w", err))
	}
	n, err := upsertSegmentTimes(ctx, db, segs, false)
	if err != nil {
		return obs.Transient(fmt.Errorf("rebuild bus segment times: %w", err))
	}
	log.Infof("[SEGMENT_TIME] complete segments=%d elapsed=%s",
		n, time.Since(started).Round(time.Millisecond))
	return nil
}

// upsertSegmentTimes writes already-reduced hops into bus_segment_time.
//
// onlyIfBetterSampled restricts the update to rows resting on more observations
// than what is already stored. The plate pass writes unconditionally because it
// runs first; the estimate pass sets it, so whichever figure has more
// observations behind it is the one left in the table regardless of which pass
// produced it.
//
// The rows arrive grouped by the conflict key, so no batch can contain the same
// key twice — which ON CONFLICT DO UPDATE would reject outright rather than
// silently pick a winner.
func upsertSegmentTimes(ctx context.Context, db *pgxpool.Pool, segs []segmentObs, onlyIfBetterSampled bool) (int64, error) {
	stmt := `
		INSERT INTO bus_segment_time
		  (sub_route_uid, direction, from_stop_uid, to_stop_uid, secs, sample_count, updated_at)
		SELECT u.sub_route_uid, u.direction, u.from_stop_uid, u.to_stop_uid,
		       u.secs, u.sample_count, now()
		FROM unnest($1::text[], $2::smallint[], $3::text[], $4::text[], $5::int[], $6::int[])
		     AS u(sub_route_uid, direction, from_stop_uid, to_stop_uid, secs, sample_count)
		ON CONFLICT (sub_route_uid, direction, from_stop_uid, to_stop_uid)
		DO UPDATE SET secs         = EXCLUDED.secs,
		              sample_count = EXCLUDED.sample_count,
		              updated_at   = now()`
	if onlyIfBetterSampled {
		stmt += `
		WHERE EXCLUDED.sample_count > bus_segment_time.sample_count`
	}
	var total int64
	for start := 0; start < len(segs); start += segmentUpsertBatch {
		batch := segs[start:min(start+segmentUpsertBatch, len(segs))]
		subRoutes := make([]string, len(batch))
		directions := make([]int16, len(batch))
		fromStops := make([]string, len(batch))
		toStops := make([]string, len(batch))
		secs := make([]int32, len(batch))
		samples := make([]int32, len(batch))
		for i, s := range batch {
			subRoutes[i], directions[i] = s.subRouteUID, s.direction
			fromStops[i], toStops[i] = s.fromStopUID, s.toStopUID
			secs[i], samples[i] = int32(s.secs), int32(s.sampleCount)
		}
		tag, err := db.Exec(ctx, stmt, subRoutes, directions, fromStops, toStops, secs, samples)
		if err != nil {
			return total, fmt.Errorf("upsert segments %d..%d: %w", start, start+len(batch), err)
		}
		total += tag.RowsAffected()
	}
	return total, nil
}
