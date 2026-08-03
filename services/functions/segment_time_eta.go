package main

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
	"go.uber.org/zap"
)

// Running time between consecutive stops, differenced within one observation
// instead of across two.
//
// This is the only observation pass. A single ETA snapshot answers the question
// directly: at one instant TDX gives the seconds-to-arrival for every stop the
// approaching bus still has ahead of it, so the difference between two adjacent
// stops' estimates is that bus's running time between them. One row, no pairing,
// no vehicle identity.
//
// It outlived the plate-pairing pass it used to complement (removed 2026-08-02,
// see segment_time.go). Needing no vehicle identity is why: Taipei and NewTaipei
// publish no PlateNumb at all — over a week 36.8% and 31.6% of their rows carry
// none — so pairing never reached the two largest networks anyway, and where both
// did produce a hop they agreed to within 2 seconds of median over 45,775 of
// them.
//
// Needing only a snapshot is the other reason, and it is what lets the writer
// sample: a pass that differences within one recorded instant is indifferent to
// how far apart those instants are (historySnapshotInterval).
const (
	// segmentDiffMinSecs / segmentDiffMaxSecs match segmentMinSecs/segmentMaxSecs:
	// both bound one hop's running time, and a disagreement would put two
	// different definitions of "plausible" in one table.
	segmentDiffMinSecs = segmentMinSecs
	segmentDiffMaxSecs = segmentMaxSecs
	// segmentDiffWindow is deliberately wider than segmentWindow. The cumulative
	// pass has to match each observation to a departure, so old rows buy it
	// little; this pass only needs a route to have run once, and TDX reports
	// StopStatus 0 for the whole remainder of a route — a median of 32 consecutive
	// stops — so a single snapshot of a running route yields nearly all its hops.
	// Reaching further back therefore picks up the route that ran on a Tuesday and
	// not since: 7 days yields 131,507 hops, 14 yields 156,156. Beyond 14 adds
	// almost nothing today (156,478 for all of it) because the retained history
	// does not reach further, and 30-day cleanup bounds it regardless.
	segmentDiffWindow = 14 * 24 * time.Hour
	// segmentRateMinHops is how many observed hops a route direction needs before
	// its own pace is used instead of its city's. Below it the median is drawn
	// from too few segments to describe the route.
	segmentRateMinHops = 5
	// segmentEstimatedSamples marks a row as estimated rather than observed.
	// bus_segment_time carries no source column, and sample_count already means
	// "how many observations back this figure" — so zero says the honest thing,
	// and the sample-count conflict rule then lets any real observation replace
	// it. Readers wanting observed data only filter on sample_count > 0.
	segmentEstimatedSamples = 0
)

// computeSegmentTimesFromEstimates fills bus_segment_time from adjacent-stop
// estimate differences over the last window of history.
//
// A pair is kept only when the two stops are adjacent in the sequence and the
// later stop's estimate is the larger one. A bus approaching a stop is always
// further from the stop after it, so a non-positive difference means the two
// estimates describe different vehicles — most often a following bus that TDX
// reported at the later stop — and differencing them would be meaningless.
func computeSegmentTimesFromEstimates(ctx context.Context, db *pgxpool.Pool, hist historySource) error {
	if db == nil {
		return nil
	}
	if hist == nil {
		zap.S().Warnw("skipped", "component", "segment_time_eta", "reason", "history_disabled")
		return nil
	}
	zap.S().Infow("start", "component", "segment_time_eta")
	started := time.Now()
	segs, err := hist.segmentsByEstimate(ctx, segmentDiffWindow)
	if err != nil {
		return obs.Transient(fmt.Errorf("read estimate segments: %w", err))
	}
	n, err := upsertSegmentTimes(ctx, db, segs)
	if err != nil {
		return obs.Transient(fmt.Errorf("rebuild bus segment times from estimates: %w", err))
	}
	zap.S().Infow("complete",
		"component", "segment_time_eta",
		"segments", n,
		"elapsed", time.Since(started).Round(time.Millisecond),
	)
	return nil
}

