package main

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// predictTestPool connects to the DATABASE_URL cluster and skips when it is
// unset, mirroring loaderTestPool.
func predictTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set; skipping batchNextDepartures integration test")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	return pool
}

// TestBatchNextDepartures is the regression test for the query rewrite: the
// original filter (type = true AND stopsequence = 0) matched no row the
// loader ever writes (the atomic writer stores frequency rows as type=true,
// stopsequence=-1, and timetable rows as type=false, stopsequence=<TDX
// StopSequence>), so batchNextDepartures always returned an empty map. This
// pins the fixed query against rows inserted through the same shape
// the atomic writer stores: timetable origin-stop selection (not sequence 0),
// service_day bitmask filtering (Monday=bit0..Sunday=bit6, mask2 order), and
// the frequency-window fallback.
func TestBatchNextDepartures(t *testing.T) {
	pool := predictTestPool(t)
	defer pool.Close()
	ctx := context.Background()

	provisionBusSinks(t, ctx, pool)

	const ttUID = "ZZ_PREDICT_TT"
	const freqUID = "ZZ_PREDICT_FREQ"
	cleanup := func() {
		_, _ = pool.Exec(ctx, `DELETE FROM bus_schedule WHERE sub_route_uid IN ($1, $2)`, ttUID, freqUID)
	}
	cleanup()
	defer cleanup()

	const weekdays = 31 // Mon-Fri: bits 0-4
	const allDays = 127 // Mon-Sun: bits 0-6

	insert := `INSERT INTO bus_schedule
		(sub_route_uid, direction, type, tripid, islowfloor, stopsequence,
		 "stop_uid/MinHeadwayMins", "stop_name/MaxHeadwayMins",
		 "arrival_time/StartTime", "departure_time/EndTime", service_day)
		VALUES ($1, $2, $3, $4, false, $5, $6, $7, $8::time, $8::time, $9)`

	// Timetable trip A: all days, stops 08:00/08:10/08:20.
	if _, err := pool.Exec(ctx, insert, ttUID, int16(0), false, "T1", int16(1), "S1", "Stop 1", "08:00:00", allDays); err != nil {
		t.Fatalf("insert trip A stop 1: %v", err)
	}
	if _, err := pool.Exec(ctx, insert, ttUID, int16(0), false, "T1", int16(2), "S2", "Stop 2", "08:10:00", allDays); err != nil {
		t.Fatalf("insert trip A stop 2: %v", err)
	}
	if _, err := pool.Exec(ctx, insert, ttUID, int16(0), false, "T1", int16(3), "S3", "Stop 3", "08:20:00", allDays); err != nil {
		t.Fatalf("insert trip A stop 3: %v", err)
	}

	// Timetable trip B: weekdays only, stops 09:00/09:10/09:20.
	if _, err := pool.Exec(ctx, insert, ttUID, int16(0), false, "T2", int16(1), "S1", "Stop 1", "09:00:00", weekdays); err != nil {
		t.Fatalf("insert trip B stop 1: %v", err)
	}
	if _, err := pool.Exec(ctx, insert, ttUID, int16(0), false, "T2", int16(2), "S2", "Stop 2", "09:10:00", weekdays); err != nil {
		t.Fatalf("insert trip B stop 2: %v", err)
	}
	if _, err := pool.Exec(ctx, insert, ttUID, int16(0), false, "T2", int16(3), "S3", "Stop 3", "09:20:00", weekdays); err != nil {
		t.Fatalf("insert trip B stop 3: %v", err)
	}

	// Frequency row: window 06:30-22:00, all days, on a different routeDirKey.
	freqInsert := `INSERT INTO bus_schedule
		(sub_route_uid, direction, type, tripid, islowfloor, stopsequence,
		 "stop_uid/MinHeadwayMins", "stop_name/MaxHeadwayMins",
		 "arrival_time/StartTime", "departure_time/EndTime", service_day)
		VALUES ($1, $2, true, '', false, -1, $3, $4, $5::time, $6::time, $7)`
	if _, err := pool.Exec(ctx, freqInsert, freqUID, int16(0), "10", "20", "06:30:00", "22:00:00", allDays); err != nil {
		t.Fatalf("insert frequency row: %v", err)
	}

	ttKey := routeDirKey{subRouteUID: ttUID, direction: 0}
	freqKey := routeDirKey{subRouteUID: freqUID, direction: 0}
	keys := []routeDirKey{ttKey, freqKey}

	const monday = 1  // mask2 bit order: Monday = bit0
	const sunday = 64 // mask2 bit order: Sunday = bit6

	// Query at 07:00 on Monday: trip A's origin stop (08:00) wins, not 08:10.
	got := batchNextDepartures(ctx, pool, keys, "07:00:00", monday)
	dep, ok := got[ttKey]
	if !ok {
		t.Fatal("07:00 Monday: expected a departure for the timetable route, got none")
	}
	if got, want := dep.Format("15:04:05"), "08:00:00"; got != want {
		t.Fatalf("07:00 Monday: departure = %s, want %s (origin stop, not stopsequence 0)", got, want)
	}

	// Query at 08:30 on Sunday: trip B is weekday-only, so no entry at all
	// (trip A's 08:00/08:10/08:20 are all before 08:30).
	got = batchNextDepartures(ctx, pool, keys, "08:30:00", sunday)
	if dep, ok := got[ttKey]; ok {
		t.Fatalf("08:30 Sunday: expected no departure (weekday-only trip B excluded), got %s", dep.Format("15:04:05"))
	}

	// Query at 08:30 on Monday: trip B applies, origin stop 09:00.
	got = batchNextDepartures(ctx, pool, keys, "08:30:00", monday)
	dep, ok = got[ttKey]
	if !ok {
		t.Fatal("08:30 Monday: expected a departure for the timetable route, got none")
	}
	if got, want := dep.Format("15:04:05"), "09:00:00"; got != want {
		t.Fatalf("08:30 Monday: departure = %s, want %s", got, want)
	}

	// Frequency route at 07:00: window already open (06:30-22:00), clamped to now.
	got = batchNextDepartures(ctx, pool, keys, "07:00:00", monday)
	dep, ok = got[freqKey]
	if !ok {
		t.Fatal("07:00: expected a departure for the frequency route (window open), got none")
	}
	if got, want := dep.Format("15:04:05"), "07:00:00"; got != want {
		t.Fatalf("07:00: frequency departure = %s, want %s (clamped to now)", got, want)
	}

	// Frequency route at 23:00: window closed (ends 22:00), no entry.
	got = batchNextDepartures(ctx, pool, keys, "23:00:00", monday)
	if dep, ok := got[freqKey]; ok {
		t.Fatalf("23:00: expected no departure (frequency window closed), got %s", dep.Format("15:04:05"))
	}
}
