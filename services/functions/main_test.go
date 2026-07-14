package main

import (
	"context"
	"errors"
	"go/ast"
	"go/parser"
	"go/token"
	"strings"
	"testing"
	"time"
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
