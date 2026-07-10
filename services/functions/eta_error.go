package main

import (
	"context"
	"fmt"
	"math"
	"sort"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
)

// predictionSource labels which prediction tier produced an ETA, so accuracy can
// be compared tier by tier. Values match the source column of
// bus_eta_prediction_error.
const (
	sourceTDX         = "tdx"
	sourcePropagation = "propagation"
	sourceModel       = "model"
	sourceTravelAvg   = "travel_avg"
	sourceSchedule    = "schedule"
)

// predictionRecord is one prediction awaiting an actual: a predicted arrival at
// (route, direction, stop) made at predictedAt by source, in seconds-to-arrival.
type predictionRecord struct {
	subRouteUID   string
	direction     int16
	stopUID       string
	source        string
	predictedAt   time.Time
	predictedSecs int
}

// arrivalEvent is one observed vehicle arrival at a stop: the moment the vehicle
// reached (or passed) the stop, derived from an estimate crossing zero.
type arrivalEvent struct {
	subRouteUID string
	direction   int16
	stopUID     string
	arrivedAt   time.Time
}

// matchedError pairs a prediction with the actual arrival it predicted and the
// error in seconds (predicted minus actual arrival time). It is one row for
// bus_eta_prediction_error / one sample for MAE.
type matchedError struct {
	subRouteUID   string
	direction     int16
	stopUID       string
	source        string
	predictedAt   time.Time
	predictedSecs int
	actualSecs    int
}

// matchPredictionActual, for one (route, direction, stop), pairs each prediction
// with the earliest arrival at or after the moment it was made, then computes the
// error. The predicted arrival is predictedAt + predictedSecs; the actual is the
// matched arrival; actualSecs is the true seconds-to-arrival from predictedAt.
//
// A prediction with no later arrival within matchWindow is dropped (the vehicle
// never observably reached the stop, or history was pruned). Predictions and
// arrivals need not be pre-sorted.
func matchPredictionActual(preds []predictionRecord, arrivals []arrivalEvent, matchWindow time.Duration) []matchedError {
	sorted := append([]arrivalEvent(nil), arrivals...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].arrivedAt.Before(sorted[j].arrivedAt) })

	out := make([]matchedError, 0, len(preds))
	for _, p := range preds {
		var matched *arrivalEvent
		for i := range sorted {
			a := &sorted[i]
			if a.subRouteUID != p.subRouteUID || a.direction != p.direction || a.stopUID != p.stopUID {
				continue
			}
			if a.arrivedAt.Before(p.predictedAt) {
				continue
			}
			if a.arrivedAt.Sub(p.predictedAt) > matchWindow {
				break
			}
			matched = a
			break
		}
		if matched == nil {
			continue
		}
		out = append(out, matchedError{
			subRouteUID:   p.subRouteUID,
			direction:     p.direction,
			stopUID:       p.stopUID,
			source:        p.source,
			predictedAt:   p.predictedAt,
			predictedSecs: p.predictedSecs,
			actualSecs:    int(matched.arrivedAt.Sub(p.predictedAt).Round(time.Second).Seconds()),
		})
	}
	return out
}

// maeKey groups matched errors for aggregation: per route and prediction source.
type maeKey struct {
	subRouteUID string
	source      string
}

// maeStat is the aggregated accuracy for one (route, source): mean absolute
// error in seconds over n samples.
type maeStat struct {
	subRouteUID string
	source      string
	maeSeconds  float64
	samples     int
}

// aggregateMAE computes mean absolute error (|predicted - actual| seconds) per
// route per source. Results are sorted by route then source for a stable,
// scannable log. An empty input yields an empty slice.
func aggregateMAE(errs []matchedError) []maeStat {
	type acc struct {
		sumAbs float64
		n      int
	}
	buckets := make(map[maeKey]*acc)
	for _, e := range errs {
		k := maeKey{subRouteUID: e.subRouteUID, source: e.source}
		a := buckets[k]
		if a == nil {
			a = &acc{}
			buckets[k] = a
		}
		a.sumAbs += math.Abs(float64(e.predictedSecs - e.actualSecs))
		a.n++
	}
	out := make([]maeStat, 0, len(buckets))
	for k, a := range buckets {
		mae := 0.0
		if a.n > 0 {
			mae = a.sumAbs / float64(a.n)
		}
		out = append(out, maeStat{subRouteUID: k.subRouteUID, source: k.source, maeSeconds: mae, samples: a.n})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].subRouteUID != out[j].subRouteUID {
			return out[i].subRouteUID < out[j].subRouteUID
		}
		return out[i].source < out[j].source
	})
	return out
}

