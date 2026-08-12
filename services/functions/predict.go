package main

import (
	"context"
	"encoding/json"
	"os"
	"strings"
	"time"

	"github.com/dmitryikh/leaves"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

// routeDirKey identifies one subroute direction, used as a map key when batching
// next-departure and stop-offset lookups.
type routeDirKey struct {
	subRouteUID string
	direction   int32
}

// stopOffsetKey identifies one stop's running-time offset from its subroute's
// origin: subroute, direction, stop.
type stopOffsetKey struct {
	subRouteUID string
	direction   int32
	stopUID     string
}

// dedupRouteDirPairs removes duplicate route/direction keys while preserving
// first-seen order, so the batched departure query does not repeat pairs.
func dedupRouteDirPairs(keys []routeDirKey) []routeDirKey {
	seen := make(map[routeDirKey]bool, len(keys))
	out := make([]routeDirKey, 0, len(keys))
	for _, k := range keys {
		if !seen[k] {
			seen[k] = true
			out = append(out, k)
		}
	}
	return out
}

// batchNextDepartures returns, per route/direction, the next scheduled
// departure at or after todTime (today's local time-of-day), considering only
// rows whose service_day mask includes dayBit. Timetable rows (type=false)
// contribute their trip's origin-stop time; frequency rows (type=true) have no
// per-trip departures, so an open service window contributes the window start
// clamped to now. Timetable wins over frequency when both exist. An empty key
// set or a query error yields an empty map.
func batchNextDepartures(ctx context.Context, db *pgxpool.Pool, keys []routeDirKey, todTime string, dayBit int) map[routeDirKey]time.Time {
	out := make(map[routeDirKey]time.Time, len(keys))
	if len(keys) == 0 {
		return out
	}
	uids := make([]string, len(keys))
	dirs := make([]int32, len(keys))
	for i, k := range keys {
		uids[i] = k.subRouteUID
		dirs[i] = k.direction
	}
	rows, err := db.Query(ctx, `
		WITH wanted(sub_route_uid, direction) AS (
			SELECT unnest($1::text[]), unnest($2::int[])
		),
		origin AS (
			SELECT DISTINCT ON (b.sub_route_uid, b.direction, b.tripid)
			       b.sub_route_uid, b.direction, b."arrival_time/StartTime" AS dep
			FROM bus_schedule b
			JOIN wanted w ON b.sub_route_uid = w.sub_route_uid AND b.direction = w.direction
			WHERE b.type = false AND (b.service_day & $4) <> 0
			ORDER BY b.sub_route_uid, b.direction, b.tripid, b.stopsequence
		)
		SELECT sub_route_uid, direction, dep, 0 AS prio FROM (
			SELECT sub_route_uid, direction, MIN(dep) AS dep
			FROM origin WHERE dep >= $3::time
			GROUP BY sub_route_uid, direction
		) tt
		UNION ALL
		SELECT b.sub_route_uid, b.direction,
		       MIN(GREATEST(b."arrival_time/StartTime", $3::time)) AS dep, 1 AS prio
		FROM bus_schedule b
		JOIN wanted w ON b.sub_route_uid = w.sub_route_uid AND b.direction = w.direction
		WHERE b.type = true AND (b.service_day & $4) <> 0
		  AND b."departure_time/EndTime" >= $3::time
		GROUP BY b.sub_route_uid, b.direction`,
		uids, dirs, todTime, dayBit)
	if err != nil {
		zap.S().Errorw("batchNextDepartures error", "component", "model", "err", err)
		return out
	}
	defer rows.Close()
	type prioDep struct {
		dep  time.Time
		prio int
	}
	best := make(map[routeDirKey]prioDep, len(keys))
	for rows.Next() {
		var uid string
		var dir int32
		var dep time.Time
		var prio int
		if err := rows.Scan(&uid, &dir, &dep, &prio); err != nil {
			continue
		}
		k := routeDirKey{subRouteUID: uid, direction: dir}
		if cur, ok := best[k]; !ok || prio < cur.prio {
			best[k] = prioDep{dep: dep, prio: prio}
		}
	}
	if err := rows.Err(); err != nil {
		zap.S().Errorw("batchNextDepartures rows error", "component", "model", "err", err)
	}
	for k, v := range best {
		out[k] = v.dep
	}
	return out
}

// batchStopOffsets loads each stop's running seconds from its subroute's origin
// for the given subroutes, in one query. The result feeds ETA prediction the
// expected time from departure to a stop. An empty uid set or a query error
// yields an empty map.
//
// The offsets are accumulated from bus_segment_time, the observed running time
// between consecutive stops, over busPatternSQL — the same statement the GTFS
// export lays a trip out with, so a predicted arrival and a published stop time
// cannot disagree about the same journey.
//
// Only directions busPatternSQL calls complete are returned. Accumulating past
// an unobserved hop silently compresses every stop after it, so a direction
// missing one segment yields nothing and the caller falls back to the bare
// scheduled departure.
func batchStopOffsets(ctx context.Context, db *pgxpool.Pool, uids []string) map[stopOffsetKey]int {
	out := make(map[stopOffsetKey]int)
	if len(uids) == 0 {
		return out
	}
	missing := cachedStopOffsets(&_stopOffsetCache, uids, time.Now(), out)
	if len(missing) == 0 {
		return out
	}
	rows, err := db.Query(ctx, `
		SELECT p.sub_route_uid, p.direction, p.stop_uid, p.offset_secs
		FROM (`+_busPatternSQL+`) p
		WHERE p.complete AND p.sub_route_uid = ANY($1::text[])`,
		missing)
	if err != nil {
		zap.S().Errorw("batchStopOffsets error", "component", "model", "err", err)
		return out
	}
	defer rows.Close()
	// Every queried uid gets an entry, including the ones the query returns
	// nothing for. A direction busPatternSQL does not call complete is the common
	// case, not an error, and caching only the hits would leave those re-running
	// the statement on every tick — which is most of the cost being avoided.
	fetched := make(map[string][]stopOffset, len(missing))
	for _, uid := range missing {
		fetched[uid] = nil
	}
	for rows.Next() {
		var uid, stop string
		var dir int32
		var sec int
		if err := rows.Scan(&uid, &dir, &stop, &sec); err == nil {
			out[stopOffsetKey{subRouteUID: uid, direction: dir, stopUID: stop}] = sec
			fetched[uid] = append(fetched[uid], stopOffset{direction: dir, stopUID: stop, secs: sec})
		}
	}
	if err := rows.Err(); err != nil {
		// A partial read is not cached: the uids it covered would look complete
		// and stay that way for the whole TTL.
		zap.S().Errorw("batchStopOffsets rows error", "component", "model", "err", err)
		return out
	}
	storeStopOffsets(&_stopOffsetCache, fetched, time.Now())
	return out
}

// _predictor is the process-wide ETA model, built once at startup by
// newPredictor and never reassigned afterward. Tests that need a different
// model build their own local *predictor instead of mutating this one.
var _predictor *predictor

// predictor holds the loaded XGBoost ensemble that predicts a residual
// correction on the schedule+running-time ETA, and the categorical-to-integer
// encodings it was trained with, so runtime features match training. A nil
// *predictor, or one with a nil model, means no model is loaded, which
// disables prediction (predictNextBusTime returns ""). Only City is currently
// applied; PlateNumb is loaded but unused at prediction time.
type predictor struct {
	model    *leaves.Ensemble
	encoders struct {
		City      map[string]int `json:"city"`
		PlateNumb map[string]int `json:"plate_numb"`
	}
}

// newPredictor loads the XGBoost ETA model and its encoders from
// BUS_ETA_MODEL_PATH (default ./model/bus_eta.json, encoders at
// <path>_encoders.json). A missing or unreadable model yields a *predictor
// with a nil model, which disables prediction — this is a tolerated state, not
// a fatal error, so the service runs without the model.
func newPredictor() *predictor {
	path := os.Getenv("BUS_ETA_MODEL_PATH")
	if path == "" {
		path = "./model/bus_eta.json"
	}
	m, err := leaves.XGEnsembleFromFile(path, true /* loadTransformation */)
	if err != nil {
		zap.S().Infow("not loaded", "component", "model", "path", path, "err", err)
		return &predictor{}
	}
	p := &predictor{model: m}
	encPath := strings.TrimSuffix(path, ".json") + "_encoders.json"
	encData, err := os.ReadFile(encPath)
	if err != nil {
		zap.S().Infow("encoders not found", "component", "model", "path", encPath, "err", err)
	} else if err := json.Unmarshal(encData, &p.encoders); err != nil {
		zap.S().Infow("encoders parse failed", "component", "model", "path", encPath, "err", err)
	}
	zap.S().Infow("loaded", "component", "model", "path", path)
	return p
}

// busStopCtx describes the stop being predicted: its subroute/direction, the
// stop's position in the route (sequence out of total), and city.
type busStopCtx struct {
	subRouteUID  string
	direction    int32
	stopUID      string
	city         string
	stopSequence int
	totalStops   int
}

// predictionInputs carries the per-call inputs to prediction: the current time,
// the next scheduled departure, and the stop's running-time offset from the
// origin (its value, and whether one exists for this stop at all).
type predictionInputs struct {
	now       time.Time
	nextDep   time.Time
	offsetSec int
	hasOffset bool
}

// baselineArrival computes the schedule+running-time arrival for a stop, with no
// model correction: today's scheduled departure plus the stop's offset from the
// origin. Without an offset it returns the bare departure — the stop's direction
// has an unobserved hop somewhere, and a guessed offset would be worse than
// admitting the journey is unknown. It returns the zero time when there is no
// upcoming scheduled departure. This is the delay-propagation baseline and the
// pre-correction basis inside predictNextBusTime.
func baselineArrival(inputs predictionInputs) time.Time {
	if inputs.nextDep.IsZero() {
		return time.Time{}
	}
	t := inputs.now.In(_taipei)
	dep := time.Date(t.Year(), t.Month(), t.Day(),
		inputs.nextDep.Hour(), inputs.nextDep.Minute(), inputs.nextDep.Second(), 0, _taipei)
	if !inputs.hasOffset {
		return dep
	}
	return dep.Add(time.Duration(inputs.offsetSec) * time.Second)
}

// predictNextBusTime calls _predictor's method of the same name. It exists so
// callers elsewhere in the package do not need to reference the package-level
// predictor directly; the prediction logic itself lives on *predictor so tests
// can exercise it against a local instance instead of the shared global.
func predictNextBusTime(weather *weatherData, stop busStopCtx, inputs predictionInputs) string {
	return _predictor.predictNextBusTime(weather, stop, inputs)
}

// predictNextBusTime estimates a NextBusTime for a stop TDX left blank. It bases
// the estimate on the next scheduled departure plus the stop's running-time
// offset from the origin, then adds the XGBoost residual correction. Without an
// offset it falls back to the bare departure time, uncorrected: the correction is
// a residual on a journey estimate, and there is no journey estimate to correct.
// Returns "" when the model is not loaded (including a nil receiver, which
// happens before newPredictor has run) or there is no upcoming scheduled
// departure. Result is an RFC3339 timestamp.
func (p *predictor) predictNextBusTime(weather *weatherData, stop busStopCtx, inputs predictionInputs) string {
	if p == nil || p.model == nil || inputs.nextDep.IsZero() {
		return ""
	}
	t := inputs.now.In(_taipei)
	dep := time.Date(t.Year(), t.Month(), t.Day(),
		inputs.nextDep.Hour(), inputs.nextDep.Minute(), inputs.nextDep.Second(), 0, _taipei)
	if !inputs.hasOffset {
		return dep.Format(time.RFC3339)
	}
	ratio := 0.0
	if stop.totalStops > 0 {
		ratio = float64(stop.stopSequence) / float64(stop.totalStops)
	}
	// The caller passes the city's cached weather snapshot (read once per city
	// through the live sink); a nil snapshot leaves the features zero-valued.
	var wd weatherData
	if weather != nil {
		wd = *weather
	}
	cityEnc := -1.0
	if v, ok := p.encoders.City[stop.city]; ok {
		cityEnc = float64(v)
	}
	features := []float64{
		float64(t.Hour()),
		float64(t.Weekday()),
		boolToFloat64(isHoliday(t)),
		wd.Temperature,
		wd.Precipitation,
		wd.WindSpeed,
		wd.Humidity,
		float64(stop.direction),
		float64(stop.stopSequence),
		float64(stop.totalStops),
		ratio,
		cityEnc,
		-1,
		-1,
		-1,
	}
	correction := p.model.PredictSingle(features, 0)
	eta := dep.Add(time.Duration(inputs.offsetSec)*time.Second + time.Duration(correction)*time.Second)
	return eta.Format(time.RFC3339)
}

// boolToFloat64 maps true to 1 and false to 0 for encoding a boolean feature
// (the holiday flag) into the model's float feature vector.
func boolToFloat64(b bool) float64 {
	if b {
		return 1
	}
	return 0
}
