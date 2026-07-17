package main

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
)

// pipelineMarkerReader checks pipeline_runs for a completed job on a given
// date. The narrow interface keeps waitForPipelineMarker testable without a
// live database.
type pipelineMarkerReader interface {
	MarkerExists(ctx context.Context, job string, runDate time.Time) (bool, error)
}

// pgPipelineMarkerReader queries pipeline_runs against db (this environment's
// PG_SCHEMA). pipeline_runs is unqualified, like every other transform target
// table, so it resolves through db's search_path.
type pgPipelineMarkerReader struct{ db *pgxpool.Pool }

func (r pgPipelineMarkerReader) MarkerExists(ctx context.Context, job string, runDate time.Time) (bool, error) {
	var exists bool
	err := r.db.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM pipeline_runs WHERE job = $1 AND run_date = $2)`,
		job, runDate.Format(time.DateOnly),
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("query pipeline_runs marker %s: %w", job, err)
	}
	return exists, nil
}

// recordPipelineMarker upserts today's completion marker for job. Callers
// must only call this after a fully successful run; a failed or partial run
// must never write it, since downstream stages treat its presence as proof
// the upstream stage is safe to build on.
func recordPipelineMarker(ctx context.Context, db *pgxpool.Pool, job string, runDate time.Time) error {
	_, err := db.Exec(ctx,
		`INSERT INTO pipeline_runs (job, run_date) VALUES ($1, $2)
		 ON CONFLICT (job, run_date) DO UPDATE SET completed_at = now()`,
		job, runDate.Format(time.DateOnly),
	)
	if err != nil {
		return fmt.Errorf("record pipeline_runs marker %s: %w", job, err)
	}
	return nil
}

// recordPipelineMarkerWithRetry records the marker with a few quick attempts
// of its own, deliberately outside the caller's job retry: a failed one-row
// upsert must never re-drive the (expensive, already successful) stage it
// marks. Exhausted attempts are logged distinctly and returned so the caller
// can surface a marker-only failure without reporting the stage as failed.
//
// On success it also logs the marker lag: wall time from runDate (the
// cron tick's start, per its caller) to the marker write, i.e. how long this
// pipeline stage took end-to-end including its own retries. It is a plain
// structured-log gauge, not a queryable metric — waitForPipelineMarker (the
// only downstream consumer) already reads pipeline_runs directly, so a
// second read path would duplicate that source of truth for no benefit; a
// human tuning the SLO in docs/slo.md is the intended reader.
func recordPipelineMarkerWithRetry(ctx context.Context, db *pgxpool.Pool, job string, runDate time.Time) error {
	err := obs.Retry(ctx, 3, 5*time.Second, func() error {
		return obs.Transient(recordPipelineMarker(ctx, db, job, runDate))
	})
	if err != nil {
		log.Errorf("[PIPELINE] action=record_marker event=failed job=%s run_date=%s error=%v", job, runDate.Format(time.DateOnly), err)
		return err
	}
	log.Infof("[PIPELINE] action=record_marker event=recorded job=%s run_date=%s gauge=marker_lag_seconds value=%.0f",
		job, runDate.Format(time.DateOnly), time.Since(runDate).Seconds())
	return nil
}

const (
	pipelineMarkerPollInterval = 5 * time.Minute
	pipelineMarkerPollDeadline = 2 * time.Hour
)

// waitForPipelineMarker polls reader for job's runDate marker: an immediate
// check, then every interval, giving up once now (per the now func) has
// passed the deadline measured from the first check. A read error does not
// abort the wait — a transient database blip during the poll window must not
// cancel the whole nightly stage — it is logged and the next tick retries;
// only the deadline (or ctx via sleep) ends an unready wait. now and sleep
// are injected so the poll/deadline logic is testable without real waits.
func waitForPipelineMarker(
	ctx context.Context,
	reader pipelineMarkerReader,
	job string,
	runDate time.Time,
	interval, deadline time.Duration,
	now func() time.Time,
	sleep func(context.Context, time.Duration) error,
) error {
	deadlineAt := now().Add(deadline)
	var lastErr error
	for {
		ok, err := reader.MarkerExists(ctx, job, runDate)
		if err != nil {
			lastErr = err
			log.Errorf("[PIPELINE] action=wait_marker event=read_error job=%s run_date=%s error=%v", job, runDate.Format(time.DateOnly), err)
		} else {
			lastErr = nil
			if ok {
				return nil
			}
			log.Warnf("[PIPELINE] action=wait_marker event=not_ready job=%s run_date=%s", job, runDate.Format(time.DateOnly))
		}
		if !now().Before(deadlineAt) {
			log.Errorf("[PIPELINE] action=wait_marker event=give_up job=%s run_date=%s", job, runDate.Format(time.DateOnly))
			if lastErr != nil {
				return fmt.Errorf("pipeline marker %q not confirmed for %s by deadline: %w", job, runDate.Format(time.DateOnly), lastErr)
			}
			return fmt.Errorf("pipeline marker %q not found for %s by deadline", job, runDate.Format(time.DateOnly))
		}
		if err := sleep(ctx, interval); err != nil {
			return err
		}
	}
}

// sleepCtx waits d or returns ctx.Err() if ctx is done first. It is the
// production sleep implementation passed to waitForPipelineMarker.
func sleepCtx(ctx context.Context, d time.Duration) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(d):
		return nil
	}
}
