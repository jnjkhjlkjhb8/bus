package main

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
	"go.uber.org/zap"
)

// bikeHistorySampleInterval is the minimum spacing between persisted history
// rows for a single station. The bikeEta cron runs every 30s, but availability
// changes slowly, so history is sampled once per 5 minutes per station to keep
// the table small while still capturing the daily/weekly demand shape needed for
// future rentable/returnable prediction.
const bikeHistorySampleInterval = 5 * time.Minute

// bikeHistorySampler decides, per station, whether enough time has elapsed since
// the last persisted sample to record another. It is the 5-minute sampling gate
// that keeps bikeEta from writing a history row on every 30s round. The zero
// value is ready to use and safe for concurrent access.
type bikeHistorySampler struct {
	mu   sync.Mutex
	last map[string]time.Time
}

// shouldSample reports whether stationUID should be persisted at now, and if so
// records now as its latest sample time. The first observation of a station
// always samples; subsequent ones only sample once bikeHistorySampleInterval has
// passed since the previous accepted sample.
func (s *bikeHistorySampler) shouldSample(stationUID string, now time.Time) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.last == nil {
		s.last = make(map[string]time.Time)
	}
	prev, seen := s.last[stationUID]
	if seen && now.Sub(prev) < bikeHistorySampleInterval {
		return false
	}
	s.last[stationUID] = now
	return true
}

// saveBikeAvailabilityHistory bulk-COPYs sampled availability observations into
// bike_availability_history, the training data behind future rentable/returnable
// prediction. An empty batch is a no-op; a copy error is logged, not returned,
// so a failed history write never disrupts the realtime Redis path.
func saveBikeAvailabilityHistory(ctx context.Context, db *pgxpool.Pool, rows [][]any) {
	if len(rows) == 0 {
		return
	}
	cols := []string{"station_uid", "available_rent", "available_return", "recorded_at"}
	_, err := db.CopyFrom(ctx, pgx.Identifier{"bike_availability_history"}, cols, pgx.CopyFromRows(rows))
	if err != nil {
		zap.S().Errorw("copy error", "component", "bike_history", "rows", len(rows), "err", err)
	} else {
		zap.S().Infow(fmt.Sprintf("inserted %d rows", len(rows)), "component", "bike_history")
	}
}

// cleanupBikeHistory deletes bike_availability_history rows older than 30 days
// (the retention window), mirroring cleanupBusHistory. A failure is wrapped as
// transient so runDaily retries it.
func cleanupBikeHistory(ctx context.Context, db *pgxpool.Pool) error {
	tag, err := db.Exec(ctx, `DELETE FROM bike_availability_history WHERE recorded_at < NOW() - INTERVAL '30 days'`)
	if err != nil {
		return obs.Transient(fmt.Errorf("cleanup bike history: %w", err))
	}
	zap.S().Infow(fmt.Sprintf("cleanup deleted %d rows", tag.RowsAffected()), "component", "bike_history")
	return nil
}
