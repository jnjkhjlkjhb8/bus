// Command export-fixtures dumps one raw_tdx dataset/partition to a JSON file for
// deterministic loader replay tests (ADR-0005: "Local tests replay exported
// raw_tdx fixtures — deterministic, no network"). It is read-only: it never
// writes to the database, only to the -out file.
//
// Usage:
//
//	DATABASE_URL=... go run ./scripts/export-fixtures \
//	  -table thsr_station -out services/functions/testdata/raw_tdx/thsr_station.json
//	DATABASE_URL=... go run ./scripts/export-fixtures \
//	  -table tra_dailytimetable -partcol traindate -part 2026-07-05 -out ...
//
// The reconstruction query is byte-for-byte the same shape as
// rawTDXSource.datasetJSON in services/functions/loader.go: to_jsonb of each row
// minus the fetched_at (and partition) bookkeeping columns, with the
// thsr_dailytimetable traindate re-derived as a YYYY-MM-DD string. A fixture
// exported here therefore replays identically through the loader. The SQL is
// duplicated rather than imported because that unexported helper lives in
// another package main, which a separate command cannot import.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	table := flag.String("table", "", "raw_tdx table name")
	partCol := flag.String("partcol", "", "partition column (city|system|traindate), empty for unpartitioned")
	part := flag.String("part", "", "partition value")
	out := flag.String("out", "", "output JSON file")
	flag.Parse()
	if *table == "" || *out == "" {
		fmt.Fprintln(os.Stderr, "table and out are required")
		os.Exit(2)
	}

	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		fmt.Fprintln(os.Stderr, "DATABASE_URL not set")
		os.Exit(2)
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer pool.Close()

	body, err := datasetJSON(context.Background(), pool, *table, *partCol, *part)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if err := os.WriteFile(*out, body, 0o644); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("wrote %d bytes to %s\n", len(body), *out)
}

// datasetJSON reconstructs the lowercased-JSON array for one raw_tdx partition,
// mirroring rawTDXSource.datasetJSON. partCol is interpolated into the query, so
// callers must pass only trusted column names (this command is a developer tool
// run against known raw_tdx tables).
func datasetJSON(ctx context.Context, pool *pgxpool.Pool, table, partCol, partVal string) ([]byte, error) {
	strip := "ARRAY['fetched_at']::text[]"
	if partCol != "" {
		strip = fmt.Sprintf("ARRAY['fetched_at','%s']::text[]", partCol)
	}
	elem := fmt.Sprintf("(to_jsonb(t) - %s)", strip)
	if table == "thsr_dailytimetable" {
		// Re-derive traindate as a YYYY-MM-DD string; the landing column is
		// timestamptz but the transform historically decoded a date-only string.
		elem = fmt.Sprintf("(%s || jsonb_build_object('traindate', to_char(t.traindate, 'YYYY-MM-DD')))", elem)
	}
	where := ""
	args := []any{}
	if partCol != "" {
		where = fmt.Sprintf("WHERE %s = $1", partCol)
		args = append(args, partVal)
	}
	q := fmt.Sprintf(
		`SELECT COALESCE(jsonb_agg(%s), '[]'::jsonb) FROM raw_tdx.%s t %s`,
		elem, table, where)
	var body []byte
	if err := pool.QueryRow(ctx, q, args...).Scan(&body); err != nil {
		return nil, err
	}
	return body, nil
}
