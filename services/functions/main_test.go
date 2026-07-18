package main

import (
	"context"
	"errors"
	"go/ast"
	"go/parser"
	"go/token"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/robfig/cron/v3"
)

func TestRunLegacyProdRoutesBootLoadThroughStaticGuard(t *testing.T) {
	file, err := parser.ParseFile(token.NewFileSet(), "main.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	var legacy *ast.FuncDecl
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if ok && fn.Name.Name == "runLegacyProd" {
			legacy = fn
			break
		}
	}
	if legacy == nil {
		t.Fatal("runLegacyProd declaration not found")
	}
	var guardedBootCalls, directLoadCalls int
	ast.Inspect(legacy.Body, func(node ast.Node) bool {
		call, ok := node.(*ast.CallExpr)
		if !ok {
			return true
		}
		ident, ok := call.Fun.(*ast.Ident)
		if !ok {
			return true
		}
		switch ident.Name {
		case "runBootBusDailyTimetable":
			guardedBootCalls++
		case "runLoad":
			directLoadCalls++
		}
		return true
	})
	if guardedBootCalls != 1 {
		t.Fatalf("runLegacyProd guarded boot calls = %d, want 1", guardedBootCalls)
	}
	if directLoadCalls != 0 {
		t.Fatalf("runLegacyProd direct runLoad calls = %d, want 0", directLoadCalls)
	}
}

// TestChangeToVectorBoundToLoader guards the ownership move: changetovector must
// run in the loader (registerLoaderCrons -> runVectorRefresh, once per the cron
// and boot paths) and must no longer be hosted by the functions service
// (runLegacyProd). If someone re-adds it to runLegacyProd or drops it from the
// loader, the load->vector path silently depends on functions again.
func TestChangeToVectorBoundToLoader(t *testing.T) {
	countCalls := func(file, fnName, callee string) int {
		parsed, err := parser.ParseFile(token.NewFileSet(), file, nil, 0)
		if err != nil {
			t.Fatal(err)
		}
		var target *ast.FuncDecl
		for _, decl := range parsed.Decls {
			if fn, ok := decl.(*ast.FuncDecl); ok && fn.Name.Name == fnName {
				target = fn
				break
			}
		}
		if target == nil {
			t.Fatalf("%s declaration not found in %s", fnName, file)
		}
		n := 0
		ast.Inspect(target.Body, func(node ast.Node) bool {
			if call, ok := node.(*ast.CallExpr); ok {
				if ident, ok := call.Fun.(*ast.Ident); ok && ident.Name == callee {
					n++
				}
			}
			return true
		})
		return n
	}
	if got := countCalls("loader_cron.go", "registerLoaderCrons", "runVectorRefresh"); got != 2 {
		t.Fatalf("registerLoaderCrons runVectorRefresh calls = %d, want 2 (cron + boot)", got)
	}
	if got := countCalls("main.go", "runLegacyProd", "runVectorRefresh"); got != 0 {
		t.Fatalf("runLegacyProd runVectorRefresh calls = %d, want 0 (moved to loader)", got)
	}
}

func TestVectorRefreshJobPropagatesError(t *testing.T) {
	wantErr := errors.New("watermark unavailable")
	job := vectorRefreshJob(
		&testVectorRedis{getErr: wantErr},
		nil,
		&stubEmbeddingClient{},
	)
	if err := job(context.Background()); !errors.Is(err, wantErr) {
		t.Fatalf("vectorRefreshJob() error = %v, want wrapped %v", err, wantErr)
	}
}

func TestRunDailyRetriesLoadPartitionFailure(t *testing.T) {
	partitionErr := errors.New("load partition failed")
	attempts := 0
	err := runDailyWithRetry(context.Background(), 100*time.Millisecond, 0, func(context.Context) error {
		attempts++
		if attempts == 1 {
			return partitionErr
		}
		return nil
	})
	if err != nil {
		t.Fatalf("runDailyWithRetry returned %v", err)
	}
	if attempts != 2 {
		t.Fatalf("attempts = %d, want 2", attempts)
	}
}

func TestMask(t *testing.T) {
	got := mask(true, false, true, false, false, false, true)
	want := uint8((1 << 0) | (1 << 2) | (1 << 6))
	if got != want {
		t.Fatalf("mask() = %d, want %d", got, want)
	}
}

func TestMask2(t *testing.T) {
	got := mask2(0, 1, 0, 0, 0, 1, 0)
	want := uint8((1 << 1) | (1 << 5))
	if got != want {
		t.Fatalf("mask2() = %d, want %d", got, want)
	}
}

