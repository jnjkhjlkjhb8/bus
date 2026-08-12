package main

import (
	"context"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

type busEtaStore interface {
	staticStops(context.Context, string) ([]busStationmap, error)
	nextDepartures(context.Context, []routeDirKey, string, int) map[routeDirKey]time.Time
	stopOffsets(context.Context, []string) map[stopOffsetKey]int
	saveHistory(context.Context, [][]any)
	saveStopEvents(context.Context, [][]any)
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

// The caller's context is deliberately unused: it is the live tick's, and
// outliving it is the whole point (see busEtaFlusher).
func (s pgBusEtaStore) saveHistory(_ context.Context, rows [][]any) {
	if len(rows) == 0 {
		return
	}
	target := archiveTarget()
	_busEtaFlushes.submit(busEtaFlush{table: "bus_eta_history", rows: len(rows), write: func(ctx context.Context) {
		saveBusEtaHistory(ctx, target, rows)
	}})
}

// saveStopEvents archives observed stop arrivals and departures (TDX A2). Same
// background flusher and same fire-and-forget contract as saveHistory: the rows
// describe a tick that has already been published, so a slow archive host must
// not spend the live tick's budget. The table's natural key makes the INSERT
// idempotent, which is what lets every tick re-submit the records TDX keeps
// republishing.
func (s pgBusEtaStore) saveStopEvents(_ context.Context, rows [][]any) {
	if len(rows) == 0 {
		return
	}
	target := archiveTarget()
	_busEtaFlushes.submit(busEtaFlush{table: "bus_stop_event", rows: len(rows), write: func(ctx context.Context) {
		saveBusStopEvents(ctx, target, rows)
	}})
}

func (s pgBusEtaStore) recordPredictions(_ context.Context, rows []predictionRecord) {
	if len(rows) == 0 {
		return
	}
	db := s.db
	_busEtaFlushes.submit(busEtaFlush{table: "bus_eta_prediction_error", rows: len(rows), write: func(ctx context.Context) {
		recordPredictionErrors(ctx, db, rows)
	}})
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
// busEtaFlushTimeout is the floor and busEtaFlushPerBatch the allowance for each
// further archiveRowsPerInsert rows. One flush goes out in bounded batches, so a
// flat deadline is the wrong shape: it fails only the largest bursts, and it
// fails them at the end, after most of the work is already spent. A snapshot of
// 21,353 rows died on the last of its 22 statements at a flat 60s, losing the
// tail and keeping the other 21,000.
const (
	_busEtaFlushTimeout  = 60 * time.Second
	_busEtaFlushPerBatch = 5 * time.Second
	_busEtaFlushDepth    = 8
	_busEtaFlushWorkers  = 2
)

// flushBudget is how long one batch of rows may take.
func flushBudget(floor time.Duration, rows int) time.Duration {
	return floor + time.Duration(rows/_archiveRowsPerInsert)*_busEtaFlushPerBatch
}

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
	wg      sync.WaitGroup
}

var _busEtaFlushes = &busEtaFlusher{
	queue:   make(chan busEtaFlush, _busEtaFlushDepth),
	workers: _busEtaFlushWorkers,
	timeout: _busEtaFlushTimeout,
}

// submit hands one batch to the flusher, dropping it when the queue is full.
// Workers start on first use so a process that never writes history never spawns
// them (and a test can hold the queue still by declaring zero workers).
func (f *busEtaFlusher) submit(task busEtaFlush) {
	f.start.Do(func() {
		for range f.workers {
			f.wg.Add(1)
			go func() {
				defer f.wg.Done()
				for t := range f.queue {
					ctx, cancel := context.WithTimeout(context.Background(), flushBudget(f.timeout, t.rows))
					t.write(ctx)
					cancel()
				}
			}()
		}
	})
	select {
	case f.queue <- task:
	default:
		zap.S().Warnw("dropped",
			"component", "bus_eta",
			"action", "flush",
			"event", "dropped",
			"table", task.table,
			"rows", task.rows,
			"reason", "queue_full",
		)
	}
}

// Close stops the flusher from accepting further work and waits for its
// workers to drain the queue and exit.
func (f *busEtaFlusher) Close() {
	close(f.queue)
	f.wg.Wait()
}
