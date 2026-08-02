package main

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// segmentEtaTestPool connects to DATABASE_URL and skips when it is unset, the
// same shape cleanupTestPool uses.
func segmentEtaTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set; skipping segment-from-estimates integration test")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	return pool
}

// fixtureHistory is a historySource that returns canned hops. The observations
// live on MySQL now, so the judgements that used to be asserted here — adjacency,
// sequence gaps, non-positive differences — are made by SQL this suite cannot
// reach. What is still Go, and still worth pinning, is what the process does with
// the rows that come back.
type fixtureHistory struct {
	plate    []segmentObs
	estimate []segmentObs
}

func (f fixtureHistory) arrivals(context.Context, time.Time) ([]arrivalEvent, error) {
	return nil, nil
}

func (f fixtureHistory) segmentsByPlate(context.Context, time.Duration) ([]segmentObs, error) {
	return f.plate, nil
}

func (f fixtureHistory) segmentsByEstimate(context.Context, time.Duration) ([]segmentObs, error) {
	return f.estimate, nil
}

// TestComputeSegmentTimesFromEstimates asserts the conflict rule the estimate
// pass carries: it runs after the plate pass, so it must fill a hop nobody
// covered, replace a figure resting on fewer observations, and leave a
// better-sampled one exactly as it was. Getting this backwards would quietly
// overwrite every plate-derived hop with a worse-sampled snapshot difference.
func TestComputeSegmentTimesFromEstimates(t *testing.T) {
	pool := segmentEtaTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	if _, err := pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS bus_segment_time (
			sub_route_uid text NOT NULL, direction smallint NOT NULL,
			from_stop_uid text NOT NULL, to_stop_uid text NOT NULL,
			secs int NOT NULL, sample_count int NOT NULL,
			updated_at timestamptz NOT NULL DEFAULT NOW(),
			PRIMARY KEY (sub_route_uid, direction, from_stop_uid, to_stop_uid))`); err != nil {
		t.Fatalf("ddl: %v", err)
	}

	const uid = "TESTSEG0001"
	cleanup := func() {
		_, _ = pool.Exec(ctx, `DELETE FROM bus_segment_time WHERE sub_route_uid = $1`, uid)
	}
	cleanup()
	t.Cleanup(cleanup)

	// Two rows already in the table: S1->S2 rests on more observations than the
	// estimate pass offers, S2->S3 on fewer.
	if _, err := pool.Exec(ctx, `
		INSERT INTO bus_segment_time
		  (sub_route_uid, direction, from_stop_uid, to_stop_uid, secs, sample_count)
		VALUES ($1, 0, 'S1', 'S2', 999, 50), ($1, 0, 'S2', 'S3', 999, 1)`, uid); err != nil {
		t.Fatalf("seed segments: %v", err)
	}

	hist := fixtureHistory{estimate: []segmentObs{
		{subRouteUID: uid, direction: 0, fromStopUID: "S1", toStopUID: "S2", secs: 120, sampleCount: 8},
		{subRouteUID: uid, direction: 0, fromStopUID: "S2", toStopUID: "S3", secs: 220, sampleCount: 8},
		{subRouteUID: uid, direction: 0, fromStopUID: "S3", toStopUID: "S4", secs: 300, sampleCount: 8},
	}}
	if err := computeSegmentTimesFromEstimates(ctx, pool, hist); err != nil {
		t.Fatalf("computeSegmentTimesFromEstimates: %v", err)
	}

	got := map[string][2]int{}
	cur, err := pool.Query(ctx, `
		SELECT from_stop_uid, to_stop_uid, secs, sample_count
		FROM bus_segment_time WHERE sub_route_uid = $1`, uid)
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	defer cur.Close()
	for cur.Next() {
		var from, to string
		var secs, n int
		if err := cur.Scan(&from, &to, &secs, &n); err != nil {
			t.Fatalf("scan: %v", err)
		}
		got[from+"->"+to] = [2]int{secs, n}
	}
	if err := cur.Err(); err != nil {
		t.Fatalf("rows: %v", err)
	}

	if v, ok := got["S1->S2"]; !ok || v[0] != 999 || v[1] != 50 {
		t.Errorf("S1->S2 = %v, want the better-sampled row (999s, 50) left intact", v)
	}
	if v, ok := got["S2->S3"]; !ok || v[0] != 220 || v[1] != 8 {
		t.Errorf("S2->S3 = %v, want (220, 8): more observations than the row it replaces", v)
	}
	if v, ok := got["S3->S4"]; !ok || v[0] != 300 || v[1] != 8 {
		t.Errorf("S3->S4 = %v, want (300, 8): a hop nothing covered before", v)
	}
}

// The plate pass writes unconditionally — it runs first, so anything already in
// the table is from a previous day's rebuild and the fresh figure wins whatever
// it rests on.
func TestComputeSegmentTimesOverwritesRegardlessOfSamples(t *testing.T) {
	pool := segmentEtaTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	if _, err := pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS bus_segment_time (
			sub_route_uid text NOT NULL, direction smallint NOT NULL,
			from_stop_uid text NOT NULL, to_stop_uid text NOT NULL,
			secs int NOT NULL, sample_count int NOT NULL,
			updated_at timestamptz NOT NULL DEFAULT NOW(),
			PRIMARY KEY (sub_route_uid, direction, from_stop_uid, to_stop_uid))`); err != nil {
		t.Fatalf("ddl: %v", err)
	}

	const uid = "TESTSEG0002"
	cleanup := func() {
		_, _ = pool.Exec(ctx, `DELETE FROM bus_segment_time WHERE sub_route_uid = $1`, uid)
	}
	cleanup()
	t.Cleanup(cleanup)

	if _, err := pool.Exec(ctx, `
		INSERT INTO bus_segment_time
		  (sub_route_uid, direction, from_stop_uid, to_stop_uid, secs, sample_count)
		VALUES ($1, 0, 'P1', 'P2', 999, 50)`, uid); err != nil {
		t.Fatalf("seed segment: %v", err)
	}

	hist := fixtureHistory{plate: []segmentObs{
		{subRouteUID: uid, direction: 0, fromStopUID: "P1", toStopUID: "P2", secs: 140, sampleCount: 1},
	}}
	if err := computeSegmentTimes(ctx, pool, hist); err != nil {
		t.Fatalf("computeSegmentTimes: %v", err)
	}

	var secs, samples int
	if err := pool.QueryRow(ctx, `
		SELECT secs, sample_count FROM bus_segment_time
		WHERE sub_route_uid=$1 AND from_stop_uid='P1' AND to_stop_uid='P2'`, uid).
		Scan(&secs, &samples); err != nil {
		t.Fatalf("read back: %v", err)
	}
	if secs != 140 || samples != 1 {
		t.Errorf("P1->P2 = (%d, %d), want (140, 1): the plate pass writes unconditionally", secs, samples)
	}
}

