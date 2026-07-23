package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5"
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

// busLandingCycleSource is the stronger, additive source contract used only by
// the correlated bus snapshot. JSON bytes, freshness, and the durable landing
// cycle are read from one RepeatableRead transaction. Other loaders retain the
// smaller loadSource contract and do not acquire cycle coupling accidentally.
type busLandingCycleSource interface {
	datasetJSONWithLandingCycle(ctx context.Context, table, partCol, partVal string) ([]byte, time.Time, string, error)
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
	staleOK    bool
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

// errLoadStale marks a partition whose durable landing-state fetched_at is
// older than the freshness window; the loader skips it rather than overwriting
// good data with a landing that never happened.
var errLoadStale = errors.New("raw_tdx_partition_stale")

// loadQuarantine collects the records one partition dropped instead of
// rejecting the whole partition over them.
//
// TDX publishes a standing tail of dangling references and divergent variants
// that never resolve on their own. Failing the partition over one of them
// wrote nothing at all, which left that city frozen at its last good snapshot
// indefinitely and silently — a load failure has no staleness alarm behind it.
// Dropping the record keeps the rest of the partition current.
//
// The line this draws: a bad *record* is dropped, a wrong *payload* still
// fails. Dangling refs, divergent variants and unusable per-record identity
// are data defects and get quarantined; a UID that belongs to another city
// means the wrong payload landed, so those checks stay fatal rather than
// silently discarding thousands of rows.
type loadQuarantine struct {
	dataset string
	part    string
	dropped map[string]int    // reason -> count
	sample  map[string]string // reason -> first offending record
	kind    map[string]string // reason -> the kind it was dropped from
	seen    map[string]int    // kind -> records examined (the ratio denominator)
}

func newLoadQuarantine(dataset, part string) *loadQuarantine {
	return &loadQuarantine{
		dataset: dataset, part: part,
		dropped: map[string]int{}, sample: map[string]string{},
		kind: map[string]string{}, seen: map[string]int{},
	}
}

// consider records how many records of a kind were examined. It is the
// denominator quarantineRatioLimit gates on, so every kind that can drop must
// declare its total.
func (q *loadQuarantine) consider(kind string, n int) {
	q.seen[kind] += n
}

// drop records one rejected record. kind names the section it came from (the
// ratio bucket, e.g. "shape"); reason is the stable log slug; detail
// identifies the offending record so an operator can find it.
func (q *loadQuarantine) drop(kind, reason, detail string) {
	q.dropped[reason]++
	q.kind[reason] = kind
	if _, ok := q.sample[reason]; !ok {
		q.sample[reason] = logSafeDetail(detail)
	}
}

// quarantineRatioLimit is the share of one kind's records that may be dropped
// before the partition fails instead. A standing tail of TDX defects is a
// handful of records; a third of a city's shapes vanishing is a defect in the
// feed or in this loader, and quarantining that silently ships a half-empty
// city without anyone noticing. The default is a starting guess — the ratio is
// logged on every run, so tune it from what the feed actually does.
func quarantineRatioLimit() float64 {
	if v := os.Getenv("LOAD_QUARANTINE_MAX_RATIO"); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil && f >= 0 && f <= 1 {
			return f
		}
		log.Warnf("[LOAD] action=quarantine event=bad_ratio_env value=%q using=%v", v, defaultQuarantineRatio)
	}
	return defaultQuarantineRatio
}

const defaultQuarantineRatio = 0.10

// exceeded reports the kinds whose drop ratio crossed the limit. The caller
// fails the partition on a non-nil error, which leaves the previous load's rows
// in place — stale but whole, which beats fresh but silently gutted.
func (q *loadQuarantine) exceeded() error {
	limit := quarantineRatioLimit()
	byKind := map[string]int{}
	for reason, n := range q.dropped {
		byKind[q.kind[reason]] += n
	}
	var over []error
	for _, kind := range sortedKeys(byKind) {
		seen := q.seen[kind]
		if seen == 0 {
			continue
		}
		ratio := float64(byKind[kind]) / float64(seen)
		if ratio > limit {
			over = append(over, fmt.Errorf("%s dropped %d/%d records (%.1f%% > %.1f%%)",
				kind, byKind[kind], seen, ratio*100, limit*100))
		}
	}
	if len(over) == 0 {
		return nil
	}
	return fmt.Errorf("%s/%s quarantine ratio exceeded: %w", q.dataset, q.part, errors.Join(over...))
}

