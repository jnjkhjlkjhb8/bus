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
		`CREATE TABLE IF NOT EXISTS bus_eta_history (
			sub_route_uid text, direction smallint, stop_uid text,
			hour smallint, day_of_week smallint, estimate double precision,
			recorded_at timestamptz NOT NULL DEFAULT NOW())`,
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
		for _, tbl := range []string{"bus_eta_history", "bus_travel_avg", "bus_schedule"} {
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

	// Ten arrival crossings for STOP_B: each pair is a positive estimate then a
	// non-positive one within 5s, which computeTravelAvg reads as one arrival.
	// Anchored to yesterday 08:05 Taipei so every crossing lands in hour 8 and
	// resolves against the 08:00 origin departure. Stored hour/day_of_week are
	// what the aggregation buckets on, independent of the wall-clock date.
	now := time.Now().In(taipei)
	base := time.Date(now.Year(), now.Month(), now.Day(), 8, 5, 0, 0, taipei).Add(-24 * time.Hour)
	for i := 0; i < 10; i++ {
		tPos := base.Add(time.Duration(i*20) * time.Second)
		tNeg := tPos.Add(5 * time.Second)
		if _, err := pool.Exec(ctx, `
			INSERT INTO bus_eta_history (sub_route_uid, direction, stop_uid, hour, day_of_week, estimate, recorded_at)
			VALUES ($1, 0, 'STOP_B', 8, 1, 60, $2), ($1, 0, 'STOP_B', 8, 1, -5, $3)`,
			sr, tPos, tNeg); err != nil {
			t.Fatalf("insert history pair %d: %v", i, err)
		}
	}

	if err := computeTravelAvg(ctx, pool); err != nil {
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
