package history

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Observed running time between consecutive stops, rebuilt from ETA history.
// This is the only shape the observations support, and the one both ETA
// prediction and the GTFS export accumulate along the stop sequence.
//
// It replaced a cumulative measure (bus_travel_avg, dropped 2026-07-31) that
// recorded seconds from a subroute's departure to a stop. That needs a departure
// time to measure from, so every observation had to match a bus_schedule row and
// was discarded when none lined up — over seven days it reached 34 subroutes
// against 2,395 here.
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
//
// There was a second observation pass here until 2026-08-02: computeSegmentTimes
// grouped history rows by plate_numb and differenced consecutive arrivals. It is
// gone, and this file keeps only what both passes shared. Three things retired it
// together — it agreed with the surviving pass to within 2 seconds of median over
// 45,775 overlapping hops, so it carried no information of its own; its "arrival"
// was itself derived from an estimate (recorded_at + estimate), so it was never
// the ground truth it looked like; and it was the one reader that needed a dense
// series rather than snapshots, which made it read gaps in the history as buses
// arriving. That last one is why it had to go rather than merely idle: with the
// writer sampled (historySnapshotInterval), it would have manufactured arrivals
// out of the sampling interval itself.
const (
	// _segmentUpsertBatch bounds one upsert into bus_segment_time. The rebuild
	// produces on the order of 150k hops and the target is a 2 GB Azure server, so
	// the rows go over in batches rather than as one statement carrying every
	// array. Each batch is one round trip; the medians are already computed.
	_segmentUpsertBatch = 2000
	// Segments outside these bounds are dropped rather than recorded. Below five
	// seconds is two stops sharing a position; above thirty minutes is a vehicle
	// that went out of service, or two runs of one plate stitched together.
	_segmentMinSecs = 5
	_segmentMaxSecs = 1800
)

// upsertSegmentTimes writes already-reduced hops into bus_segment_time.
//
// The write is unconditional. It was once guarded on sample_count so the two
// observation passes could not clobber each other's better-sampled figure; with
// one pass left, that guard would instead pin the table to whichever day
// happened to observe the most — a quieter week could never refresh a hop, and
// the stored seconds would age indefinitely while looking freshly written.
// Estimated rows (sample_count 0, FillSegmentTimesFromDistance) are meant to be
// replaced by an observation and this is what replaces them.
//
// The rows arrive grouped by the conflict key, so no batch can contain the same
// key twice — which ON CONFLICT DO UPDATE would reject outright rather than
// silently pick a winner.
func upsertSegmentTimes(ctx context.Context, db *pgxpool.Pool, segs []SegmentObs) (int64, error) {
	stmt := `
		INSERT INTO bus_segment_time
		  (sub_route_uid, direction, from_stop_uid, to_stop_uid, secs, sample_count, updated_at)
		SELECT u.sub_route_uid, u.Direction, u.from_stop_uid, u.to_stop_uid,
		       u.secs, u.sample_count, now()
		FROM unnest($1::text[], $2::smallint[], $3::text[], $4::text[], $5::int[], $6::int[])
		     AS u(sub_route_uid, direction, from_stop_uid, to_stop_uid, secs, sample_count)
		ON CONFLICT (sub_route_uid, direction, from_stop_uid, to_stop_uid)
		DO UPDATE SET secs         = EXCLUDED.secs,
		              sample_count = EXCLUDED.sample_count,
		              updated_at   = now()`
	var total int64
	for start := 0; start < len(segs); start += _segmentUpsertBatch {
		batch := segs[start:min(start+_segmentUpsertBatch, len(segs))]
		subRoutes := make([]string, len(batch))
		directions := make([]int16, len(batch))
		fromStops := make([]string, len(batch))
		toStops := make([]string, len(batch))
		secs := make([]int32, len(batch))
		samples := make([]int32, len(batch))
		for i, s := range batch {
			subRoutes[i], directions[i] = s.SubRouteUID, s.Direction
			fromStops[i], toStops[i] = s.fromStopUID, s.toStopUID
			secs[i], samples[i] = int32(s.secs), int32(s.sampleCount)
		}
		tag, err := db.Exec(ctx, stmt, subRoutes, directions, fromStops, toStops, secs, samples)
		if err != nil {
			return total, _oops.With("start", start).With("end", start+len(batch)).Wrapf(err, "upsert segments")
		}
		total += tag.RowsAffected()
	}
	return total, nil
}
