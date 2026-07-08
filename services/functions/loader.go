package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5/pgxpool"
)

// loadSource is the seam between the loader and the raw landing store. The
// production adapter (rawTDXSource) reconstructs a lowercased-JSON array from a
// raw_tdx table/partition; the test adapters (fakeLoadSource) serve committed
// bytes. table/partCol/partVal identify one partition; an unpartitioned dataset
// passes partCol="" and partVal="".
type loadSource interface {
	datasetJSON(ctx context.Context, table, partCol, partVal string) ([]byte, time.Time, error)
}

// loadSpec is one dataset's loader recipe: which raw_tdx table and partitions to
// read, and the transform that consumes the reconstructed decoder. load's SQL
// body is byte-identical to the legacy transform it was split from (ADR-0005:
// transforms are reused, not rewritten). report, when set, names the env-schema
// tables to emit a data-quality line for after a successful load; Redis-only
// specs leave it nil.
type loadSpec struct {
	key        string
	table      string
	partCol    string
	partitions func() []string
	load       func(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, rc *redis.Client, part string) error
	report     []qualityTarget
}

// qualityTarget describes one env-schema table's post-load quality probe: the
// text columns whose empty-or-NULL ratio matters (names) and the columns whose
// NULL ratio matters (coordinates, stored as PostGIS geometry, so empty-string
// does not apply). reportQuality runs one aggregate query per target.
type qualityTarget struct {
	table    string
	textCols []string
	geoCols  []string
}

// errLoadStale marks a partition whose newest fetched_at is older than the
// freshness window; the loader skips it rather than overwriting good data with
// a landing that never happened.
var errLoadStale = errors.New("raw_tdx partition stale")

// staleAfter is the freshness window. Landing runs at 03:00, loads at 03:30; a
// partition older than 27h means the last landing failed or was skipped, so the
// loader leaves the env schema untouched (ADR-0005 coordination).
const staleAfter = 27 * time.Hour

// isStale reports whether a partition landed at fetchedAt is too old to load.
func isStale(fetchedAt time.Time) bool {
	return time.Since(fetchedAt) > staleAfter
}

// runLoad transforms the named datasets from src into db (and rc for the
// Redis-only datasets). keys selects registry entries by loadSpec.key; an empty
// keys slice loads every registered dataset.
func runLoad(ctx context.Context, src loadSource, db *pgxpool.Pool, rc *redis.Client, keys []string) error {
	specs := loaderRegistry(src)
	if len(keys) > 0 {
		want := map[string]bool{}
		for _, k := range keys {
			want[k] = true
		}
		filtered := specs[:0:0]
		for _, s := range specs {
			if want[s.key] {
				filtered = append(filtered, s)
			}
		}
		specs = filtered
	}
	return runLoadSpecs(ctx, src, db, rc, specs)
}

// runLoadSpecs is the registry-parameterized core: per spec, per partition, it
// reads the reconstructed JSON, staleness-checks fetched_at, wraps the bytes in
// a *json.Decoder, and calls the transform. Per-partition failures are logged
// and do not abort the run (mirrors ingestRaw's per-endpoint isolation).
func runLoadSpecs(ctx context.Context, src loadSource, db *pgxpool.Pool, rc *redis.Client, specs []loadSpec) error {
	for _, spec := range specs {
		parts := spec.partitions()
		for _, part := range parts {
			body, fetchedAt, err := src.datasetJSON(ctx, spec.table, spec.partCol, part)
			if err != nil {
				log.Infof("[LOAD] action=read event=error dataset=%s partition=%s error=%v", spec.key, part, err)
				continue
			}
			if isStale(fetchedAt) {
				log.Infof("[LOAD] action=skip event=stale dataset=%s partition=%s fetched_at=%s reason=%v", spec.key, part, fetchedAt.Format(time.RFC3339), errLoadStale)
				continue
			}
			dec := json.NewDecoder(bytes.NewReader(body))
			if err := spec.load(ctx, dec, db, rc, part); err != nil {
				log.Infof("[LOAD] action=transform event=error dataset=%s partition=%s error=%v", spec.key, part, err)
				continue
			}
			log.Infof("[LOAD] action=transform event=success dataset=%s partition=%s", spec.key, part)
		}
		reportQuality(ctx, db, spec)
	}
	return nil
}

