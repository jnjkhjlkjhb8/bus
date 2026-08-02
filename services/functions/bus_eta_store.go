package main

import (
	"context"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type busEtaStore interface {
	staticStops(context.Context, string) ([]busStationmap, error)
	nextDepartures(context.Context, []routeDirKey, string, int) map[routeDirKey]time.Time
	stopOffsets(context.Context, []string) map[stopOffsetKey]int
	saveHistory(context.Context, [][]any)
	recordPredictions(context.Context, []predictionRecord)
}

type pgBusEtaStore struct {
	db *pgxpool.Pool
}

func (s pgBusEtaStore) staticStops(ctx context.Context, prefix string) ([]busStationmap, error) {
	return busstaticmp(ctx, s.db, prefix)
}

func (s pgBusEtaStore) nextDepartures(ctx context.Context, keys []routeDirKey, todTime string, dayBit int) map[routeDirKey]time.Time {
	return batchNextDepartures(ctx, s.db, keys, todTime, dayBit)
}

func (s pgBusEtaStore) stopOffsets(ctx context.Context, uids []string) map[stopOffsetKey]int {
	return batchStopOffsets(ctx, s.db, uids)
}

// History and prediction rows record a tick that has already been published, and
// nothing downstream waits on them. Running them inline on the live tick's
// context is where two symptoms came from: the bus tick spends ~22 s of its 25 s
// budget on TDX, so these writes ran last and died mid-batch on "context
// deadline exceeded", and the seconds they did spend came out of the budget the
// remaining cities needed to fetch at all.
//
// They go to a bounded background flusher instead — their own deadline, off the
// tick's clock. The queue is deliberately shallow: a database that cannot keep
// up should drop batches loudly rather than accumulate a backlog of rows that
// are staler than the ones behind them.
const (
	busEtaFlushTimeout = 60 * time.Second
	busEtaFlushDepth   = 8
	busEtaFlushWorkers = 2
)

type busEtaFlush struct {
	table string
	rows  int
	write func(context.Context)
}

type busEtaFlusher struct {
	queue   chan busEtaFlush
	workers int
	timeout time.Duration
	start   sync.Once
}

var busEtaFlushes = &busEtaFlusher{
	queue:   make(chan busEtaFlush, busEtaFlushDepth),
	workers: busEtaFlushWorkers,
	timeout: busEtaFlushTimeout,
}

// submit hands one batch to the flusher, dropping it when the queue is full.
// Workers start on first use so a process that never writes history never spawns
// them (and a test can hold the queue still by declaring zero workers).
func (f *busEtaFlusher) submit(task busEtaFlush) {
	f.start.Do(func() {
		for range f.workers {
			go func() {
				for t := range f.queue {
					ctx, cancel := context.WithTimeout(context.Background(), f.timeout)
					t.write(ctx)
					cancel()
				}
			}()
		}
	})
	select {
	case f.queue <- task:
	default:
		log.Warnf("[BUS_ETA] action=flush event=dropped table=%s rows=%d reason=queue_full", task.table, task.rows)
	}
}

// The caller's context is deliberately unused: it is the live tick's, and
// outliving it is the whole point (see busEtaFlusher).
func (s pgBusEtaStore) saveHistory(_ context.Context, rows [][]any) {
	if len(rows) == 0 {
		return
	}
	target := archiveTarget()
	busEtaFlushes.submit(busEtaFlush{table: "bus_eta_history", rows: len(rows), write: func(ctx context.Context) {
		saveBusEtaHistory(ctx, target, rows)
	}})
}

func (s pgBusEtaStore) recordPredictions(_ context.Context, rows []predictionRecord) {
	if len(rows) == 0 {
		return
	}
	db := s.db
	busEtaFlushes.submit(busEtaFlush{table: "bus_eta_prediction_error", rows: len(rows), write: func(ctx context.Context) {
		recordPredictionErrors(ctx, db, rows)
	}})
}
