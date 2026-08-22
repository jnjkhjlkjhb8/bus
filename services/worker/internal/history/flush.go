package history

import (
	"context"
	"sync"
	"time"

	"go.uber.org/zap"
)

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
// FlushTimeout is the floor and FlushPerBatch the allowance for each
// further archiveRowsPerInsert rows. One flush goes out in bounded batches, so a
// flat deadline is the wrong shape: it fails only the largest bursts, and it
// fails them at the end, after most of the work is already spent. A snapshot of
// 21,353 rows died on the last of its 22 statements at a flat 60s, losing the
// tail and keeping the other 21,000.
const (
	_flushTimeout  = 60 * time.Second
	_flushPerBatch = 5 * time.Second
	_flushDepth    = 8
	_flushWorkers  = 2
)

// flushBudget is how long one batch of rows may take.
func flushBudget(floor time.Duration, rows int) time.Duration {
	return floor + time.Duration(rows/RowsPerInsert)*_flushPerBatch
}

type Flush struct {
	table string
	rows  int
	write func(context.Context)
}

type Flusher struct {
	queue   chan Flush
	workers int
	timeout time.Duration
	start   sync.Once
	wg      sync.WaitGroup
}

var _flushes = &Flusher{
	queue:   make(chan Flush, _flushDepth),
	workers: _flushWorkers,
	timeout: _flushTimeout,
}

// submit hands one batch to the flusher, dropping it when the queue is full.
// Workers start on first use so a process that never writes history never spawns
// them (and a test can hold the queue still by declaring zero workers).
func (f *Flusher) submit(task Flush) {
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
func (f *Flusher) Close() {
	close(f.queue)
	f.wg.Wait()
}

// Submit queues one batch of archive rows for the background flusher. The write
// runs off the caller's clock on its own deadline, and is dropped loudly when
// the queue is full: a database that cannot keep up should shed batches rather
// than accumulate rows staler than the ones behind them.
func Submit(table string, rows int, write func(context.Context)) {
	_flushes.submit(Flush{table: table, rows: rows, write: write})
}

// CloseFlusher drains the queue and waits for the workers at shutdown.
func CloseFlusher() { _flushes.Close() }
