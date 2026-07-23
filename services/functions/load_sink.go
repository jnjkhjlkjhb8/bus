package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"reflect"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// decodeLoadArray consumes exactly one JSON array, returning a wrapped error
// for the element that failed to decode or validate. Load transforms call this
// before opening a write transaction or Redis pipeline so a malformed suffix
// cannot leave a partially applied target.
func decodeLoadArray[T any](dec *json.Decoder, dataset string, validate func(int, T) error) ([]T, error) {
	tok, err := dec.Token()
	if err != nil {
		return nil, fmt.Errorf("%s opening array: %w", dataset, err)
	}
	if tok != json.Delim('[') {
		return nil, fmt.Errorf("%s opening array: got %v", dataset, tok)
	}

	items := make([]T, 0)
	for index := 0; dec.More(); index++ {
		var item T
		if err := dec.Decode(&item); err != nil {
			return nil, fmt.Errorf("%s element %d decode: %w", dataset, index, err)
		}
		if validate != nil {
			if err := validate(index, item); err != nil {
				return nil, fmt.Errorf("%s element %d: %w", dataset, index, err)
			}
		}
		items = append(items, item)
	}
	if tok, err = dec.Token(); err != nil {
		return nil, fmt.Errorf("%s closing array: %w", dataset, err)
	}
	if tok != json.Delim(']') {
		return nil, fmt.Errorf("%s closing array: got %v", dataset, tok)
	}
	var trailing json.RawMessage
	if err := dec.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return nil, fmt.Errorf("%s trailing JSON value", dataset)
		}
		return nil, fmt.Errorf("%s trailing JSON: %w", dataset, err)
	}
	return items, nil
}

// appendUniqueLoadRow keeps the first row for a target natural key. Identical
// source duplicates collapse deterministically; divergent duplicates abort the
// load before the sink opens a transaction.
func appendUniqueLoadRow(rows *[][]any, seen map[string][]any, key, label string, row []any) error {
	if prior, ok := seen[key]; ok {
		if reflect.DeepEqual(prior, row) {
			return nil
		}
		return fmt.Errorf("divergent duplicate %s %q", label, key)
	}
	seen[key] = row
	*rows = append(*rows, row)
	return nil
}

// errorWithout removes only branches that resolve to target from an error tree.
// In particular, errors.Join may combine a benign transaction-closed sentinel
// with a real rollback failure; checking errors.Is on the combined error would
// otherwise discard both branches.
func errorWithout(err, target error) error {
	if err == nil {
		return nil
	}
	if joined, ok := err.(interface{ Unwrap() []error }); ok {
		remaining := make([]error, 0, len(joined.Unwrap()))
		for _, child := range joined.Unwrap() {
			if child = errorWithout(child, target); child != nil {
				remaining = append(remaining, child)
			}
		}
		return errors.Join(remaining...)
	}
	if wrapped, ok := err.(interface{ Unwrap() error }); ok {
		child := wrapped.Unwrap()
		if errors.Is(child, target) {
			return errorWithout(child, target)
		}
	}
	if errors.Is(err, target) {
		return nil
	}
	return err
}

// loadSink is the write seam a loadSpec's transform receives instead of raw
// PostgreSQL and Redis clients. copyUpsert owns the temp-table COPY + upsert
// skeleton the station, fare and timetable transforms repeat; semantic methods
// own the loaders that do not fit that shape. The production adapter is
// pgLoadSink; unit tests drive the transforms through fakeLoadSink.
type loadSink interface {
	copyUpsert(ctx context.Context, spec copyUpsertSpec, rows [][]any) error
	loadBusCity(ctx context.Context, src loadSource, city string) error
	loadBusDailyTimetable(ctx context.Context, dec *json.Decoder, src loadSource, city string) error
	loadMrtJourneyMatrix(ctx context.Context, dec *json.Decoder, system string) error
	loadMrtTravelTime(ctx context.Context, src loadSource, system string) error
	loadThsrStations(ctx context.Context, dec *json.Decoder, part string) error
}

type copyUpsertSink interface {
	copyUpsert(ctx context.Context, spec copyUpsertSpec, rows [][]any) error
}

// copyUpsertStmt is one parameterized statement copyUpsert runs inside its
// transaction before staging, e.g. the partition DELETE the mrt_schedule
// partition-replace load performs before re-inserting a system's rows.
type copyUpsertStmt struct {
	sql  string
	args []any
}

// copyUpsertSpec is one dataset's copy-upsert recipe: the log identity, optional
// pre-staging statements, the temp-table DDL and its COPY columns, and the
// INSERT ... SELECT ... [ON CONFLICT ...] drain into the env-schema target. The
// SQL strings are byte-identical to the transforms this consolidates; genuinely
// per-dataset logic (the TRA service-day mask, THSR overnight) stays in the
// caller's row mapping, not here.
type copyUpsertSpec struct {
	key       string
	preExec   []copyUpsertStmt
	createSQL string
	tempTable string
	copyCols  []string
	insertSQL string
}

