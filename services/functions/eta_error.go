package main

import (
	"context"
	"fmt"
	"math"
	"sort"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
	"go.uber.org/zap"
)

// predictionSource labels which prediction tier produced an ETA, so accuracy can
// be compared tier by tier. Values match the source column of
// bus_eta_prediction_error.
const (
	sourceTDX         = "tdx"
	sourcePropagation = "propagation"
	sourceModel       = "model"
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

// predictionMatchWindow bounds how long after a prediction an arrival may occur
// and still be treated as the arrival that prediction was about.
const predictionMatchWindow = 30 * time.Minute

// predictionLookback is how far back measurePredictionError considers still-open
// predictions, and therefore how much arrival history it needs to load.
const predictionLookback = 24 * time.Hour

// loadOpenPredictions reads predictions from the last day that have no actual
// yet. Postgres owns bus_eta_prediction_error; only the arrivals moved.
func loadOpenPredictions(ctx context.Context, db *pgxpool.Pool) ([]predictionRecord, error) {
	rows, err := db.Query(ctx, `
		SELECT sub_route_uid, direction, stop_uid, source, predicted_at, predicted_seconds
		FROM bus_eta_prediction_error
		WHERE actual_seconds IS NULL AND predicted_at >= NOW() - INTERVAL '1 day'`)
	if err != nil {
		return nil, fmt.Errorf("query open predictions: %w", err)
	}
	defer rows.Close()
	var out []predictionRecord
	for rows.Next() {
		var p predictionRecord
		if err := rows.Scan(&p.subRouteUID, &p.direction, &p.stopUID, &p.source,
			&p.predictedAt, &p.predictedSecs); err != nil {
			return nil, fmt.Errorf("scan open prediction: %w", err)
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// writePredictionActuals fills actual_seconds for every matched prediction in
// one statement. The rows are addressed by their natural key rather than by id,
// which the matcher does not carry; source is part of that key because two
// prediction tiers can describe the same stop at the same instant.
func writePredictionActuals(ctx context.Context, db *pgxpool.Pool, matched []matchedError) (int64, error) {
	if len(matched) == 0 {
		return 0, nil
	}
	uids := make([]string, len(matched))
	dirs := make([]int16, len(matched))
	stops := make([]string, len(matched))
	sources := make([]string, len(matched))
	at := make([]time.Time, len(matched))
	actual := make([]int32, len(matched))
	for i, m := range matched {
		uids[i], dirs[i], stops[i] = m.subRouteUID, m.direction, m.stopUID
		sources[i], at[i], actual[i] = m.source, m.predictedAt, int32(m.actualSecs)
	}
	tag, err := db.Exec(ctx, `
		UPDATE bus_eta_prediction_error pe
		SET actual_seconds = v.actual_seconds
		FROM unnest($1::text[], $2::smallint[], $3::text[], $4::text[],
		            $5::timestamptz[], $6::int[])
		       AS v(sub_route_uid, direction, stop_uid, source, predicted_at, actual_seconds)
		WHERE pe.sub_route_uid = v.sub_route_uid
		  AND pe.direction     = v.direction
		  AND pe.stop_uid      = v.stop_uid
		  AND pe.source        = v.source
		  AND pe.predicted_at  = v.predicted_at
		  AND pe.actual_seconds IS NULL`,
		uids, dirs, stops, sources, at, actual)
	if err != nil {
		return 0, fmt.Errorf("write prediction actuals: %w", err)
	}
	return tag.RowsAffected(), nil
}

// fillPredictionActuals pairs still-open predictions with the arrivals they
// predicted and writes the results back. A disabled history host leaves the
// predictions open for a later run rather than failing the job.
func fillPredictionActuals(ctx context.Context, db *pgxpool.Pool, hist historySource) (int64, error) {
	if hist == nil {
		zap.S().Warnw("skipped fill", "component", "eta_error", "event", "skipped_fill", "reason", "history_disabled")
		return 0, nil
	}
	preds, err := loadOpenPredictions(ctx, db)
	if err != nil {
		return 0, obs.Transient(fmt.Errorf("load open predictions: %w", err))
	}
	if len(preds) == 0 {
		return 0, nil
	}
	arrivals, err := hist.arrivals(ctx, time.Now().Add(-predictionLookback))
	if err != nil {
		return 0, obs.Transient(fmt.Errorf("load history arrivals: %w", err))
	}
	n, err := writePredictionActuals(ctx, db, matchPredictionActual(preds, arrivals, predictionMatchWindow))
	if err != nil {
		return 0, obs.Transient(fmt.Errorf("fill prediction actuals: %w", err))
	}
	return n, nil
}

// measurePredictionError is the daily cron body. It loads the last day's
// predictions from bus_eta_prediction_error (Postgres) and observed arrivals
// from bus_eta_history (the MySQL history host), fills in actuals for
// still-open predictions, and logs MAE per route per source. It is measurement
// only — no dashboard, just numbers in the log. Query failures are wrapped
// transient so runDaily retries.
func measurePredictionError(ctx context.Context, db *pgxpool.Pool, hist historySource) error {
	zap.S().Infow("start", "component", "eta_error")

	// Fill actual arrivals for predictions still missing one, by matching each to
	// the first estimate-zero crossing at its stop after the prediction was made.
	// bus_eta_history lives on the MySQL history host, so the two sides cannot be
	// joined in one correlated UPDATE: they are loaded separately and paired by
	// matchPredictionActual, which encodes the same rule in Go and is unit-tested.
	filled, err := fillPredictionActuals(ctx, db, hist)
	if err != nil {
		return err
	}
	zap.S().Infow(fmt.Sprintf("filled %d actuals", filled), "component", "eta_error")

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
		return obs.Transient(fmt.Errorf("aggregate prediction error: %w", err))
	}
	defer rows.Close()
	count := 0
	for rows.Next() {
		var sub, source string
		var mae float64
		var samples int
		if err := rows.Scan(&sub, &source, &mae, &samples); err != nil {
			zap.S().Errorw(fmt.Sprintf("scan error: %v", err), "component", "eta_error")
			continue
		}
		zap.S().Infow("log",
			"component", "eta_error",
			"sub_route", sub,
			"source", source,
			"mae_seconds", mae,
			"samples", samples,
		)
		count++
	}
	if err := rows.Err(); err != nil {
		return obs.Transient(fmt.Errorf("aggregate prediction error rows: %w", err))
	}
	zap.S().Infow("complete", "component", "eta_error", "groups", count)
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
	rows := make([][]any, 0, len(preds))
	for _, p := range preds {
		rows = append(rows, []any{
			p.subRouteUID, p.direction, p.stopUID, p.source, p.predictedAt, p.predictedSecs,
		})
	}
	cols := []string{"sub_route_uid", "direction", "stop_uid", "source", "predicted_at", "predicted_seconds"}
	_, err := db.CopyFrom(ctx, pgx.Identifier{"bus_eta_prediction_error"}, cols, pgx.CopyFromRows(rows))
	if err != nil {
		zap.S().Errorw("insert predictions error", "component", "eta_error", "rows", len(rows), "err", err)
	}
}
