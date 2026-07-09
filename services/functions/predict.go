package main

import (
	"context"
	"encoding/json"
	"os"
	"strings"
	"time"

	"github.com/dmitryikh/leaves"
	"github.com/jackc/pgx/v5/pgxpool"
)

// routeDirKey identifies one subroute direction, used as a map key when batching
// next-departure and travel-average lookups.
type routeDirKey struct {
	subRouteUID string
	direction   int32
}

// travelAvgKey identifies a per-stop, time-bucketed travel-average sample:
// subroute, direction, stop, hour of day, and day of week.
type travelAvgKey struct {
	subRouteUID string
	direction   int32
	stopUID     string
	hour        int
	dayOfWeek   int
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
		log.Infof("[MODEL] batchNextDepartures error: %v", err)
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
	for k, v := range best {
		out[k] = v.dep
	}
	return out
}

// batchTravelAvg loads precomputed average travel seconds (origin to each stop)
// for the given subroutes at a specific hour and day of week, in one query. The
// result feeds ETA prediction the expected time from departure to a stop. An
// empty uid set or a query error yields an empty map.
func batchTravelAvg(ctx context.Context, db *pgxpool.Pool, uids []string, hour, dayOfWeek int) map[travelAvgKey]int {
	out := make(map[travelAvgKey]int)
	if len(uids) == 0 {
		return out
	}
	rows, err := db.Query(ctx, `
		SELECT sub_route_uid, direction, stop_uid, avg_seconds
		FROM bus_travel_avg
		WHERE hour = $2 AND day_of_week = $3
		  AND sub_route_uid = ANY($1::text[])`,
		uids, hour, dayOfWeek)
	if err != nil {
		log.Infof("[MODEL] batchTravelAvg error: %v", err)
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var uid, stop string
		var dir int32
		var sec int
		if err := rows.Scan(&uid, &dir, &stop, &sec); err == nil {
			out[travelAvgKey{subRouteUID: uid, direction: dir, stopUID: stop, hour: hour, dayOfWeek: dayOfWeek}] = sec
		}
	}
	return out
}

// etaModel is the loaded XGBoost ensemble that predicts a residual correction on
// the schedule+travel-average ETA. It stays nil when no model file is present,
// which disables prediction (predictNextBusTime returns "").
var etaModel *leaves.Ensemble

// modelEncoders holds the categorical-to-integer encodings the model was trained
// with, so runtime features match training. Only City is currently applied;
// PlateNumb is loaded but unused at prediction time.
var modelEncoders struct {
	City      map[string]int `json:"city"`
	PlateNumb map[string]int `json:"plate_numb"`
}

// loadModel loads the XGBoost ETA model and its encoders from BUS_ETA_MODEL_PATH
// (default ./model/bus_eta.json, encoders at <path>_encoders.json). A missing or
// unreadable model leaves etaModel nil and disables prediction — this is a
// tolerated state, not a fatal error, so the service runs without the model.
func loadModel() {
	path := os.Getenv("BUS_ETA_MODEL_PATH")
	if path == "" {
		path = "./model/bus_eta.json"
	}
	m, err := leaves.XGEnsembleFromFile(path, true)
	if err != nil {
		log.Infof("[MODEL] not loaded (file: %s): %v", path, err)
		return
	}
	encPath := strings.TrimSuffix(path, ".json") + "_encoders.json"
	encData, err := os.ReadFile(encPath)
	if err != nil {
		log.Infof("[MODEL] encoders not found at %s: %v", encPath, err)
	} else {
		json.Unmarshal(encData, &modelEncoders)
	}
	etaModel = m
	log.Infof("[MODEL] loaded from %s", path)
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
// the next scheduled departure, and the travel-average signal (its value, whether
// one exists for this exact stop, and the route's max as a fallback basis).
type predictionInputs struct {
	now          time.Time
	nextDep      time.Time
	travelAvg    int
	hasTravelAvg bool
	maxTravelAvg int
}

// baselineArrival computes the schedule+travel-average arrival for a stop, with
// no model correction: today's scheduled departure plus expected travel seconds.
// When no per-stop travel average exists it interpolates from the route's max
// average by stop-sequence ratio; if even that is unavailable (maxTravelAvg == 0)
// it returns the bare departure. It returns the zero time when there is no
// upcoming scheduled departure. This is the delay-propagation baseline and the
// pre-correction basis inside predictNextBusTime.
func baselineArrival(stop busStopCtx, inputs predictionInputs) time.Time {
	if inputs.nextDep.IsZero() {
		return time.Time{}
	}
	t := inputs.now.In(taipei)
	dep := time.Date(t.Year(), t.Month(), t.Day(),
		inputs.nextDep.Hour(), inputs.nextDep.Minute(), inputs.nextDep.Second(), 0, taipei)
	travelSec := inputs.travelAvg
	if !inputs.hasTravelAvg {
		if inputs.maxTravelAvg == 0 {
			return dep
		}
		ratio := 0.0
		if stop.totalStops > 0 {
			ratio = float64(stop.stopSequence) / float64(stop.totalStops)
		}
		travelSec = int(ratio * float64(inputs.maxTravelAvg))
	}
	return dep.Add(time.Duration(travelSec) * time.Second)
}

// predictNextBusTime estimates a NextBusTime for a stop TDX left blank. It bases
// the estimate on the next scheduled departure plus expected travel time, then
// adds the XGBoost residual correction. When no per-stop travel average exists it
// interpolates from the route's max average by stop-sequence ratio; if even that
// is unavailable it falls back to the bare departure time. Returns "" when the
// model is not loaded or there is no upcoming scheduled departure. Result is an
// RFC3339 timestamp.
func predictNextBusTime(weather *weatherData, stop busStopCtx, inputs predictionInputs) string {
	if etaModel == nil || inputs.nextDep.IsZero() {
		return ""
	}
	t := inputs.now.In(taipei)
	dep := time.Date(t.Year(), t.Month(), t.Day(),
		inputs.nextDep.Hour(), inputs.nextDep.Minute(), inputs.nextDep.Second(), 0, taipei)
	travelSec := inputs.travelAvg
	ratio := 0.0
	if stop.totalStops > 0 {
		ratio = float64(stop.stopSequence) / float64(stop.totalStops)
	}
	if !inputs.hasTravelAvg {
		if inputs.maxTravelAvg == 0 {
			return dep.Format(time.RFC3339)
		}
		travelSec = int(ratio * float64(inputs.maxTravelAvg))
	}
	// The caller passes the city's cached weather snapshot (read once per city
	// through the live sink); a nil snapshot leaves the features zero-valued.
	var wd weatherData
	if weather != nil {
		wd = *weather
	}
	cityEnc := -1.0
	if v, ok := modelEncoders.City[stop.city]; ok {
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
	correction := etaModel.PredictSingle(features, 0)
	eta := dep.Add(time.Duration(travelSec)*time.Second + time.Duration(correction)*time.Second)
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
