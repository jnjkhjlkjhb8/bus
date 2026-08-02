package main

import (
	"context"
	"math"
)

// haversine returns the great-circle distance in meters between two lat/lon
// points, used to pick the nearest live vehicle to a stop.
func haversine(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371000
	φ1 := lat1 * math.Pi / 180
	φ2 := lat2 * math.Pi / 180
	dφ := (lat2 - lat1) * math.Pi / 180
	dλ := (lon2 - lon1) * math.Pi / 180
	a := math.Sin(dφ/2)*math.Sin(dφ/2) + math.Cos(φ1)*math.Cos(φ2)*math.Sin(dλ/2)*math.Sin(dλ/2)
	return 2 * R * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}

// busEtaHistoryCols is bus_eta_history's insert column list, in the order
// processBusEtaCity builds each row. id is auto-assigned by MySQL and absent
// here; recorded_at is supplied explicitly rather than defaulted, so every row
// in a batch carries the job's own instant instead of the MySQL server's clock
// and session time zone.
var busEtaHistoryCols = []string{
	"sub_route_uid", "stop_uid", "direction", "stop_sequence", "total_stops",
	"estimate", "next_bus_time", "src_update_time", "city", "hour", "day_of_week",
	"is_holiday", "temperature", "precipitation", "wind_speed", "humidity",
	"plate_numb", "bus_speed", "bus_distance_m", "recorded_at",
}

// saveBusEtaHistory appends collected ETA observations to bus_eta_history on the
// MySQL history host, the training data behind segment times and the ETA
// model. An empty batch is a no-op; an insert error is logged, not returned, so
// a history write can never disrupt the realtime Redis path. Those rows are then
// lost rather than retried — Postgres holds no copy to re-read, which is the
// accepted cost of keeping ~200k rows a day off the 2 GB Azure server.
func saveBusEtaHistory(ctx context.Context, db archiveExecer, rows [][]any) {
	if len(rows) == 0 {
		return
	}
	if err := archiveInsert(ctx, db, "bus_eta_history", busEtaHistoryCols, rows); err != nil {
		log.Errorf("[ETA_HISTORY] insert error: %v rows=%d", err, len(rows))
		return
	}
	log.Infof("[ETA_HISTORY] inserted %d rows", len(rows))
}