func sortedKeys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
func logSafeDetail(s string) string {
	return strings.NewReplacer(" ", "_", "=", ":", `"`, "'").Replace(s)
}

// report logs one line per reason with its share of the kind it came from, so a
// tail that stops being a tail is visible before it becomes an outage. A clean
// partition logs nothing.
func (q *loadQuarantine) report() {
	for _, r := range sortedKeys(q.dropped) {
		kind := q.kind[r]
		seen := q.seen[kind]
		ratio := 0.0
		if seen > 0 {
			ratio = float64(q.dropped[r]) / float64(seen)
		}
		log.Warnf("[LOAD] action=quarantine event=dropped dataset=%s partition=%s reason=%s count=%d of=%d ratio=%.3f first=%s",
			q.dataset, q.part, r, q.dropped[r], seen, ratio, q.sample[r])
	}
}

// loadStats counts partition outcomes for one run. A partition is skipped (not
// failed) when it never landed at all: the rail date windows reach 45-60 days
// out, further than TDX publishes timetables, so their tail has no
// landing_state row every single day. That is the ingestor reporting an empty
// horizon, not a loader failure, and it cannot overwrite anything.
type loadStats struct {
	ok      int
	failed  int
	skipped int
}

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
func runLoad(ctx context.Context, src loadSource, db *pgxpool.Pool, rc *redis.Client, keys []string) (loadStats, error) {
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
// and do not abort the run; every failure is returned through errors.Join so
// the daily wrapper retries without hiding failures in otherwise independent
// partitions.
func runLoadSpecs(ctx context.Context, src loadSource, db *pgxpool.Pool, rc *redis.Client, specs []loadSpec) (loadStats, error) {
	sink := pgLoadSink{db: db, rc: rc}
	var stats loadStats
	var failures []error
	for _, spec := range specs {
		parts := spec.partitions()
		for _, part := range parts {
			body, fetchedAt, err := src.datasetJSON(ctx, spec.table, spec.partCol, part)
			if err != nil {
				log.Errorf("[LOAD] action=read event=error dataset=%s partition=%s error=%v", spec.key, part, err)
				failures = append(failures, fmt.Errorf("load dataset %s partition %s: read: %w", spec.key, part, err))
				stats.failed++
				continue
			}
			// Never landed and landed-but-stale are different events. No
			// landing_state row means the ingestor found nothing to land;
			// a stale one means a landing that should have happened did
			// not, which is worth failing the run over.
			if fetchedAt.IsZero() {
				log.Warnf("[LOAD] action=skip event=never_landed dataset=%s partition=%s", spec.key, part)
				stats.skipped++
				continue
			}
			if !spec.staleOK && isStale(fetchedAt) {
				log.Warnf("[LOAD] action=skip event=stale dataset=%s partition=%s fetched_at=%s reason=%v", spec.key, part, fetchedAt.Format(time.RFC3339), errLoadStale)
				failures = append(failures, fmt.Errorf("load dataset %s partition %s: %w", spec.key, part, errLoadStale))
				stats.failed++
				continue
			}
			dec := json.NewDecoder(bytes.NewReader(body))
			if err := spec.load(ctx, dec, sink, part); err != nil {
				log.Errorf("[LOAD] action=transform event=error dataset=%s partition=%s error=%v", spec.key, part, err)
				failures = append(failures, fmt.Errorf("load dataset %s partition %s: transform: %w", spec.key, part, err))
				stats.failed++
				continue
			}
			log.Infof("[LOAD] action=transform event=success dataset=%s partition=%s", spec.key, part)
			stats.ok++
		}
		reportQuality(ctx, db, spec)
	}
	log.Infof("[LOAD] action=run event=done ok=%d failed=%d skipped=%d", stats.ok, stats.failed, stats.skipped)
	return stats, errors.Join(failures...)
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
			log.Errorf("[LOAD] action=quality_report event=query_error dataset=%s table=%s error=%v", spec.key, t.table, err)
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
// columns. Freshness comes from raw_tdx.landing_state, including for a verified
// empty landing; raw row fetched_at is write-time bookkeeping and is never mass
// updated on a 304. The bus-only method also returns landing_cycle from this
// same RepeatableRead transaction.
type rawReadTxBeginner interface {
	BeginTx(context.Context, pgx.TxOptions) (pgx.Tx, error)
}

type rawTDXSource struct {
	pool rawReadTxBeginner
}

// datasetJSON returns a JSON array of every row in the partition (with the
// partition column and fetched_at stripped, since those are loader bookkeeping,
// not TDX fields) plus the landing-state fetched_at. Rows are serialized one at a time
// on the server and concatenated here: a single jsonb_agg over a partition with
// large jsonb columns (bus_routefare odfares) expands to a multi-GB in-memory
// tree and can OOM the 2 GB database server, so the per-statement working set
// must stay one row. A state-backed empty partition yields "[]" and its verified
// freshness; a partition without state yields "[]" and a zero time, forcing the
// ingestor bootstrap/refetch before any transform can consume legacy raw rows.
//
// thsr_dailytimetable.traindate is timestamptz on the landing table, but the
// original TDX payload's TrainDate is a YYYY-MM-DD string and the transform's
// train_date temp column is a date; to_jsonb would serialize the timestamptz as
// a full timestamp. The traindateColumn override re-derives the YYYY-MM-DD form
// back into the traindate JSON key so the reconstructed payload matches what the
// transform historically decoded.
func (r rawTDXSource) datasetJSON(ctx context.Context, table, partCol, partVal string) ([]byte, time.Time, error) {
	body, fetchedAt, _, err := r.readDatasetJSON(ctx, table, partCol, partVal, false)
	return body, fetchedAt, err
}

func (r rawTDXSource) datasetJSONWithLandingCycle(ctx context.Context, table, partCol, partVal string) ([]byte, time.Time, string, error) {
	return r.readDatasetJSON(ctx, table, partCol, partVal, true)
}

func (r rawTDXSource) readDatasetJSON(ctx context.Context, table, partCol, partVal string, includeCycle bool) ([]byte, time.Time, string, error) {
	if err := validateRawTarget(table, partCol); err != nil {
		return nil, time.Time{}, "", err
	}
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{
		IsoLevel:   pgx.RepeatableRead,
		AccessMode: pgx.ReadOnly,
	})
	if err != nil {
		return nil, time.Time{}, "", fmt.Errorf("read raw dataset %s partition %s: begin: %w", table, partVal, err)
	}
	defer func() {
		rbCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = tx.Rollback(rbCtx)
	}()

	var fetchedAt time.Time
	var expectedRows int64
	var landingCycle string
	stateSQL := `
		SELECT fetched_at, row_count
		FROM raw_tdx.landing_state
		WHERE table_name=$1 AND partition_column=$2 AND partition_value=$3`
	if includeCycle {
		stateSQL = `
			SELECT fetched_at, row_count, COALESCE(landing_cycle, '')
			FROM raw_tdx.landing_state
			WHERE table_name=$1 AND partition_column=$2 AND partition_value=$3`
	}
	row := tx.QueryRow(ctx, stateSQL, table, partCol, partVal)
	if includeCycle {
		err = row.Scan(&fetchedAt, &expectedRows, &landingCycle)
	} else {
		err = row.Scan(&fetchedAt, &expectedRows)
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return []byte("[]"), time.Time{}, "", nil
	}
	if err != nil {
		return nil, time.Time{}, "", fmt.Errorf("read raw dataset %s partition %s: landing state: %w", table, partVal, err)
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
		`SELECT %s::text FROM raw_tdx.%s t %s`,
		elem, table, where)
	rows, err := tx.Query(ctx, q, args...)
	if err != nil {
		return nil, time.Time{}, "", fmt.Errorf("read raw dataset %s partition %s: query rows: %w", table, partVal, err)
	}
	defer rows.Close()
	var buf bytes.Buffer
	buf.WriteByte('[')
	var actualRows int64
	for rows.Next() {
		var rowJSON []byte
		if err := rows.Scan(&rowJSON); err != nil {
			return nil, time.Time{}, "", fmt.Errorf("read raw dataset %s partition %s: scan row: %w", table, partVal, err)
		}
		if buf.Len() > 1 {
			buf.WriteByte(',')
		}
		buf.Write(rowJSON)
		actualRows++
	}
	if err := rows.Err(); err != nil {
		return nil, time.Time{}, "", fmt.Errorf("read raw dataset %s partition %s: rows: %w", table, partVal, err)
	}
	if actualRows != expectedRows {
		return nil, time.Time{}, "", &rawLandingStateMismatchError{
			Table: table, PartCol: partCol, PartVal: partVal,
			Reason: "loader_row_count", Expected: fmt.Sprint(expectedRows), Observed: fmt.Sprint(actualRows),
		}
	}
	buf.WriteByte(']')
	rows.Close()
	if err := tx.Commit(ctx); err != nil {
		return nil, time.Time{}, "", fmt.Errorf("read raw dataset %s partition %s: commit: %w", table, partVal, err)
	}
	return buf.Bytes(), fetchedAt, landingCycle, nil
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
// by the bus binding because loadBus reads eight correlated raw_tdx tables (a
// single decoder cannot feed a multi-endpoint correlation); the standalone
// copy-upsert transforms ignore it and consume the decoder runLoadSpecs hands
// them. bus_operator is one of the bus binding's eight inputs, not a transform.
func loaderTransforms(src loadSource) map[string]loaderBinding {
	return map[string]loaderBinding{
		"bus": {
			load: func(ctx context.Context, _ *json.Decoder, sink loadSink, part string) error {
				return sink.loadBusCity(ctx, src, part)
			},
			report: []qualityTarget{
				{table: "bus_subroutes", textCols: []string{"route_name", "sub_route_name", "depart", "destin"}},
				{table: "bus_static", textCols: []string{"route_name", "sub_route_name"}},
				{table: "bus_stations", textCols: []string{"station_name"}, geoCols: []string{"position"}},
			}},
		"bus_dailytimetable": {load: func(ctx context.Context, dec *json.Decoder, sink loadSink, part string) error {
			return sink.loadBusDailyTimetable(ctx, dec, src, part)
		}},
		"bike": {load: loadBikeStations,
			report: []qualityTarget{{table: "bike_stations", textCols: []string{"name", "address"}, geoCols: []string{"geom"}}}},
		"mrt_station": {load: loadMrtStations,
			report: []qualityTarget{{table: "mrt_station", textCols: []string{"name"}, geoCols: []string{"stationposition"}}}},
		"mrt_firstlast": {load: loadMrtFirstlast},
		"mrt_odfare": {load: func(ctx context.Context, dec *json.Decoder, sink loadSink, part string) error {
			return sink.loadMrtJourneyMatrix(ctx, dec, part)
		}},
		"mrt_trtc_traveltime": {load: func(ctx context.Context, _ *json.Decoder, sink loadSink, part string) error {
			return sink.loadMrtTravelTime(ctx, src, part)
		}},
		"tra_station": {load: loadTraStation,
			report: []qualityTarget{{table: "tra_stations", textCols: []string{"name"}, geoCols: []string{"geom"}}}},
		"thsr_station": {
			load: func(ctx context.Context, dec *json.Decoder, sink loadSink, part string) error {
				return sink.loadThsrStations(ctx, dec, part)
			},
			report: []qualityTarget{{table: "thsr_stations", textCols: []string{"name"}, geoCols: []string{"geom"}}}},
		"tra_fare":       {load: loadTraFare},
		"thsr_fare":      {load: loadThsrFare},
		"tra_timetable":  {load: loadTraTimetable},
		"thsr_timetable": {load: loadThsrTimetable},
		"tra_shape":      {load: loadRailShape("tra")},
		"thsr_shape":     {load: loadRailShape("thsr")},
		"metro_shape":    {load: loadRailShape("metro")},
	}
}

// loaderRegistry derives the ordered loader specs from the datasetRegistry: one
// loadSpec per dataset that has a loadKey, in registry slice order, with its
// table/partition-column/partition-enumerator taken from the dataset and its
// transform/report from loaderTransforms. bus_operator has no standalone spec:
// it is validated and written by the atomic bus city snapshot. A dataset whose
// loadPartitions differs from its landed partitions (bus static and daily
// timetable) loads the selected subset/order here.
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
			staleOK:    d.staleOK,
		})
	}
	// mrt_adjacency reads the same landed metro_s2straveltime table as
	// mrt_trtc_traveltime but produces a different target (the same-line ride
	// graph, ADR-0015). A raw_tdx table maps to one datasetRegistry entry (and
	// thus one loadKey), so this second consumer is appended as a standalone
	// loadSpec rather than a second dataset. TRTC only.
	specs = append(specs, loadSpec{
		key:        "mrt_adjacency",
		table:      "metro_s2straveltime",
		partCol:    "system",
		partitions: func() []string { return []string{"TRTC"} },
		load:       loadMrtAdjacency,
	})
	return specs
}
