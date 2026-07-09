package main

import (
	"context"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// loadSink is the write seam a loadSpec's transform receives instead of the raw
// pool. copyUpsert owns the temp-table COPY + upsert skeleton the station, fare
// and timetable transforms all repeat; pool and redis are escape hatches for the
// loaders that do not fit that shape (the multi-table bus assembly reads six
// correlated raw_tdx tables, the metro OD-fare loader batches per row, the daily
// timetable loader writes only Redis). The production adapter is pgLoadSink;
// unit tests drive the migrated transforms through fakeLoadSink.
type loadSink interface {
	copyUpsert(ctx context.Context, spec copyUpsertSpec, rows [][]any) error
	pool() *pgxpool.Pool
	redis() *redis.Client
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

// pgLoadSink is the production loadSink backed by the env-schema pool plus the
// Redis client the Redis-only loaders need.
type pgLoadSink struct {
	db *pgxpool.Pool
	rc *redis.Client
}

func (s pgLoadSink) pool() *pgxpool.Pool  { return s.db }
func (s pgLoadSink) redis() *redis.Client { return s.rc }

// copyUpsert runs the temp-table COPY + upsert skeleton in one transaction:
// preExec statements, CREATE TEMP TABLE ... ON COMMIT DROP, CopyFrom, the
// INSERT ... SELECT drain, then Commit, with a deferred Rollback. Each step
// failure logs a structured [LOAD] line keyed by spec.key and returns; an
// aborted transaction never commits, so the SQL effect matches the per-transform
// skeletons this replaces. The per-partition success/date fields are logged by
// runLoadSpecs; this line carries the row count.
func (s pgLoadSink) copyUpsert(ctx context.Context, spec copyUpsertSpec, rows [][]any) error {
	b, err := s.db.Begin(ctx)
	if err != nil {
		log.Infof("[LOAD] action=copy_upsert dataset=%s event=begin_error error=%v", spec.key, err)
		return err
	}
	defer func() { _ = b.Rollback(ctx) }()
	for _, st := range spec.preExec {
		if _, err := b.Exec(ctx, st.sql, st.args...); err != nil {
			log.Infof("[LOAD] action=copy_upsert dataset=%s event=pre_exec_error error=%v", spec.key, err)
			return err
		}
	}
	if _, err := b.Exec(ctx, spec.createSQL); err != nil {
		log.Infof("[LOAD] action=copy_upsert dataset=%s event=create_temp_error error=%v", spec.key, err)
		return err
	}
	if _, err := b.CopyFrom(ctx, pgx.Identifier{spec.tempTable}, spec.copyCols, pgx.CopyFromRows(rows)); err != nil {
		log.Infof("[LOAD] action=copy_upsert dataset=%s event=copyfrom_error error=%v", spec.key, err)
		return err
	}
	if _, err := b.Exec(ctx, spec.insertSQL); err != nil {
		log.Infof("[LOAD] action=copy_upsert dataset=%s event=exec_error error=%v", spec.key, err)
		return err
	}
	if err := b.Commit(ctx); err != nil {
		log.Infof("[LOAD] action=copy_upsert dataset=%s event=commit_error error=%v", spec.key, err)
		return err
	}
	log.Infof("[LOAD] action=copy_upsert dataset=%s event=success rows=%d", spec.key, len(rows))
	return nil
}
