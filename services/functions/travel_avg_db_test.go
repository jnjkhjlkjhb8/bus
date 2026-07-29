package main

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// travelAvgTestPool connects to DATABASE_URL and skips when it is unset. Unlike
// loaderTestPool it does not require the raw_tdx schema: this test provisions
// the three bus_* tables it needs itself.
func travelAvgTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set; skipping travel-average integration test")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	return pool
}

// TestComputeTravelAvgMatchesTimetableDepartures is the regression guard for the
// getDepTimes fix: the origin-departure lookup must read timetable rows
// (type=false, origin = lowest stopsequence per trip) filtered by service_day,
// not the dead "type=true AND stopsequence=0" shape that never matches loaded
// rows. It lands a single 08:00 Monday origin departure plus ten arrival
// crossings for a downstream stop, runs computeTravelAvg, and asserts a
// bus_travel_avg bucket was produced. With the old dead query getDepTimes
// returns nothing, every crossing is skipped, and no bucket is upserted.
func TestComputeTravelAvgMatchesTimetableDepartures(t *testing.T) {
	pool := travelAvgTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	ddl := []string{
		`CREATE TABLE IF NOT EXISTS bus_travel_avg (
			sub_route_uid text, direction smallint, stop_uid text,
			hour smallint, day_of_week smallint, avg_seconds int,
			sample_count int, updated_at timestamptz NOT NULL DEFAULT NOW(),
			PRIMARY KEY (sub_route_uid, direction, stop_uid, hour, day_of_week))`,
		`CREATE TABLE IF NOT EXISTS bus_schedule (
			sub_route_uid text, direction smallint, type bool, tripid text,
			islowfloor bool, stopsequence smallint,
			"stop_uid/MinHeadwayMins" text, "stop_name/MaxHeadwayMins" text,
			"arrival_time/StartTime" time, "departure_time/EndTime" time,
			service_day smallint, updated_at timestamptz NOT NULL DEFAULT NOW(),
			PRIMARY KEY (sub_route_uid, direction, type, service_day, tripid, "stop_uid/MinHeadwayMins"))`,
	}
	for _, s := range ddl {
		if _, err := pool.Exec(ctx, s); err != nil {
			t.Fatalf("provision: %v\nDDL: %s", err, s)
		}
	}

	const sr = "TESTTRAVELAVG_SR"
	clean := func() {
		for _, tbl := range []string{"bus_travel_avg", "bus_schedule"} {
			if _, err := pool.Exec(ctx, "DELETE FROM "+tbl+" WHERE sub_route_uid = $1", sr); err != nil {
				t.Fatalf("clean %s: %v", tbl, err)
			}
		}
	}
	clean()
	defer clean()

	// Origin departure at 08:00, Monday only. day_of_week=1 (Monday) maps to
	// service_day bit0 = 1, so the getDepTimes service_day filter must match.
	// Two stops on one trip; the origin is the lowest stopsequence.
	if _, err := pool.Exec(ctx, `
		INSERT INTO bus_schedule (sub_route_uid, direction, type, tripid, islowfloor,
			stopsequence, "stop_uid/MinHeadwayMins", "stop_name/MaxHeadwayMins",
			"arrival_time/StartTime", "departure_time/EndTime", service_day)
		VALUES ($1, 0, false, 'T1', false, 1, 'STOP_A', 'A', '08:00:00', '08:00:00', 1),
		       ($1, 0, false, 'T1', false, 2, 'STOP_B', 'B', '08:10:00', '08:10:00', 1)`,
		sr); err != nil {
		t.Fatalf("insert schedule: %v", err)
	}

	// Ten arrival crossings for STOP_B, supplied as fixtures: bus_eta_history
	// lives on the MySQL history host now, so only the Postgres half of the job
	// (departure lookup, bucketing, upsert) is exercised against a real database.
	// Anchored to yesterday 08:05 Taipei so every crossing lands in hour 8 and
	// resolves against the 08:00 origin departure. hour/day_of_week are what the
	// aggregation buckets on, independent of the wall-clock date.
	now := time.Now().In(taipei)
	base := time.Date(now.Year(), now.Month(), now.Day(), 8, 5, 0, 0, taipei).Add(-24 * time.Hour)
	hist := &fakeHistory{}
	for i := range 10 {
		hist.crossingRows = append(hist.crossingRows, crossing{
			subRouteUID: sr, direction: 0, stopUID: "STOP_B", hour: 8, dayOfWeek: 1,
			crossingAt: base.Add(time.Duration(i*20) * time.Second),
		})
	}

	if err := computeTravelAvg(ctx, pool, hist); err != nil {
		t.Fatalf("computeTravelAvg: %v", err)
	}

	var sampleCount, avgSeconds int
	err := pool.QueryRow(ctx, `
		SELECT sample_count, avg_seconds FROM bus_travel_avg
		WHERE sub_route_uid = $1 AND direction = 0 AND stop_uid = 'STOP_B'
		  AND hour = 8 AND day_of_week = 1`, sr).Scan(&sampleCount, &avgSeconds)
	if err != nil {
		t.Fatalf("expected a travel-average bucket (dead getDepTimes query would produce none): %v", err)
	}
	if sampleCount != 10 {
		t.Errorf("sample_count = %d, want 10", sampleCount)
	}
	if avgSeconds <= 0 || avgSeconds > 7200 {
		t.Errorf("avg_seconds = %d, want a positive origin-to-stop travel time within range", avgSeconds)
	}
}