// pgLoadSink is the production loadSink backed by the env-schema pool and Redis.
type pgLoadSink struct {
	db *pgxpool.Pool
	rc *redis.Client
}

type loadTx interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	CopyFrom(context.Context, pgx.Identifier, []string, pgx.CopyFromSource) (int64, error)
	Commit(context.Context) error
	Rollback(context.Context) error
}

type loadTxBeginner interface {
	BeginLoadTx(context.Context) (loadTx, error)
}

func (s pgLoadSink) BeginLoadTx(ctx context.Context) (loadTx, error) {
	if s.db == nil {
		return nil, errors.New("nil PostgreSQL pool")
	}
	return s.db.Begin(ctx)
}

func (s pgLoadSink) loadBusCity(ctx context.Context, src loadSource, city string) error {
	return loadBus(ctx, src, s.db, s.rc, city)
}

func (s pgLoadSink) loadBusDailyTimetable(ctx context.Context, dec *json.Decoder, src loadSource, city string) error {
	return loadBusDailyTimetable(ctx, dec, src, s.db, s.rc, city)
}

func (s pgLoadSink) loadMrtJourneyMatrix(ctx context.Context, dec *json.Decoder, system string) error {
	return loadMrtJourneyMatrix(ctx, dec, s, system)
}

func (s pgLoadSink) loadMrtTravelTime(ctx context.Context, src loadSource, system string) error {
	return loadMrtTrtcTravelTime(ctx, src, s, system)
}

func (s pgLoadSink) loadThsrStations(ctx context.Context, dec *json.Decoder, part string) error {
	return loadThsrStation(ctx, dec, s, part)
}

// copyUpsert runs the temp-table COPY + upsert skeleton in one transaction:
// preExec statements, CREATE TEMP TABLE ... ON COMMIT DROP, CopyFrom, the
// INSERT ... SELECT drain, then Commit, with a deferred Rollback. Each step
// failure logs a structured [LOAD] line keyed by spec.key and returns; an
// aborted transaction never commits, so the SQL effect matches the per-transform
// skeletons this replaces. The per-partition success/date fields are logged by
// runLoadSpecs; this line carries the row count.
func (s pgLoadSink) copyUpsert(ctx context.Context, spec copyUpsertSpec, rows [][]any) error {
	return runCopyUpsert(ctx, s, spec, rows)
}

func runCopyUpsert(ctx context.Context, db loadTxBeginner, spec copyUpsertSpec, rows [][]any) (resultErr error) {
	if db == nil {
		return fmt.Errorf("copy-upsert %s begin: nil database", spec.key)
	}
	b, err := db.BeginLoadTx(ctx)
	if err != nil {
		log.Errorf("[LOAD] action=copy_upsert dataset=%s event=begin_error error=%v", spec.key, err)
		return fmt.Errorf("copy-upsert %s begin: %w", spec.key, err)
	}
	committed := false
	defer func() {
		if committed {
			return
		}
		rollbackCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := errorWithout(b.Rollback(rollbackCtx), pgx.ErrTxClosed); err != nil {
			resultErr = errors.Join(resultErr, fmt.Errorf("copy-upsert %s rollback: %w", spec.key, err))
		}
	}()
	for index, st := range spec.preExec {
		if _, err := b.Exec(ctx, st.sql, st.args...); err != nil {
			log.Errorf("[LOAD] action=copy_upsert dataset=%s event=pre_exec_error error=%v", spec.key, err)
			return fmt.Errorf("copy-upsert %s pre-exec %d: %w", spec.key, index, err)
		}
	}
	if _, err := b.Exec(ctx, spec.createSQL); err != nil {
		log.Errorf("[LOAD] action=copy_upsert dataset=%s event=create_temp_error error=%v", spec.key, err)
		return fmt.Errorf("copy-upsert %s create temp: %w", spec.key, err)
	}
	if _, err := b.CopyFrom(ctx, pgx.Identifier{spec.tempTable}, spec.copyCols, pgx.CopyFromRows(rows)); err != nil {
		log.Errorf("[LOAD] action=copy_upsert dataset=%s event=copyfrom_error error=%v", spec.key, err)
		return fmt.Errorf("copy-upsert %s COPY %s: %w", spec.key, spec.tempTable, err)
	}
	if _, err := b.Exec(ctx, spec.insertSQL); err != nil {
		log.Errorf("[LOAD] action=copy_upsert dataset=%s event=exec_error error=%v", spec.key, err)
		return fmt.Errorf("copy-upsert %s final exec: %w", spec.key, err)
	}
	if err := b.Commit(ctx); err != nil {
		log.Errorf("[LOAD] action=copy_upsert dataset=%s event=commit_error error=%v", spec.key, err)
		return fmt.Errorf("copy-upsert %s commit: %w", spec.key, err)
	}
	committed = true
	log.Infof("[LOAD] action=copy_upsert dataset=%s event=success rows=%d", spec.key, len(rows))
	return nil
}
