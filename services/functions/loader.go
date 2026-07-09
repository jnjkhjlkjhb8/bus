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
	load       func(ctx context.Context, dec *json.Decoder, sink loadSink, part string) error
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
	sink := pgLoadSink{db: db, rc: rc}
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
			if err := spec.load(ctx, dec, sink, part); err != nil {
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

// datasetJSON returns a JSON array of every row in the partition (with the
// partition column and fetched_at stripped, since those are loader bookkeeping,
// not TDX fields) plus the newest fetched_at. Rows are serialized one at a time
// on the server and concatenated here: a single jsonb_agg over a partition with
// large jsonb columns (bus_routefare odfares) expands to a multi-GB in-memory
// tree and can OOM the 2 GB database server, so the per-statement working set
// must stay one row. An empty partition yields "[]" and a zero time, which
// isStale treats as stale (skipped).
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
		`SELECT %s::text, t.fetched_at FROM raw_tdx.%s t %s`,
		elem, table, where)
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, time.Time{}, err
	}
	defer rows.Close()
	var buf bytes.Buffer
	buf.WriteByte('[')
	var fetchedAt time.Time
	for rows.Next() {
		var rowJSON []byte
		var ft time.Time
		if err := rows.Scan(&rowJSON, &ft); err != nil {
			return nil, time.Time{}, err
		}
		if buf.Len() > 1 {
			buf.WriteByte(',')
		}
		buf.Write(rowJSON)
		if ft.After(fetchedAt) {
			fetchedAt = ft
		}
	}
	if err := rows.Err(); err != nil {
		return nil, time.Time{}, err
	}
	buf.WriteByte(']')
	return buf.Bytes(), fetchedAt, nil
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

// loaderBinding is one dataset's loader implementation: the transform and the
// optional post-load quality targets. It is joined onto the structural facts
// (table, partition column, partition enumerator, order) the datasetRegistry
// owns, keyed by loadKey.
type loaderBinding struct {
	load   func(ctx context.Context, dec *json.Decoder, sink loadSink, part string) error
	report []qualityTarget
}

// loaderTransforms maps each dataset's loadKey to its transform. src is captured
// by the bus binding because loadBus reads six correlated raw_tdx tables (a
// single decoder cannot feed a multi-endpoint correlation); the standalone
// copy-upsert transforms ignore it and consume the decoder runLoadSpecs hands
// them.
func loaderTransforms(src loadSource) map[string]loaderBinding {
	return map[string]loaderBinding{
		"bus_operator": {load: func(ctx context.Context, dec *json.Decoder, sink loadSink, part string) error {
			_, err := loadBusOperators(ctx, dec, sink.pool(), part)
			return err
		}},
		"bus": {
			load: func(ctx context.Context, _ *json.Decoder, sink loadSink, part string) error {
				return loadBus(ctx, src, sink.pool(), sink.redis(), part)
			},
			report: []qualityTarget{
				{table: "bus_subroutes", textCols: []string{"route_name", "sub_route_name", "depart", "destin"}},
				{table: "bus_static", textCols: []string{"route_name", "sub_route_name"}},
				{table: "bus_stations", textCols: []string{"station_name"}, geoCols: []string{"position"}},
			}},
		"bus_dailytimetable": {load: func(ctx context.Context, dec *json.Decoder, sink loadSink, part string) error {
			return loadBusDailyTimetable(ctx, dec, sink.pool(), sink.redis(), part)
		}},
		"bike": {load: loadBikeStations,
			report: []qualityTarget{{table: "bike_stations", textCols: []string{"name", "address"}, geoCols: []string{"geom"}}}},
		"mrt_station": {load: loadMrtStations,
			report: []qualityTarget{{table: "mrt_station", textCols: []string{"name"}, geoCols: []string{"stationposition"}}}},
		"mrt_firstlast": {load: loadMrtFirstlast},
		"mrt_odfare": {load: func(ctx context.Context, dec *json.Decoder, sink loadSink, part string) error {
			return loadMrtJourneyMatrix(ctx, dec, sink.pool(), sink.redis(), part)
		}},
		"tra_station": {load: loadTraStation,
			report: []qualityTarget{{table: "tra_stations", textCols: []string{"name"}, geoCols: []string{"geom"}}}},
		"thsr_station": {
			load: func(ctx context.Context, dec *json.Decoder, sink loadSink, part string) error {
				return loadThsrStation(ctx, dec, sink.pool(), sink.redis(), part)
			},
			report: []qualityTarget{{table: "thsr_stations", textCols: []string{"name"}, geoCols: []string{"geom"}}}},
		"tra_fare":       {load: loadTraFare},
		"thsr_fare":      {load: loadThsrFare},
		"tra_timetable":  {load: loadTraTimetable},
		"thsr_timetable": {load: loadThsrTimetable},
	}
}

// loaderRegistry derives the ordered loader specs from the datasetRegistry: one
// loadSpec per dataset that has a loadKey, in registry slice order, with its
// table/partition-column/partition-enumerator taken from the dataset and its
// transform/report from loaderTransforms. Because it walks the ordered slice,
// the datasetRegistry's bus_operator-before-bus ordering is preserved — loadBus
// reads bus_operators back after the staleness-gated bus_operator upsert. A
// dataset whose loadPartitions differs from its landed partitions (only
// bus_dailytimetable) loads the subset here.
func loaderRegistry(src loadSource) []loadSpec {
	transforms := loaderTransforms(src)
	var specs []loadSpec
	for _, d := range datasetRegistry() {
		if d.loadKey == "" {
			continue
		}
		b := transforms[d.loadKey]
		specs = append(specs, loadSpec{
			key:        d.loadKey,
			table:      d.rawTable,
			partCol:    d.partCol,
			partitions: d.loadPartitions,
			load:       b.load,
			report:     b.report,
		})
	}
	return specs
}