// TestCleanupPredictionErrorsRetentionBoundary pins the 30-day retention
// boundary of the only data-deleting cron left on Postgres: rows past the
// window must go, rows inside it must survive. bus_eta_history is no longer a
// target — it lives on the MySQL history host and is never pruned.
func TestCleanupPredictionErrorsRetentionBoundary(t *testing.T) {
	pool := travelAvgTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	if _, err := pool.Exec(ctx, `CREATE TABLE IF NOT EXISTS bus_eta_prediction_error (
		sub_route_uid text, direction smallint, stop_uid text, source text,
		predicted_at timestamptz NOT NULL, predicted_seconds int, actual_seconds int)`); err != nil {
		t.Fatalf("provision: %v", err)
	}

	const sr = "TESTCLEANUP_SR"
	clean := func() {
		_, _ = pool.Exec(ctx, `DELETE FROM bus_eta_prediction_error WHERE sub_route_uid = $1`, sr)
	}
	clean()
	defer clean()

	for _, age := range []string{"31 days", "29 days"} {
		if _, err := pool.Exec(ctx, `
			INSERT INTO bus_eta_prediction_error (sub_route_uid, direction, stop_uid, source, predicted_at, predicted_seconds)
			VALUES ($1, 0, 'STOP_A', 'model', NOW() - $2::interval, 120)`, sr, age); err != nil {
			t.Fatalf("insert prediction error %s: %v", age, err)
		}
	}

	if err := cleanupPredictionErrors(ctx, pool); err != nil {
		t.Fatalf("cleanupPredictionErrors: %v", err)
	}

	for _, q := range []struct{ table, timeCol string }{
		{"bus_eta_prediction_error", "predicted_at"},
	} {
		var total, old int
		err := pool.QueryRow(ctx, `SELECT COUNT(*), COUNT(*) FILTER (WHERE `+q.timeCol+` < NOW() - INTERVAL '30 days')
			FROM `+q.table+` WHERE sub_route_uid = $1`, sr).Scan(&total, &old)
		if err != nil {
			t.Fatalf("count %s: %v", q.table, err)
		}
		if total != 1 || old != 0 {
			t.Fatalf("%s after cleanup: total=%d old=%d, want only the 29-day row", q.table, total, old)
		}
	}
}
