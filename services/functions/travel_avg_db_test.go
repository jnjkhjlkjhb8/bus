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
// the two bus_* tables it needs itself.
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

// TestComputeTravelAvgDerivesTripsFromPlates covers the whole derivation: an
// arrival is the tail of a descending estimate run, the origin arrival of the
// same plate is that trip's departure, and the bucket keys on the departure's
// hour and weekday. Three trips land 10 minutes apart, each observed twice at the
// origin and twice downstream, giving one bucket of three samples.
func TestComputeTravelAvgDerivesTripsFromPlates(t *testing.T) {
	pool := travelAvgTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	ddl := []string{
		`CREATE TABLE IF NOT EXISTS bus_eta_history (
			sub_route_uid text, direction smallint, stop_uid text,
			stop_sequence smallint, estimate int, plate_numb text,
			src_update_time timestamptz,
			recorded_at timestamptz NOT NULL DEFAULT NOW())`,
		`CREATE TABLE IF NOT EXISTS bus_travel_avg (
			sub_route_uid text, direction smallint, stop_uid text,
			hour smallint, day_of_week smallint, avg_seconds int,
			sample_count int, updated_at timestamptz NOT NULL DEFAULT NOW(),
			PRIMARY KEY (sub_route_uid, direction, stop_uid, hour, day_of_week))`,
	}
	for _, s := range ddl {
		if _, err := pool.Exec(ctx, s); err != nil {
			t.Fatalf("provision: %v\nDDL: %s", err, s)
		}
	}

	const sr = "TESTTRAVELAVG_SR"
	clean := func() {
		for _, tbl := range []string{"bus_eta_history", "bus_travel_avg"} {
			if _, err := pool.Exec(ctx, "DELETE FROM "+tbl+" WHERE sub_route_uid = $1", sr); err != nil {
				t.Fatalf("clean %s: %v", tbl, err)
			}
		}
	}
	clean()
	defer clean()

	// Yesterday 08:05 Taipei, so all three departures fall in hour 8 and the
	// aggregation window (30 days) covers them regardless of wall-clock date.
	now := time.Now().In(taipei)
	base := time.Date(now.Year(), now.Month(), now.Day(), 8, 5, 0, 0, taipei).Add(-24 * time.Hour)

	insert := func(stop string, seq int, est int, at time.Time, plate string) {
		t.Helper()
		if _, err := pool.Exec(ctx, `
			INSERT INTO bus_eta_history
			  (sub_route_uid, direction, stop_uid, stop_sequence, estimate, plate_numb, recorded_at)
			VALUES ($1, 0, $2, $3, $4, $5, $6)`,
			sr, stop, seq, est, plate, at); err != nil {
			t.Fatalf("insert %s@%s: %v", plate, stop, err)
		}
	}

	for i, plate := range []string{"KAA-001", "KAA-002", "KAA-003"} {
		dep := base.Add(time.Duration(i*10) * time.Minute)
		// Origin: run tail at dep+20s with estimate 30 => departure at dep+50s.
		insert("STOP_A", 1, 300, dep, plate)
		insert("STOP_A", 1, 30, dep.Add(20*time.Second), plate)
		// Downstream: run tail at dep+10m with estimate 60 => arrival at dep+11m.
		insert("STOP_B", 2, 600, dep.Add(2*time.Minute), plate)
		insert("STOP_B", 2, 60, dep.Add(10*time.Minute), plate)
	}

	if err := computeTravelAvg(ctx, pool); err != nil {
		t.Fatalf("computeTravelAvg: %v", err)
	}

	var sampleCount, avgSeconds int
	err := pool.QueryRow(ctx, `
		SELECT sample_count, avg_seconds FROM bus_travel_avg
		WHERE sub_route_uid = $1 AND direction = 0 AND stop_uid = 'STOP_B'
		  AND hour = 8 AND day_of_week = $2`,
		sr, int(base.Weekday())).Scan(&sampleCount, &avgSeconds)
	if err != nil {
		t.Fatalf("expected a travel-average bucket: %v", err)
	}
	if sampleCount != 3 {
		t.Errorf("sample_count = %d, want 3", sampleCount)
	}
	// arrival(dep+11m) - departure(dep+50s) = 610s.
	if avgSeconds != 610 {
		t.Errorf("avg_seconds = %d, want 610", avgSeconds)
	}
}
