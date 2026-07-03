package main

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Integration test — requires DATABASE_URL. Verifies dumpRawTDX against the real
// raw_tdx schema: empty-array 0-row insert, partition replace, and that a
// non-whitelisted table returns an error (the condition under which callApi skips
// caching the If-Modified-Since value).
func TestDumpRawTDXIntegration(t *testing.T) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set; skipping raw_tdx integration test")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer pool.Close()

	prev := ingestDB
	ingestDB = pool
	defer func() { ingestDB = prev }()

	ctx := context.Background()
	var provisioned bool
	if err := pool.QueryRow(ctx,
		"SELECT to_regclass('raw_tdx.bus_route') IS NOT NULL").Scan(&provisioned); err != nil {
		t.Fatalf("probe raw_tdx schema: %v", err)
	}
	if !provisioned {
		t.Skip("raw_tdx schema not provisioned; skipping raw_tdx integration test")
	}
	const city = "ZZ_TEST_CITY"
	cleanup := func() { _, _ = pool.Exec(ctx, "DELETE FROM raw_tdx.bus_route WHERE city=$1", city) }
	cleanup()
	defer cleanup()

	if err := dumpRawTDX(ctx, "bus_route", "city", city, []byte("[]")); err != nil {
		t.Fatalf("empty-array dump: %v", err)
	}
	if n := countCity(t, pool, city); n != 0 {
		t.Fatalf("empty array: got %d rows, want 0", n)
	}

	body := []byte(`[{"RouteUID":"ZZR1","RouteName":{"Zh_tw":"測"},"VersionID":1}]`)
	if err := dumpRawTDX(ctx, "bus_route", "city", city, body); err != nil {
		t.Fatalf("single-row dump: %v", err)
	}
	if n := countCity(t, pool, city); n != 1 {
		t.Fatalf("single row: got %d rows, want 1", n)
	}

	body2 := []byte(`[{"RouteUID":"ZZR2","VersionID":2},{"RouteUID":"ZZR3","VersionID":3}]`)
	if err := dumpRawTDX(ctx, "bus_route", "city", city, body2); err != nil {
		t.Fatalf("partition-replace dump: %v", err)
	}
	if n := countCity(t, pool, city); n != 2 {
		t.Fatalf("partition replace: got %d rows, want 2", n)
	}

	if err := dumpRawTDX(ctx, "pg_class", "city", city, body); err == nil {
		t.Fatal("expected error for non-whitelisted table, got nil")
	}
}

func countCity(t *testing.T, pool *pgxpool.Pool, city string) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		"SELECT count(*) FROM raw_tdx.bus_route WHERE city=$1", city).Scan(&n); err != nil {
		t.Fatalf("count: %v", err)
	}
	return n
}
