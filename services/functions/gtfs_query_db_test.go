package main

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
)

// gtfsTestPool opens the DATABASE_URL pool these tests share, or skips.
//
// Both tests need a database with raw_tdx provisioned. CI's postgres has neither
// that schema nor PostGIS, so both skip there; they are for a dev or staging
// database, and the second one is opt-in because it reads.
func gtfsTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set; skipping GTFS statement integration test")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	t.Cleanup(pool.Close)
	var provisioned bool
	if err := pool.QueryRow(context.Background(),
		`SELECT to_regclass('raw_tdx.bus_route') IS NOT NULL`).Scan(&provisioned); err != nil {
		t.Fatalf("probe raw_tdx schema: %v", err)
	}
	if !provisioned {
		t.Skip("raw_tdx schema not provisioned; skipping GTFS statement integration test")
	}
	return pool
}

// TestGTFSStatementsPlan asserts every statement in the feed resolves against the
// real schema.
//
// TestGTFSFilesAreWellFormed only inspects the strings. A statement naming a
// column that does not exist is invisible until the nightly export runs and the
// feed silently loses a file — runGTFSExport logs rather than returns, precisely
// so a failed export cannot fail the load that preceded it. This catches it
// first.
//
// EXPLAIN rather than execution: it parses the statement and resolves every
// relation and column without reading a row. That matters because the target is
// a 2 GB Azure instance where stop_times is six million rows, and a test that
// scans it to prove it parses would be a worse problem than the one it finds.
func TestGTFSStatementsPlan(t *testing.T) {
	pool := gtfsTestPool(t)
	for _, file := range gtfsFiles("20260801-0345") {
		t.Run(file.name, func(t *testing.T) {
			if _, err := pool.Exec(context.Background(), "EXPLAIN "+file.sql); err != nil {
				t.Errorf("%s does not plan: %v", file.name, err)
			}
		})
	}
}

// TestGTFSSectionFareUnits checks the sectioned-bus fare arithmetic against the
// zone layout it is meant to describe.
//
// Zones alternate core, buffer, core: index 0 and 2 are sections either side of
// the buffer at index 1. A rider pays one unit per section entered, and entering
// a buffer is not entering a section — only passing clear through one is. The
// expression got that wrong for a leg starting and ending inside the same buffer
// (it counted -1 crossings and priced the ride at zero), which is why the
// same-index cases are here.
//
// It needs a database only as a calculator: no schema, no fixtures.
func TestGTFSSectionFareUnits(t *testing.T) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Skip("DATABASE_URL not set; skipping")
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer pool.Close()

	// A route with two buffer zones: 0 core, 1 buffer, 2 core, 3 buffer, 4 core.
	for _, c := range []struct{ from, to, want int }{
		{0, 0, 1}, // within the first section
		{0, 1, 1}, // into the buffer, no section crossed
		{0, 2, 2}, // clear through the buffer
		{0, 3, 2}, // through the first, into the second
		{0, 4, 3}, // through both
		{1, 1, 1}, // begins and ends inside one buffer
		{1, 2, 1},
		{1, 3, 1}, // buffer to buffer, neither crossed whole
		{1, 4, 2},
		{2, 4, 2},
		{3, 3, 1},
		{3, 4, 1},
		{4, 4, 1},
	} {
		var got int
		if err := pool.QueryRow(context.Background(),
			`SELECT `+busSectionUnitsSQL("$1::int", "$2::int"), c.from, c.to).Scan(&got); err != nil {
			t.Fatalf("zone %d->%d: %v", c.from, c.to, err)
		}
		if got != c.want {
			t.Errorf("zone %d->%d: %d section fares, want %d", c.from, c.to, got, c.want)
		}
	}
}