// measurePredictionError is the daily cron body. It loads the last day's
// predictions and observed arrivals from bus_eta_prediction_error /
// bus_eta_history, fills in actuals for still-open predictions, and logs MAE per
// route per source. It is measurement only — no dashboard, just numbers in the
// log. Query failures are wrapped transient so runDaily retries.
func measurePredictionError(ctx context.Context, db *pgxpool.Pool) error {
	log.Infof("[ETA_ERROR] start")

	// Fill actual arrivals for predictions still missing one, by matching each to
	// the first estimate-zero crossing at its stop after the prediction was made.
	// One correlated UPDATE keeps the match logic in SQL (the pure matcher above
	// covers the same rule and is unit-tested); the 30-minute window bounds it.
	tag, err := db.Exec(ctx, `
		UPDATE bus_eta_prediction_error pe
		SET actual_seconds = sub.actual_seconds
		FROM (
			SELECT pe2.id,
			       EXTRACT(EPOCH FROM MIN(h.recorded_at) - pe2.predicted_at)::int AS actual_seconds
			FROM bus_eta_prediction_error pe2
			JOIN bus_eta_history h
			  ON h.sub_route_uid = pe2.sub_route_uid
			 AND h.direction     = pe2.direction
			 AND h.stop_uid      = pe2.stop_uid
			 AND h.recorded_at   >= pe2.predicted_at
			 AND h.recorded_at   <= pe2.predicted_at + INTERVAL '30 minutes'
			 AND h.estimate      <= 0
			WHERE pe2.actual_seconds IS NULL
			  AND pe2.predicted_at >= NOW() - INTERVAL '1 day'
			GROUP BY pe2.id, pe2.predicted_at
		) sub
		WHERE pe.id = sub.id`)
	if err != nil {
		log.Infof("[ETA_ERROR] fill actuals error: %v", err)
		return obs.Transient(fmt.Errorf("fill prediction actuals: %w", err))
	}
	log.Infof("[ETA_ERROR] filled %d actuals", tag.RowsAffected())

	rows, err := db.Query(ctx, `
		SELECT sub_route_uid, source,
		       AVG(ABS(predicted_seconds - actual_seconds))::float AS mae,
		       COUNT(*) AS samples
		FROM bus_eta_prediction_error
		WHERE actual_seconds IS NOT NULL
		  AND predicted_at >= NOW() - INTERVAL '1 day'
		GROUP BY sub_route_uid, source
		ORDER BY sub_route_uid, source`)
	if err != nil {
		log.Infof("[ETA_ERROR] aggregate query error: %v", err)
		return obs.Transient(fmt.Errorf("aggregate prediction error: %w", err))
	}
	defer rows.Close()
	count := 0
	for rows.Next() {
		var sub, source string
		var mae float64
		var samples int
		if err := rows.Scan(&sub, &source, &mae, &samples); err != nil {
			log.Infof("[ETA_ERROR] scan error: %v", err)
			continue
		}
		log.Infof("[ETA_ERROR] sub_route=%s source=%s mae_seconds=%.1f samples=%d", sub, source, mae, samples)
		count++
	}
	if err := rows.Err(); err != nil {
		log.Infof("[ETA_ERROR] aggregate rows error: %v", err)
		return obs.Transient(fmt.Errorf("aggregate prediction error: %w", err))
	}
	log.Infof("[ETA_ERROR] complete groups=%d", count)
	return nil
}

// recordPredictionErrors bulk-inserts freshly made predictions (actual pending)
// into bus_eta_prediction_error, so a later measurePredictionError run can match
// them to observed arrivals. An empty batch is a no-op; an insert error is
// logged, not returned — measurement must never break the live ETA path.
func recordPredictionErrors(ctx context.Context, db *pgxpool.Pool, preds []predictionRecord) {
	if len(preds) == 0 {
		return
	}
	rows := make([][]interface{}, 0, len(preds))
	for _, p := range preds {
		rows = append(rows, []interface{}{
			p.subRouteUID, p.direction, p.stopUID, p.source, p.predictedAt, p.predictedSecs,
		})
	}
	cols := []string{"sub_route_uid", "direction", "stop_uid", "source", "predicted_at", "predicted_seconds"}
	_, err := db.CopyFrom(ctx, pgx.Identifier{"bus_eta_prediction_error"}, cols, pgx.CopyFromRows(rows))
	if err != nil {
		log.Infof("[ETA_ERROR] insert predictions error: %v rows=%d", err, len(rows))
	}
}