// fillSegmentTimesFromDistance writes an estimated running time for every hop the
// two observation passes left empty, so a route direction is not lost to a single
// unobserved segment.
//
// GTFS is all-or-nothing per route direction: a journey is laid out by
// accumulating its hops, so one missing segment compresses everything downstream
// and the whole direction has to be dropped. That is why observed coverage of
// 46.1% of hops still leaves almost every route direction unusable — a 30-stop
// route needs all 29.
//
// Every stop carries a coordinate, so the gap can be closed with distance and a
// pace calibrated from the segments actually observed on that route (or, below
// segmentRateMinHops, on that city). Measured against observed Taipei hops the
// estimate lands within 30 seconds 72.9% of the time and within 60 seconds 92.2%,
// with a median error of 17 seconds — well short of a real observation's 2, which
// is why these rows are written with sample_count = 0 and never replace one.
//
// Straight-line distance understates the road, but the pace is calibrated from
// the same straight-line measure, so the detour is absorbed into the rate rather
// than left as a bias.
func fillSegmentTimesFromDistance(ctx context.Context, db *pgxpool.Pool) error {
	if db == nil {
		return nil
	}
	zap.S().Infow("start", "component", "segment_time_fill")
	started := time.Now()
	tag, err := db.Exec(ctx, `
		WITH hop AS (
			-- Every adjacent pair the network needs, from the same stop map the
			-- feed is joined against.
			SELECT sub_route_uid, direction, stop_uid, station_id, stop_sequence,
			       LEAD(stop_uid)      OVER w AS next_stop_uid,
			       LEAD(station_id)    OVER w AS next_station_id,
			       LEAD(stop_sequence) OVER w AS next_stop_sequence
			FROM bus_station_stop_map
			WINDOW w AS (PARTITION BY sub_route_uid, direction ORDER BY stop_sequence)
		), geo AS (
			SELECT h.sub_route_uid, h.direction, h.stop_uid, h.next_stop_uid,
			       ST_DistanceSphere(a.position, b.position) AS dist
			FROM hop h
			JOIN bus_stations a ON a.station_uid = h.station_id
			JOIN bus_stations b ON b.station_uid = h.next_station_id
			WHERE h.next_stop_sequence = h.stop_sequence + 1
		), observed AS (
			-- Pace is read back from what the observation passes wrote, so the
			-- estimate tracks the network's real speed rather than a constant.
			SELECT g.sub_route_uid, g.direction, t.secs / g.dist AS rate
			FROM bus_segment_time t
			JOIN geo g ON g.sub_route_uid = t.sub_route_uid
			          AND g.direction     = t.direction
			          AND g.stop_uid      = t.from_stop_uid
			          AND g.next_stop_uid = t.to_stop_uid
			WHERE t.sample_count > 0 AND g.dist > 0
		), rate_route AS (
			SELECT sub_route_uid, direction,
			       percentile_cont(0.5) WITHIN GROUP (ORDER BY rate) AS rate
			FROM observed GROUP BY 1, 2 HAVING count(*) >= $1
		), rate_city AS (
			SELECT left(sub_route_uid, 3) AS pfx,
			       percentile_cont(0.5) WITHIN GROUP (ORDER BY rate) AS rate
			FROM observed GROUP BY 1
		), rate_all AS (
			SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY rate) AS rate FROM observed
		)
		INSERT INTO bus_segment_time
		  (sub_route_uid, direction, from_stop_uid, to_stop_uid, secs, sample_count, updated_at)
		SELECT g.sub_route_uid, g.direction, g.stop_uid, g.next_stop_uid,
		       GREATEST($2, LEAST($3,
		         (g.dist * COALESCE(rr.rate, rc.rate, ra.rate))::int)),
		       $4, now()
		FROM geo g
		LEFT JOIN rate_route rr ON rr.sub_route_uid = g.sub_route_uid AND rr.direction = g.direction
		LEFT JOIN rate_city  rc ON rc.pfx = left(g.sub_route_uid, 3)
		CROSS JOIN rate_all ra
		WHERE g.dist > 0
		  AND COALESCE(rr.rate, rc.rate, ra.rate) IS NOT NULL
		-- Only genuinely empty hops. An existing row, observed or estimated, is
		-- left exactly as it is.
		ON CONFLICT (sub_route_uid, direction, from_stop_uid, to_stop_uid) DO NOTHING`,
		segmentRateMinHops, segmentDiffMinSecs, segmentDiffMaxSecs, segmentEstimatedSamples)
	if err != nil {
		return obs.Transient(fmt.Errorf("fill bus segment times from distance: %w", err))
	}
	zap.S().Infow("complete",
		"component", "segment_time_fill",
		"estimated", tag.RowsAffected(),
		"elapsed", time.Since(started).Round(time.Millisecond),
	)
	return nil
}