// TestGTFSFaresAreConsistent asserts the fare files reference each other and
// stops.txt, and that fare_products stays one row per price.
//
// Both properties are how this fare model differs from the official MOTC feed's,
// and both fail silently. A leg rule naming an area stop_areas never declares is
// a broken feed that still exports; and a product per station pair rather than
// per price is what makes the official fare_products.txt 2.8 GB and its
// fare_leg_rules 3.7 GB, together 88% of an archive no validator can open.
//
// Written as invariants over whatever is landed rather than against seeded rows:
// the rail fare tables have no city column to scope a fixture to, and inserting
// stations into a shared raw_tdx to test an exporter is not worth the blast
// radius.
func TestGTFSFaresAreConsistent(t *testing.T) {
	if os.Getenv("GTFS_DB_HEAVY_TESTS") != "1" {
		t.Skip("GTFS_DB_HEAVY_TESTS != 1; skipping (this one scans stop_times)")
	}
	pool := gtfsTestPool(t)
	ctx := context.Background()

	for _, c := range []struct{ name, query string }{
		// An empty area is a wildcard, not a reference: a flat-fare network
		// prices every leg on it regardless of where the rider boards.
		{"leg rules naming an area areas.txt omits", `
			SELECT count(*) FROM (` + gtfsFareLegRulesSQL + `) r
			WHERE (r.from_area_id <> '' AND r.from_area_id NOT IN (SELECT area_id FROM (` + gtfsAreasSQL + `) a1))
			   OR (r.to_area_id   <> '' AND r.to_area_id   NOT IN (SELECT area_id FROM (` + gtfsAreasSQL + `) a2))`},
		{"leg rules naming a product fare_products.txt omits", `
			SELECT count(*) FROM (` + gtfsFareLegRulesSQL + `) r
			WHERE r.fare_product_id NOT IN (SELECT fare_product_id FROM (` + gtfsFareProductsSQL + `) p)`},
		{"stop_areas naming a stop stops.txt omits", `
			SELECT count(*) FROM (` + gtfsStopAreasSQL + `) sa
			WHERE sa.stop_id NOT IN (SELECT stop_id FROM (` + gtfsStopsSQL + `) s)`},
		{"areas with no stop in them", `
			SELECT count(*) FROM (` + gtfsAreasSQL + `) a
			WHERE a.area_id NOT IN (SELECT area_id FROM (` + gtfsStopAreasSQL + `) sa)`},
		{"leg rules on a network no route belongs to", `
			SELECT count(*) FROM (` + gtfsFareLegRulesSQL + `) r
			WHERE r.network_id NOT IN (SELECT network_id FROM (` + gtfsRoutesSQL + `) ro)`},
	} {
		t.Run(c.name, func(t *testing.T) {
			var bad int
			if err := pool.QueryRow(ctx, c.query).Scan(&bad); err != nil {
				t.Fatalf("query: %v", err)
			}
			if bad != 0 {
				t.Errorf("%d %s", bad, c.name)
			}
		})
	}

	var products, rules int
	if err := pool.QueryRow(ctx,
		`SELECT (SELECT count(*) FROM (`+gtfsFareProductsSQL+`) p),
		        (SELECT count(*) FROM (`+gtfsFareLegRulesSQL+`) r)`).Scan(&products, &rules); err != nil {
		t.Fatalf("count: %v", err)
	}
	t.Logf("fare products=%d leg rules=%d", products, rules)
	if rules == 0 {
		// Empty fare files are only a fault when there were fares to read. A
		// database with none landed correctly prices nothing.
		var landed int
		if err := pool.QueryRow(ctx, `
			SELECT (SELECT count(*) FROM raw_tdx.bus_routefare)
			     + (SELECT count(*) FROM raw_tdx.tra_odfare)
			     + (SELECT count(*) FROM raw_tdx.thsr_odfare)
			     + (SELECT count(*) FROM raw_tdx.metro_odfare)`).Scan(&landed); err != nil {
			t.Fatalf("count landed fares: %v", err)
		}
		if landed == 0 {
			t.Skip("no fares landed; nothing to price")
		}
		t.Fatalf("%d fare records landed and not one leg rule came out", landed)
	}
	// A product per pair is the failure mode; a handful of distinct prices
	// serving thousands of pairs is the intended shape. The bound is loose on
	// purpose — it is catching an order of magnitude, not tuning a ratio — and
	// it only applies once there are enough pairs for the ratio to mean
	// anything. A database with three landed fares has no shape to check.
	if rules >= 200 && products > rules/10 {
		t.Errorf("fare_products has %d rows for %d leg rules: products are being emitted per pair, not per price",
			products, rules)
	}
}

