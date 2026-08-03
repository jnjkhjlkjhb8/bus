package main

import (
	"context"
	"fmt"
	"math"
	"time"

	"go.uber.org/zap"
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

// historySnapshotInterval is how often a full ETA snapshot is recorded, and
// busEtaTickInterval is the bus ETA cron's own cadence (live.go, "@every 30s").
//
// The bulk rows have one reader, segmentsByEstimate, and it differences adjacent
// stops inside a single snapshot: it needs whole snapshots, not a dense series of
// them. TDX reports StopStatus 0 for a median of 32 consecutive stops, so one
// snapshot of a running route already yields nearly all its hops
// (segment_time_eta.go), and a 14-day window still holds ~2,000 snapshots per
// route direction where the median wants a handful.
//
// Recording every tick instead produced ~217M rows a day against the ~197k this
// table was sized for. Four fifths were dropped at the flusher queue, and the
// process spent its single CPU building rows it then threw away — starving the
// live path in the same goroutine budget.
const (
	historySnapshotInterval = 10 * time.Minute
	busEtaTickInterval      = 30 * time.Second
)

// snapshotTick reports whether the tick starting at now records a full snapshot.
//
// It is evaluated once per job run rather than per city: cities run
// concurrently and each would otherwise read its own clock, so a tick firing
// near the boundary would record some cities and not others, and
// segmentsByEstimate would difference a snapshot that never existed whole.
func snapshotTick(now time.Time) bool {
	return now.Unix()%int64(historySnapshotInterval.Seconds()) < int64(busEtaTickInterval.Seconds())
}

// recordsHistory reports whether one stop's reading belongs in bus_eta_history.
//
// Arrivals ride at full density regardless of the snapshot clock. They are what
// measurePredictionError matches a prediction against, and matchPredictionActual
// takes the first arrival within 30 minutes — so a missing one is not a lost
// sample but a prediction silently scored against the next bus. They are also
// cheap: adjustedEstimate only reads zero inside busEtaArrivingGrace of the
// arrival instant, so this covers a few ticks per approach rather than all of it.
func recordsHistory(estimate int32, snapshot bool) bool {
	return estimate <= 0 || snapshot
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
		zap.S().Errorw("insert error", "component", "eta_history", "rows", len(rows), "err", err)
		return
	}
	zap.S().Infow(fmt.Sprintf("inserted %d rows", len(rows)), "component", "eta_history")
}
