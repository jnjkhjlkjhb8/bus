package main

import (
	"context"
	"math"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
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

// saveBusEtaHistory bulk-COPYs collected ETA observations into bus_eta_history,
// the training data behind travel averages and the ETA model. The column order
// must match the row order built in processBusEtaCity. An empty batch is a no-op;
// a copy error is logged, not returned.
func saveBusEtaHistory(ctx context.Context, db *pgxpool.Pool, rows [][]interface{}) {
	if len(rows) == 0 {
		return
	}
	cols := []string{
		"sub_route_uid", "stop_uid", "direction", "stop_sequence", "total_stops",
		"estimate", "next_bus_time", "src_update_time", "city", "hour", "day_of_week",
		"is_holiday", "temperature", "precipitation", "wind_speed", "humidity",
		"plate_numb", "bus_speed", "bus_distance_m",
	}
	_, err := db.CopyFrom(ctx, pgx.Identifier{"bus_eta_history"}, cols, pgx.CopyFromRows(rows))
	if err != nil {
		log.Errorf("[ETA_HISTORY] copy error: %v rows=%d", err, len(rows))
	} else {
		log.Infof("[ETA_HISTORY] inserted %d rows", len(rows))
	}
}