// TestDrainShutdownWaitsForBootJobBeforeReturning proves drainShutdown does
// not return the instant shutdown is signaled: a boot goroutine still running
// must be waited for (up to the grace period) before the caller is allowed to
// close shared dependencies.
func TestDrainShutdownWaitsForBootJobBeforeReturning(t *testing.T) {
	var boot sync.WaitGroup
	var jobFinished atomic.Bool
	boot.Add(1)
	go func() {
		defer boot.Done()
		time.Sleep(50 * time.Millisecond)
		jobFinished.Store(true)
	}()

	alreadyStoppedCron, cancel := context.WithCancel(context.Background())
	cancel() // no cron work in flight; isolate the boot-goroutine wait

	start := time.Now()
	drainShutdown(alreadyStoppedCron, &boot, time.Second)
	elapsed := time.Since(start)

	if !jobFinished.Load() {
		t.Fatal("drainShutdown returned before the tracked boot job finished")
	}
	if elapsed < 50*time.Millisecond {
		t.Fatalf("drainShutdown returned after %v, want it to have waited for the 50ms job", elapsed)
	}
}

// TestDrainShutdownBoundedByGraceTimeout proves a job that never finishes
// cannot hang the process forever: drainShutdown must return once the grace
// period elapses even though the tracked work is still outstanding.
func TestDrainShutdownBoundedByGraceTimeout(t *testing.T) {
	var boot sync.WaitGroup
	boot.Add(1) // deliberately never Done: simulates a stuck boot job
	t.Cleanup(boot.Done)

	neverDone, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)

	const grace = 50 * time.Millisecond
	start := time.Now()
	drainShutdown(neverDone, &boot, grace)
	elapsed := time.Since(start)

	if elapsed < grace {
		t.Fatalf("drainShutdown returned after %v, want at least the %v grace period", elapsed, grace)
	}
	if elapsed > grace+500*time.Millisecond {
		t.Fatalf("drainShutdown returned after %v, want it bounded near the %v grace period", elapsed, grace)
	}
}

// TestAddStaticCronSkipsOverlappingEntry exercises addStaticCron itself (the
// wrapper every realtime and daily cron entry in main.go/live.go now goes
// through) against a real *cron.Cron, invoking the registered entry's Job
// twice concurrently the way two ticks racing would.
func TestAddStaticCronSkipsOverlappingEntry(t *testing.T) {
	r := cron.New(cron.WithSeconds())
	var runs atomic.Int64
	started := make(chan struct{}, 1)
	release := make(chan struct{})
	id, err := addStaticCron(r, "@every 1h", func() {
		runs.Add(1)
		started <- struct{}{}
		<-release
	})
	if err != nil {
		t.Fatalf("addStaticCron: %v", err)
	}
	entry := r.Entry(id)
	if entry.Job == nil {
		t.Fatal("registered entry has no Job")
	}

	go entry.Job.Run()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("first invocation never started")
	}

	secondDone := make(chan struct{})
	go func() {
		entry.Job.Run()
		close(secondDone)
	}()
	select {
	case <-secondDone:
	case <-time.After(time.Second):
		t.Fatal("overlapping invocation did not return promptly; addStaticCron did not skip it")
	}

	close(release)
	if got := runs.Load(); got != 1 {
		t.Fatalf("addStaticCron job ran %d times, want exactly 1 (overlapping invocation must be skipped)", got)
	}
}

// TestLiveTickDeadlineStaysUnderCadence locks in the whole-tick deadline
// contract: every deadline must be strictly less than its cadence's period, so
// a tick's jobs cannot bleed into the next tick under ordinary conditions
// (SkipIfStillRunning is the backstop for when they still do).
func TestLiveTickDeadlineStaysUnderCadence(t *testing.T) {
	tests := []struct {
		cadence string
		period  time.Duration
	}{
		{"@every 10s", 10 * time.Second},
		{"@every 30s", 30 * time.Second},
		{"@every 2m", 2 * time.Minute},
		{"@every 10m", 10 * time.Minute},
	}
	for _, tt := range tests {
		t.Run(tt.cadence, func(t *testing.T) {
			got := liveTickDeadline(tt.cadence)
			if got <= 0 || got >= tt.period {
				t.Fatalf("liveTickDeadline(%q) = %v, want strictly between 0 and %v", tt.cadence, got, tt.period)
			}
		})
	}
	if got := liveTickDeadline("@every 30s"); got != liveJobTimeout {
		t.Fatalf("liveTickDeadline(@every 30s) = %v, want liveJobTimeout %v (unchanged bus/bike behavior)", got, liveJobTimeout)
	}
}

func TestBusSubroutesUpsertDeduplicatesConflictKeys(t *testing.T) {
	if !strings.Contains(busSubroutesUpsertSQL, "SELECT DISTINCT ON (uid, d)") {
		t.Fatalf("bus_subroutes upsert SQL missing DISTINCT ON dedup")
	}
}

// TestBusScheduleInsertKeepsDuplicates locks in the partition-replace contract:
// bus_schedule is rebuilt per city by DELETE + plain INSERT, so the schedule
// insert must NOT dedup (no DISTINCT ON) and must NOT upsert (no ON CONFLICT).
// A circular route visits the same stop twice per trip, colliding on the old
// natural key; those rows are intentionally kept now.
func TestBusScheduleInsertKeepsDuplicates(t *testing.T) {
	for _, banned := range []string{"DISTINCT ON", "ON CONFLICT"} {
		if strings.Contains(busScheduleInsertSQL, banned) {
			t.Fatalf("bus_schedule insert SQL must not contain %q (partition-replace keeps duplicate rows)", banned)
		}
	}
}
