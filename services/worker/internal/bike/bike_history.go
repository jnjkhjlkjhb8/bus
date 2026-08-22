package bike

import (
	"context"
	"sync"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/history"
	"go.uber.org/zap"
)

// _bikeHistorySampleInterval is the minimum spacing between persisted history
// rows for a single station. The Eta cron runs every 30s, but availability
// changes slowly, so history is sampled once per 5 minutes per station to keep
// the table small while still capturing the daily/weekly demand shape needed for
// future rentable/returnable prediction.
const _bikeHistorySampleInterval = 5 * time.Minute

// bikeHistorySampler decides, per station, whether enough time has elapsed since
// the last persisted sample to record another. It is the 5-minute sampling gate
// that keeps Eta from writing a history row on every 30s round. The zero
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
	if seen && now.Sub(prev) < _bikeHistorySampleInterval {
		return false
	}
	s.last[stationUID] = now
	return true
}

// _bikeHistoryCols is the column order saveBikeAvailabilityHistory binds, and
// must match the row shape Eta builds.
var _bikeHistoryCols = []string{"station_uid", "available_rent", "available_return", "recorded_at"}

// saveBikeAvailabilityHistory appends sampled availability observations to
// bike_availability_history on the MySQL archive host, the training data behind
// future rentable/returnable prediction.
//
// It lived on PostgreSQL under a 30-day retention job until the cutover the
// creating migration described but never performed (ADR-0023): the table has no
// online reader, so it was spending space on the 2 GB Azure server and throwing
// away eleven months of every year for nothing. It is now kept indefinitely, at
// ~11.5 MB/day.
//
// An empty batch is a no-op; an insert error is logged, not returned, so a
// failed history write never disrupts the realtime Redis path.
func saveBikeAvailabilityHistory(ctx context.Context, db history.Execer, rows [][]any) {
	if db == nil || len(rows) == 0 {
		return
	}
	if err := history.Insert(ctx, db, "bike_availability_history", _bikeHistoryCols, rows); err != nil {
		zap.S().Errorw("insert error", "component", "bike_history", "rows", len(rows), "err", err)
		return
	}
	zap.S().Infow("inserted rows", "component", "bike_history", "rows", len(rows))
}