// TestGTFSPathwaysAreConsistent asserts every entrance pathway connects two
// stops stops.txt declares, of the location types GTFS allows at the ends of a
// pathway.
//
// A pathway is the one file where a dangling reference is invisible in the feed
// and fatal in a router: it silently detaches an entrance, and the station keeps
// working through its parent_station so nothing looks wrong. GTFS also forbids a
// station (location_type 1) at either end, which is easy to reach for by
// accident since the entrance's parent is one.
func TestGTFSPathwaysAreConsistent(t *testing.T) {
	if os.Getenv("GTFS_DB_HEAVY_TESTS") != "1" {
		t.Skip("GTFS_DB_HEAVY_TESTS != 1; skipping (this one scans stop_times)")
	}
	pool := gtfsTestPool(t)
	ctx := context.Background()

	for _, c := range []struct{ name, query string }{
		{"pathways naming a stop stops.txt omits", `
			SELECT count(*) FROM (` + gtfsPathwaysSQL + `) p
			WHERE p.from_stop_id NOT IN (SELECT stop_id FROM (` + gtfsStopsSQL + `) s1)
			   OR p.to_stop_id   NOT IN (SELECT stop_id FROM (` + gtfsStopsSQL + `) s2)`},
		{"pathways ending on a station rather than an entrance or platform", `
			SELECT count(*) FROM (` + gtfsPathwaysSQL + `) p
			JOIN (` + gtfsStopsSQL + `) a ON a.stop_id = p.from_stop_id
			JOIN (` + gtfsStopsSQL + `) b ON b.stop_id = p.to_stop_id
			WHERE a.location_type <> 2 OR b.location_type <> 0`},
		{"pathways whose ends belong to different stations", `
			SELECT count(*) FROM (` + gtfsPathwaysSQL + `) p
			JOIN (` + gtfsStopsSQL + `) a ON a.stop_id = p.from_stop_id
			JOIN (` + gtfsStopsSQL + `) b ON b.stop_id = p.to_stop_id
			WHERE a.parent_station <> b.parent_station`},
		{"duplicate pathway_id", `
			SELECT COALESCE(sum(n) - count(*), 0) FROM (
			  SELECT count(*) AS n FROM (` + gtfsPathwaysSQL + `) p GROUP BY p.pathway_id
			) d`},
	} {
		t.Run(c.name, func(t *testing.T) {
			var bad int
			if err := pool.QueryRow(ctx, c.query).Scan(&bad); err != nil {
				t.Fatalf("query: %v", err)
			}
			if bad != 0 {
				t.Errorf("%d %s", bad, c.name)
			}
		})
	}

	// Every entrance should be reachable. One with no pathway is an entrance a
	// router can route to and not out of.
	var stranded int
	if err := pool.QueryRow(ctx, `
		SELECT count(*) FROM (`+gtfsStopsSQL+`) s
		WHERE s.location_type = 2
		  AND s.stop_id NOT IN (SELECT from_stop_id FROM (`+gtfsPathwaysSQL+`) p)`).Scan(&stranded); err != nil {
		t.Fatalf("stranded: %v", err)
	}
	if stranded != 0 {
		t.Errorf("%d entrances have no pathway to their platform", stranded)
	}
}

// TestGTFSTranslationsReferenceEmittedRecords asserts translations.txt never
// names a record the file it translates does not contain.
//
// This is the one way the translations query can be wrong without failing.
// It re-runs agency, stops and routes in English, so if reading the other
// language changed which rows survive — or renumbered a synthetic entrance key —
// the record_ids would drift and consumers would silently drop every
// translation. Running both languages and comparing is the only check that sees
// it, which is why it exists despite the cost.
//
// Opt-in: unlike the plan test this executes the queries, and the stops query
// scans stop_times to work out which stops are served. Run it when the language
// plumbing changes, not on every suite.
func TestGTFSTranslationsReferenceEmittedRecords(t *testing.T) {
	if os.Getenv("GTFS_DB_HEAVY_TESTS") != "1" {
		t.Skip("GTFS_DB_HEAVY_TESTS != 1; skipping (this one scans stop_times)")
	}
	pool := gtfsTestPool(t)
	ctx := context.Background()

	for _, c := range []struct{ table, emitted, idColumn string }{
		{"agency", gtfsAgencySQL, "agency_id"},
		{"stops", gtfsStopsSQL, "stop_id"},
		{"routes", gtfsRoutesSQL, "route_id"},
	} {
		t.Run(c.table, func(t *testing.T) {
			var translated, dangling, emitted int
			var sample *string
			err := pool.QueryRow(ctx, `
				SELECT count(*),
				       count(*) FILTER (WHERE tr.record_id NOT IN (SELECT `+c.idColumn+` FROM (`+c.emitted+`) e)),
				       min(tr.record_id) FILTER (WHERE tr.record_id NOT IN (SELECT `+c.idColumn+` FROM (`+c.emitted+`) e2)),
				       (SELECT count(*) FROM (`+c.emitted+`) e3)
				FROM (`+gtfsTranslationsSQL+`) tr
				WHERE tr.table_name = $1`, c.table).Scan(&translated, &dangling, &sample, &emitted)
			if err != nil {
				t.Fatalf("compare: %v", err)
			}
			// Nothing translated is only a fault when there was something to
			// translate. A database with no landed stops emits no stops.txt and
			// correctly translates none of it.
			if emitted > 0 && translated == 0 {
				t.Errorf("%s: %s.txt has %d rows and none of them are translated",
					c.table, c.table, emitted)
			}
			if dangling != 0 {
				got := "<null>"
				if sample != nil {
					got = *sample
				}
				t.Errorf("%s: %d of %d translation rows name a record %s.txt does not contain, e.g. %q",
					c.table, dangling, translated, c.table, got)
			}
		})
	}
}