// reportQuality logs one data-quality line per target table after a dataset
// loads: the row count plus the empty-or-NULL ratio of key text columns and the
// NULL ratio of key coordinate columns. It is a cheap post-load sanity signal,
// not a stored report. A query error is logged and skipped so it never blocks a
// load.
func reportQuality(ctx context.Context, db *pgxpool.Pool, spec loadSpec) {
	for _, t := range spec.report {
		selects := []string{"COUNT(*) AS rows"}
		var cols []string
		for _, c := range t.textCols {
			selects = append(selects, fmt.Sprintf(
				"COUNT(*) FILTER (WHERE %q IS NULL OR %q = '') AS %s_empty", c, c, c))
			cols = append(cols, c)
		}
		for _, c := range t.geoCols {
			selects = append(selects, fmt.Sprintf(
				"COUNT(*) FILTER (WHERE %q IS NULL) AS %s_empty", c, c))
			cols = append(cols, c)
		}
		q := fmt.Sprintf("SELECT %s FROM %s", strings.Join(selects, ", "), t.table)
		vals := make([]int64, 1+len(cols))
		dest := make([]any, len(vals))
		for i := range vals {
			dest[i] = &vals[i]
		}
		if err := db.QueryRow(ctx, q).Scan(dest...); err != nil {
			log.Infof("[LOAD] action=quality_report event=query_error dataset=%s table=%s error=%v", spec.key, t.table, err)
			continue
		}
		rows := vals[0]
		var b strings.Builder
		fmt.Fprintf(&b, "[LOAD] action=quality_report dataset=%s table=%s rows=%d", spec.key, t.table, rows)
		for i, c := range cols {
			empty := vals[i+1]
			ratio := 0.0
			if rows > 0 {
				ratio = float64(empty) / float64(rows)
			}
			fmt.Fprintf(&b, " %s_empty_ratio=%.3f", c, ratio)
		}
		log.Infof("%s", b.String())
	}
}

// rawTDXSource reconstructs lowercased-JSON arrays from the shared raw_tdx
// schema. It reads raw_tdx.<table> (schema-qualified, so PG_SCHEMA search_path
// on the sink pool does not affect it) minus the partition and fetched_at
// columns, and returns the newest fetched_at in the partition as the staleness
// signal.
type rawTDXSource struct {
	pool *pgxpool.Pool
}

// datasetJSON returns to_jsonb of every row in the partition (with the partition
// column and fetched_at stripped, since those are loader bookkeeping, not TDX
// fields) plus MAX(fetched_at). An empty partition yields "[]" and the epoch
// time, which isStale treats as stale (skipped).
//
// thsr_dailytimetable.traindate is timestamptz on the landing table, but the
// original TDX payload's TrainDate is a YYYY-MM-DD string and the transform's
// train_date temp column is a date; to_jsonb would serialize the timestamptz as
// a full timestamp. The traindateColumn override re-derives the YYYY-MM-DD form
// back into the traindate JSON key so the reconstructed payload matches what the
// transform historically decoded.
func (r rawTDXSource) datasetJSON(ctx context.Context, table, partCol, partVal string) ([]byte, time.Time, error) {
	if err := validateRawTarget(table, partCol); err != nil {
		return nil, time.Time{}, err
	}
	// Build the per-row jsonb: to_jsonb minus bookkeeping columns (fetched_at and,
	// when partitioned, the partition column), with the thsr_dailytimetable
	// traindate normalized to YYYY-MM-DD (see doc comment). The jsonb `-` operator
	// takes a text[] of keys to drop; partCol is whitelisted by validateRawTarget
	// so it is not injectable.
	strip := "ARRAY['fetched_at']::text[]"
	if partCol != "" {
		strip = fmt.Sprintf("ARRAY['fetched_at','%s']::text[]", partCol)
	}
	elem := fmt.Sprintf("(to_jsonb(t) - %s)", strip)
	if table == "thsr_dailytimetable" {
		// Re-insert traindate as a YYYY-MM-DD string. When traindate is the
		// partition column it was stripped above; jsonb || sets it either way.
		elem = fmt.Sprintf("(%s || jsonb_build_object('traindate', to_char(t.traindate, 'YYYY-MM-DD')))", elem)
	}
	where := ""
	args := []any{}
	if partCol != "" {
		where = rawPartitionWhere(table, partCol)
		args = append(args, partVal)
	}
	q := fmt.Sprintf(
		`SELECT COALESCE(jsonb_agg(%s), '[]'::jsonb), COALESCE(MAX(t.fetched_at), 'epoch') FROM raw_tdx.%s t %s`,
		elem, table, where)
	var body []byte
	var fetchedAt time.Time
	if err := r.pool.QueryRow(ctx, q, args...).Scan(&body, &fetchedAt); err != nil {
		return nil, time.Time{}, err
	}
	return body, fetchedAt, nil
}