// TestFillSegmentTimesFromDistance covers the fill pass's two promises: an empty
// hop gets an estimate scaled by distance and the route's observed pace, and an
// existing observed row is left exactly as it was. Without both, GTFS either
// keeps dropping route directions or silently loses a measured time to a guess.
func TestFillSegmentTimesFromDistance(t *testing.T) {
	pool := segmentEtaTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	if _, err := pool.Exec(ctx, `SELECT ST_DistanceSphere(
		ST_SetSRID(ST_MakePoint(121.5,25.0),4326), ST_SetSRID(ST_MakePoint(121.5,25.01),4326))`); err != nil {
		t.Skipf("PostGIS not available: %v", err)
	}
	ddl := []string{
		`CREATE TABLE IF NOT EXISTS bus_segment_time (
			sub_route_uid text NOT NULL, direction smallint NOT NULL,
			from_stop_uid text NOT NULL, to_stop_uid text NOT NULL,
			secs int NOT NULL, sample_count int NOT NULL,
			updated_at timestamptz NOT NULL DEFAULT NOW(),
			PRIMARY KEY (sub_route_uid, direction, from_stop_uid, to_stop_uid))`,
		`CREATE TABLE IF NOT EXISTS bus_stations (
			station_uid text PRIMARY KEY, station_name text NOT NULL, city text NOT NULL,
			position geometry(Point,4326), updated_at timestamptz DEFAULT CURRENT_TIMESTAMP)`,
		`CREATE TABLE IF NOT EXISTS bus_station_stop_map (
			station_id text NOT NULL, sub_route_uid text NOT NULL, direction int NOT NULL,
			route_name text, stop_uid text NOT NULL, stop_sequence int, station_name text,
			updated_at timestamptz NOT NULL DEFAULT now())`,
	}
	for _, stmt := range ddl {
		if _, err := pool.Exec(ctx, stmt); err != nil {
			t.Fatalf("ddl: %v", err)
		}
	}

	const uid = "TESTFILL0001"
	cleanup := func() {
		_, _ = pool.Exec(ctx, `DELETE FROM bus_station_stop_map WHERE sub_route_uid = $1`, uid)
		_, _ = pool.Exec(ctx, `DELETE FROM bus_segment_time WHERE sub_route_uid = $1`, uid)
		_, _ = pool.Exec(ctx, `DELETE FROM bus_stations WHERE station_uid LIKE 'TESTFILLST%'`)
	}
	cleanup()
	t.Cleanup(cleanup)

	// Three stops on one line, each hop the same 1 km, so the estimate for the
	// second hop must land on the first hop's observed 200s.
	for i, lon := range []float64{121.500, 121.510, 121.520} {
		if _, err := pool.Exec(ctx, `
			INSERT INTO bus_stations (station_uid, station_name, city, position)
			VALUES ($1, 'st', 'TestCity', ST_SetSRID(ST_MakePoint($2, 25.0), 4326))`,
			fmt.Sprintf("TESTFILLST%d", i+1), lon); err != nil {
			t.Fatalf("insert station: %v", err)
		}
		if _, err := pool.Exec(ctx, `
			INSERT INTO bus_station_stop_map
			  (station_id, sub_route_uid, direction, stop_uid, stop_sequence)
			VALUES ($1, $2, 0, $3, $4)`,
			fmt.Sprintf("TESTFILLST%d", i+1), uid, fmt.Sprintf("F%d", i+1), i+1); err != nil {
			t.Fatalf("insert stop map: %v", err)
		}
	}
	if _, err := pool.Exec(ctx, `
		INSERT INTO bus_segment_time
		  (sub_route_uid, direction, from_stop_uid, to_stop_uid, secs, sample_count)
		VALUES ($1, 0, 'F1', 'F2', 200, 9)`, uid); err != nil {
		t.Fatalf("seed observed: %v", err)
	}

	if err := fillSegmentTimesFromDistance(ctx, pool); err != nil {
		t.Fatalf("fillSegmentTimesFromDistance: %v", err)
	}

	var secs, samples int
	if err := pool.QueryRow(ctx, `
		SELECT secs, sample_count FROM bus_segment_time
		WHERE sub_route_uid=$1 AND from_stop_uid='F2' AND to_stop_uid='F3'`, uid).
		Scan(&secs, &samples); err != nil {
		t.Fatalf("estimated hop F2->F3 missing: %v", err)
	}
	if samples != segmentEstimatedSamples {
		t.Errorf("estimated sample_count = %d, want %d so readers can tell it apart", samples, segmentEstimatedSamples)
	}
	// Same distance, same route pace: within 10% of the observed hop.
	if secs < 180 || secs > 220 {
		t.Errorf("estimated F2->F3 = %ds, want ~200s from the equal-distance observed hop", secs)
	}

	if err := pool.QueryRow(ctx, `
		SELECT secs, sample_count FROM bus_segment_time
		WHERE sub_route_uid=$1 AND from_stop_uid='F1' AND to_stop_uid='F2'`, uid).
		Scan(&secs, &samples); err != nil {
		t.Fatalf("observed hop lost: %v", err)
	}
	if secs != 200 || samples != 9 {
		t.Errorf("observed hop = (%d, %d), want (200, 9) untouched", secs, samples)
	}
}