// railDateWindow returns today..today+n as YYYY-MM-DD strings, matching the
// ingestor's landing window (day 0 = today) so every landed timetable partition
// has a loader partition.
func railDateWindow(n int) []string {
	today := time.Now()
	out := make([]string, 0, n+1)
	for i := 0; i <= n; i++ {
		out = append(out, today.AddDate(0, 0, i).Format(time.DateOnly))
	}
	return out
}

// loaderRegistry lists every dataset the loader knows how to transform, in the
// order it loads them. src is captured by the bus spec because loadBus needs to
// read six correlated raw_tdx tables (a single decoder cannot feed a
// multi-endpoint correlation); every other spec ignores it and uses the decoder
// runLoadSpecs hands its load func. Partition enumerators reuse the ingestor's
// existing package vars so landed and loaded partitions always agree.
//
// Ordering invariant: the "bus_operator" spec MUST precede the "bus" spec.
// runLoadSpecs iterates this slice sequentially, so the staleness-gated
// bus_operator upsert has already written bus_operators before loadBus reads
// them back via loadBusOperatorMap. Do not reorder these two.
func loaderRegistry(src loadSource) []loadSpec {
	allCities := func() []string { return cities }
	bikeCities := func() []string {
		var out []string
		for _, c := range cities {
			if !ingestBikeSkip[c] {
				out = append(out, c)
			}
		}
		return out
	}
	dailyTimetableCities := func() []string {
		var out []string
		for _, c := range cities {
			if !busDailyTimetableSkip(c) {
				out = append(out, c)
			}
		}
		return out
	}
	single := func() []string { return []string{""} }
	return []loadSpec{
		{key: "bus_operator", table: "bus_operator", partCol: "city", partitions: allCities,
			load: func(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, _ *redis.Client, part string) error {
				_, err := loadBusOperators(ctx, dec, db, part)
				return err
			}},
		{key: "bus", table: "bus_route", partCol: "city", partitions: allCities,
			load: func(ctx context.Context, _ *json.Decoder, db *pgxpool.Pool, rc *redis.Client, part string) error {
				return loadBus(ctx, src, db, rc, part)
			},
			report: []qualityTarget{
				{table: "bus_subroutes", textCols: []string{"route_name", "sub_route_name", "depart", "destin"}},
				{table: "bus_static", textCols: []string{"route_name", "sub_route_name"}},
				{table: "bus_stations", textCols: []string{"station_name"}, geoCols: []string{"position"}},
			}},
		{key: "bus_dailytimetable", table: "bus_dailytimetable", partCol: "city", partitions: dailyTimetableCities, load: loadBusDailyTimetable},
		{key: "bike", table: "bike_station", partCol: "city", partitions: bikeCities, load: loadBikeStations,
			report: []qualityTarget{{table: "bike_stations", textCols: []string{"name", "address"}, geoCols: []string{"geom"}}}},
		{key: "mrt_station", table: "metro_station", partCol: "system", partitions: func() []string { return ingestMetroStationSystems }, load: loadMrtStations,
			report: []qualityTarget{{table: "mrt_station", textCols: []string{"name"}, geoCols: []string{"stationposition"}}}},
		{key: "mrt_firstlast", table: "metro_schedule", partCol: "system", partitions: func() []string { return ingestMetroFirstLast }, load: loadMrtFirstlast},
		{key: "mrt_odfare", table: "metro_odfare", partCol: "system", partitions: func() []string { return ingestMetroODFare }, load: loadMrtJourneyMatrix},
		{key: "tra_station", table: "tra_station", partCol: "", partitions: single, load: loadTraStation,
			report: []qualityTarget{{table: "tra_stations", textCols: []string{"name"}, geoCols: []string{"geom"}}}},
		{key: "thsr_station", table: "thsr_station", partCol: "", partitions: single, load: loadThsrStation,
			report: []qualityTarget{{table: "thsr_stations", textCols: []string{"name"}, geoCols: []string{"geom"}}}},
		{key: "tra_fare", table: "tra_odfare", partCol: "", partitions: single, load: loadTraFare},
		{key: "thsr_fare", table: "thsr_odfare", partCol: "", partitions: single, load: loadThsrFare},
		{key: "tra_timetable", table: "tra_dailytimetable", partCol: "traindate", partitions: func() []string { return railDateWindow(60) }, load: loadTraTimetable},
		{key: "thsr_timetable", table: "thsr_dailytimetable", partCol: "traindate", partitions: func() []string { return railDateWindow(45) }, load: loadThsrTimetable},
	}
}
