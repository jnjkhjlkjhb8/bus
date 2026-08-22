// Package raw lands TDX payloads verbatim into the shared raw_tdx schema and
// records what was landed. A landing is one transaction: rows and the
// landing-state marker commit together, so a partition is never half-updated
// and a later 304 can be trusted against the marker it names (ADR-0005).
package raw

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/dataset"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/history"
	"go.uber.org/zap"
)

// DB is the process-wide pool used by the raw_tdx landing path and by
// dbSince. It is set once in main and read without locking; Dump treats a
// nil value as a hard error. Tests never reassign this var — they call the
// *WithDB entry points (DumpWithDB, VerifyAndTouchLandingWithDB,
// landRawTDXWithDB) with their own pool instead.
var DB *pgxpool.Pool

// DumpEnabled gates the raw_tdx landing to ROLE=ingestor only, so the default
// prod transform path never writes raw_tdx.
var DumpEnabled bool

// IMSCacheKey is the If-Modified-Since cache key for a fetch target. The ingestor
// writes namespaced shared:raw:* keys; the default prod path keeps its legacy key
// so prod behavior is unchanged. Both key forms live in shared/keys.go.
func IMSCacheKey(name string) string {
	if DumpEnabled {
		return shared.TDXRawIMSKey(name)
	}
	return shared.TDXLegacyIMSKey(name)
}

// dbSince derives an If-Modified-Since value from the latest updated_at of the
// prod table backing a fetch target, so a cold IMS cache still avoids re-pulling
// data already in PostgreSQL. It maps the fetch name to a table/partition query;
// unknown names, a nil pool, or any query error yield "" (fetch everything). Not
// used in ingestor mode (see SinceFallbackAllowed).
func dbSince(name string) string {
	if DB == nil {
		return ""
	}
	var q string
	var arg any
	switch {
	case strings.HasPrefix(name, "tra_traindate_"):
		q = "SELECT MAX(updated_at) FROM tra_timetable WHERE train_date=$1"
		arg = strings.TrimPrefix(name, "tra_traindate_")
	case strings.HasPrefix(name, "thsr_traindate_"):
		q = "SELECT MAX(updated_at) FROM thsr_timetable WHERE train_date=$1"
		arg = strings.TrimPrefix(name, "thsr_traindate_")
	case name == "tra_stations":
		q = "SELECT MAX(updated_at) FROM tra_stations"
	case name == "thsr_stations":
		q = "SELECT MAX(updated_at) FROM thsr_stations"
	case name == "tra_fare":
		q = "SELECT MAX(updated_at) FROM tra_fares"
	case name == "thsr_fare":
		q = "SELECT MAX(updated_at) FROM thsr_fares"
	case strings.HasPrefix(name, "mrt_stations"):
		q = "SELECT MAX(updated_at) FROM mrt_station WHERE system=$1"
		arg = strings.TrimPrefix(name, "mrt_stations")
	case strings.HasPrefix(name, "mrt_firstlast"):
		q = "SELECT MAX(updated_at) FROM mrt_schedule WHERE system=$1"
		arg = strings.TrimPrefix(name, "mrt_firstlast")
	case strings.HasPrefix(name, "bike_stations"):
		q = "SELECT MAX(updated_at) FROM bike_stations WHERE city=$1"
		arg = strings.TrimPrefix(name, "bike_stations")
	default:
	}
	ctx := context.Background()
	var t *time.Time
	var err error
	if arg != nil {
		err = DB.QueryRow(ctx, q, arg).Scan(&t)
	} else {
		err = DB.QueryRow(ctx, q).Scan(&t)
	}
	if err != nil || t == nil {
		return ""
	}
	return t.UTC().Format(http.TimeFormat)
}

// dbSinceFallbackAllowed reports whether an empty IMS cache may fall back to a
// prod table's updated_at. Never in ingestor mode: a 304 against an empty
// raw_tdx would strand the landing table permanently empty.
func SinceFallbackAllowed() bool { return !DumpEnabled }

// SinceFallback is the shared TDX client's cold-cache If-Modified-Since source:
// in the legacy prod path it derives the value from the backing table's
// updated_at (dbSince); in ingestor mode it returns "" so an empty raw_tdx is
// never masked by a table-derived 304.
func SinceFallback(name string) string {
	if SinceFallbackAllowed() {
		return dbSince(name)
	}
	return ""
}

// DumpTarget maps a TDX static endpoint path to its raw_tdx landing table and
// partition column, resolving through the datasetRegistry reverse index
// (rawTargetIndex) so it can never drift from the fetch list or whitelist.
// Real-time / unmapped endpoints (and the intentionally-absent Bus/Stop) return
// ok=false. The date-partitioned timetable endpoints carry their partition value
// (traindate) in the URL's last segment so a mid-run partition swap replaces one
// date rather than TRUNCATE'ing the table.
func DumpTarget(url string) (Target, bool) {
	var partVal string
	seg := strings.Split(strings.Trim(url, "/"), "/")
	if len(seg) < 3 || seg[0] != "v2" {
		return Target{}, false
	}
	cityOf := func() string {
		for i, s := range seg {
			if s == "City" && i+1 < len(seg) {
				return seg[i+1]
			}
			if s == "InterCity" {
				return "InterCity"
			}
		}
		return ""
	}
	var key dataset.FamSeg
	switch {
	case seg[1] == "Bus":
		key, partVal = dataset.FamSeg{Family: dataset.FamilyBusCity, Seg: seg[2]}, cityOf()
	case seg[1] == "Bike" && seg[2] == "Station":
		key, partVal = dataset.FamSeg{Family: dataset.FamilyBikeCity, Seg: "Station"}, cityOf()
	case seg[1] == "Rail" && len(seg) >= 4 && seg[2] == "Metro":
		key, partVal = dataset.FamSeg{Family: dataset.FamilyMetroSystem, Seg: seg[3]}, seg[len(seg)-1]
	// Bare /v2/Rail/<Dataset> endpoints carry no TRA/THSR/Metro segment, unlike
	// every other Rail family below: /v2/Rail/Shape (TRA line shapes) and
	// /v2/Rail/Operator (all rail operators). The segment itself keys the index,
	// so a new bare endpoint needs only its registry entry.
	case seg[1] == "Rail" && len(seg) == 3:
		key = dataset.FamSeg{Family: dataset.FamilyRailSingle, Seg: seg[2]}
	case seg[1] == "Rail" && len(seg) >= 4 && (seg[2] == "TRA" || seg[2] == "THSR"):
		pair := seg[2] + "/" + seg[3]
		if pair == "TRA/DailyTimetable" || pair == "THSR/DailyTimetable" {
			key, partVal = dataset.FamSeg{Family: dataset.FamilyRailDate, Seg: pair}, seg[len(seg)-1]
		} else {
			key = dataset.FamSeg{Family: dataset.FamilyRailSingle, Seg: pair}
		}
	default:
		return Target{}, false
	}
	d, found := dataset.RawTargetIndex[key]
	if !found {
		return Target{}, false
	}
	return Target{Table: d.RawTable, PartCol: d.PartCol, PartVal: partVal}, true
}

// Target names one raw_tdx landing partition. The three fields are all
// strings and always travel together, so they are grouped: a transposed
// argument is a compile error here rather than a silent mislanding into the
// wrong table or partition.
type Target struct {
	Table   string
	PartCol string
	PartVal string
}

// errRawDump marks a raw_tdx landing failure so callers can log it distinctly
// and, crucially, avoid caching a Last-Modified that would mask the failure.
var errRawDump = errors.New("raw dump failed")

// _stalePartitionAfter bounds how long a landing_state partition may go untouched
// before ReportStalePartitions names it.
const _stalePartitionAfter = 7 * 24 * time.Hour

// rawStateQuerier is the read-only slice of the pool ReportStalePartitions
// needs, so the sweep can be exercised without a database.
type rawStateQuerier interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
}

// ReportStalePartitions logs every landing_state partition whose fetched_at is
// older than stalePartitionAfter and returns how many it found (FDPL-38).
//
// A full ingestor run touches every partition it fetches, 304s included
// (VerifyAndTouchLanding), so a fetched_at that stops moving means nobody
// fetches that partition any more: dropped from the feed, removed from the
// fetch list, or failing every run. Every prune downstream is scoped to the
// partitions that did load, so those rows would otherwise sit in raw_tdx and in
// the env schema forever with no alarm behind them.
//
// It reports and never deletes: a partition TDX is briefly serving badly must
// not lose the data it already has. Query failures are logged rather than
// returned — this is a health signal appended to a run that already did its
// work, and it must not turn a successful landing into a failed one.
func ReportStalePartitions(ctx context.Context, db rawStateQuerier) int {
	if db == nil {
		return 0
	}
	rows, err := db.Query(ctx, `
		SELECT table_name, partition_value, fetched_at
		FROM raw_tdx.landing_state
		WHERE fetched_at < $1
		ORDER BY fetched_at, table_name, partition_value`, time.Now().Add(-_stalePartitionAfter))
	if err != nil {
		zap.S().Errorw("stale scan error",
			"component", "ingest",
			"action", "landing_state",
			"event", "stale_scan_error",
			"err", err,
		)
		return 0
	}
	defer rows.Close()
	var stale int
	for rows.Next() {
		var table, partition string
		var fetchedAt time.Time
		if err := rows.Scan(&table, &partition, &fetchedAt); err != nil {
			zap.S().Errorw("stale scan error",
				"component", "ingest",
				"action", "landing_state",
				"event", "stale_scan_error",
				"err", err,
			)
			return stale
		}
		stale++
		zap.S().Warnw("stale partition",
			"component", "ingest",
			"action", "landing_state",
			"event", "stale_partition",
			"table", table,
			"partition", partition,
			"fetched_at", fetchedAt.Format(time.RFC3339),
		)
	}
	if err := rows.Err(); err != nil {
		zap.S().Errorw("stale scan error",
			"component", "ingest",
			"action", "landing_state",
			"event", "stale_scan_error",
			"err", err,
		)
		return stale
	}
	if stale > 0 {
		zap.S().Warnw("stale summary",
			"component", "ingest",
			"action", "landing_state",
			"event", "stale_summary",
			"count", stale,
			"older_than", _stalePartitionAfter,
		)
	}
	return stale
}

// ErrLandingStateMismatch marks a 304 whose durable landing metadata does
// not agree with raw_tdx. It is intentionally distinct from database failures:
// callers may invalidate the endpoint marker and perform one full refetch only
// for this recoverable state drift, while every database error fails closed.
var ErrLandingStateMismatch = errors.New("raw landing state mismatch")

type LandingStateMismatchError struct {
	Table    string
	PartCol  string
	PartVal  string
	Reason   string
	Expected string
	Observed string
}

func (e *LandingStateMismatchError) Error() string {
	return fmt.Sprintf("%v: table=%s partition=%s:%s reason=%s expected=%s observed=%s",
		ErrLandingStateMismatch, e.Table, e.PartCol, e.PartVal, e.Reason, e.Expected, e.Observed)
}

func (e *LandingStateMismatchError) Unwrap() error { return ErrLandingStateMismatch }

type LandingBeginner interface {
	Begin(context.Context) (pgx.Tx, error)
}

// TDXTables is the whitelist of raw_tdx landing tables, derived from the
// datasetRegistry so it can never drift from the datasets themselves. Table and
// partition names are interpolated into SQL, so they must come only from this
// set. It includes the land-only bus_stop and tra_traintype (never fetched, never
// loaded) whose DDL is kept because the tables may already exist on Azure.
var TDXTables = buildWhitelist()

func buildWhitelist() map[string]bool {
	m := make(map[string]bool)
	for _, d := range dataset.Registry() {
		m[d.RawTable] = true
	}
	return m
}

// ValidateTarget guards the raw_tdx landing: it rejects any table not in the
// rawTDXTables whitelist and any partition column other than "" / "city" /
// "system" / "traindate". Table and partition names are interpolated into SQL,
// so this is the injection barrier — never relax it to accept caller-supplied
// identifiers.
func ValidateTarget(t Target) error {
	if !TDXTables[t.Table] {
		return _oops.With("table", t.Table).Wrapf(errRawDump, "table not whitelisted")
	}
	switch t.PartCol {
	case "", "city", "system", "traindate":
		return nil
	default:
		return _oops.With("part_col", t.PartCol).Wrapf(errRawDump, "partition column not allowed")
	}
}

// PartitionWhere builds the partition WHERE clause for a raw_tdx landing
// table. Callers pass values already cleared by ValidateTarget, so table and
// partCol are safe to interpolate. thsr_dailytimetable.traindate is timestamptz
// landed at Taipei midnight (tra_dailytimetable.traindate is plain text), so
// comparing it to a YYYY-MM-DD string under the services' UTC session matches
// nothing; select by Taipei calendar date instead so the right partition is
// found regardless of the session TimeZone.
func PartitionWhere(t Target) string {
	if t.Table == "thsr_dailytimetable" {
		return "WHERE (traindate AT TIME ZONE 'Asia/Taipei')::date = $1::date"
	}
	return fmt.Sprintf("WHERE %s = $1", t.PartCol)
}

// VerifyAndTouchLanding validates a 304 against the durable state committed
// with the last complete landing. It locks that state row, requires an exact
// Last-Modified match, and verifies empty/non-empty parity against the raw
// partition before bumping landing_state.fetched_at and the shared run cycle.
// It deliberately does not UPDATE every raw row: doing so daily for the largest
// fare tables would create substantial WAL and table bloat. Exact row_count
// remains recorded for audit, while the bounded 304 check detects
// missing/emptied partitions without counting millions of rows; partial-row
// loss requires a full integrity audit.
func VerifyAndTouchLanding(ctx context.Context, t Target, marker, landingCycle string) error {
	if DB == nil {
		return _oops.Wrapf(errRawDump, "ingestDB is nil")
	}
	return VerifyAndTouchLandingWithDB(ctx, DB, t, marker, landingCycle)
}

func VerifyAndTouchLandingWithDB(
	ctx context.Context,
	db LandingBeginner,
	t Target,
	marker, landingCycle string,
) error {
	table, partCol, partVal := t.Table, t.PartCol, t.PartVal
	if err := ValidateTarget(t); err != nil {
		return err
	}
	if marker == "" {
		return &LandingStateMismatchError{
			Table: table, PartCol: partCol, PartVal: partVal,
			Reason: "empty_marker", Expected: "non-empty", Observed: "empty",
		}
	}
	if strings.TrimSpace(landingCycle) == "" {
		return _oops.Wrapf(errRawDump, "landing cycle is empty")
	}
	tx, err := db.Begin(ctx)
	if err != nil {
		return _oops.Wrapf(err, "verify raw landing state: begin")
	}
	defer func() {
		rbCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = tx.Rollback(rbCtx)
	}()
	if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout = '20s'"); err != nil {
		return _oops.Wrapf(err, "verify raw landing state: set lock_timeout")
	}

	var stateMarker string
	var rowCount int64
	err = tx.QueryRow(ctx, `
		SELECT last_modified, row_count
		FROM raw_tdx.landing_state
		WHERE table_name=$1 AND partition_column=$2 AND partition_value=$3
		FOR UPDATE`, table, partCol, partVal).Scan(&stateMarker, &rowCount)
	if errors.Is(err, pgx.ErrNoRows) {
		return &LandingStateMismatchError{
			Table: table, PartCol: partCol, PartVal: partVal,
			Reason: "missing_state", Expected: marker, Observed: "missing",
		}
	}
	if err != nil {
		return _oops.Wrapf(err, "verify raw landing state: read state")
	}
	if stateMarker != marker {
		return &LandingStateMismatchError{
			Table: table, PartCol: partCol, PartVal: partVal,
			Reason: "marker", Expected: stateMarker, Observed: marker,
		}
	}

	existsSQL := fmt.Sprintf("SELECT EXISTS (SELECT 1 FROM raw_tdx.%s", table)
	args := []any{}
	if partCol != "" {
		existsSQL += " " + PartitionWhere(t)
		args = append(args, partVal)
	}
	existsSQL += " LIMIT 1)"
	var hasRows bool
	if err := tx.QueryRow(ctx, existsSQL, args...).Scan(&hasRows); err != nil {
		return _oops.Wrapf(err, "verify raw landing state: inspect partition")
	}
	expectedRows := rowCount > 0
	if hasRows != expectedRows {
		return &LandingStateMismatchError{
			Table: table, PartCol: partCol, PartVal: partVal,
			Reason: "row_presence", Expected: fmt.Sprint(expectedRows), Observed: fmt.Sprint(hasRows),
		}
	}
	ct, err := tx.Exec(ctx, `
		UPDATE raw_tdx.landing_state SET fetched_at=now(), landing_cycle=$4
		WHERE table_name=$1 AND partition_column=$2 AND partition_value=$3`, table, partCol, partVal, landingCycle)
	if err != nil {
		return _oops.Wrapf(err, "verify raw landing state: touch state")
	}
	if ct.RowsAffected() != 1 {
		return &LandingStateMismatchError{
			Table: table, PartCol: partCol, PartVal: partVal,
			Reason: "state_update", Expected: "1", Observed: fmt.Sprint(ct.RowsAffected()),
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return _oops.Wrapf(err, "verify raw landing state: commit")
	}
	return nil
}

// rawDeleteSQL builds the per-partition DELETE for a raw_tdx landing. The
// table and partition column are interpolated, so callers must pass a target
// already cleared by ValidateTarget.
func rawDeleteSQL(t Target) string {
	return fmt.Sprintf("DELETE FROM raw_tdx.%s %s", t.Table, PartitionWhere(t))
}

// rawInsertSQL lowercases each object's top-level keys (PascalCase TDX → lowercase
// columns), preserves nested objects/arrays as jsonb, injects context columns, and
// coerces types by column name. It streams the array element-by-element through a
// LATERAL jsonb_populate_record rather than materialising one giant lowercased
// jsonb_agg array and re-parsing it in a single jsonb_populate_recordset — that
// intermediate is O(payload) memory and was the long pole on the largest table
// (tra_odfare, ~every station pair): the single-statement build overran the landing
// deadline. An empty TDX array yields zero elements → a clean 0-row insert.
func rawInsertSQL(table string) string {
	return fmt.Sprintf(`INSERT INTO raw_tdx.%s
SELECT r.* FROM jsonb_array_elements($2::jsonb) elem,
  LATERAL jsonb_populate_record(NULL::raw_tdx.%s,
    (SELECT jsonb_object_agg(lower(e.k), e.v) FROM jsonb_each(elem) AS e(k,v)) || $1::jsonb) r`, table, table)
}

// Dump lands a raw TDX JSON array into raw_tdx.<table>. Partitioned tables
// replace their partition (DELETE WHERE col=val); unpartitioned tables are
// TRUNCATE'd. A dump failure is an ingestion failure and is returned as an error:
// the caller must NOT advance the Last-Modified / If-Modified-Since cache unless
// the dump succeeds, otherwise a later 304 would leave raw_tdx permanently stale.
func Dump(ctx context.Context, t Target, marker, landingCycle string, body []byte) error {
	if DB == nil {
		return _oops.Wrapf(errRawDump, "ingestDB is nil")
	}
	return DumpWithDB(ctx, DB, t, marker, landingCycle, body)
}

// DumpWithDB is Dump with the pool passed explicitly, so tests can
// exercise it against a pool they own instead of reassigning DB.
func DumpWithDB(ctx context.Context, db LandingBeginner, t Target, marker, landingCycle string, body []byte) error {
	if len(body) == 0 {
		body = []byte("[]")
	}
	return dumpRawTDXReaderWithDB(ctx, db, t, marker, landingCycle, bytes.NewReader(body))
}

// DumpReader is the streaming landing entrypoint used by the ingestor.
// body must be seekable because each transient transaction retry consumes it;
// the reader is rewound before every attempt instead of retaining a second full
// copy of the payload in memory.
func DumpReader(ctx context.Context, t Target, marker, landingCycle string, body io.ReadSeeker) error {
	if DB == nil {
		return _oops.Wrapf(errRawDump, "ingestDB is nil")
	}
	return dumpRawTDXReaderWithDB(ctx, DB, t, marker, landingCycle, body)
}

func dumpRawTDXReaderWithDB(
	ctx context.Context,
	db LandingBeginner,
	t Target,
	marker, landingCycle string,
	body io.ReadSeeker,
) error {
	if err := ValidateTarget(t); err != nil {
		return err
	}
	if body == nil {
		return _oops.Wrapf(errRawDump, "response body is nil")
	}
	if strings.TrimSpace(marker) == "" {
		return _oops.Wrapf(errRawDump, "last-modified marker is empty")
	}
	if strings.TrimSpace(landingCycle) == "" {
		return _oops.Wrapf(errRawDump, "landing cycle is empty")
	}
	// Archive before landing, because landing is destructive: it replaces the
	// partition, and TDX cannot re-serve what it replaced. Deliberately not a
	// gate — a failed archive write is logged and the landing proceeds (ADR-0023).
	ArchivePayload(ctx, history.Target(), t, marker, landingCycle, body)
	return obs.Retry(ctx, 3, 2*time.Second, func() error {
		if _, err := body.Seek(0, io.SeekStart); err != nil {
			return _oops.Wrapf(err, "rewind response")
		}
		return obs.Transient(landRawTDXWithDB(ctx, db, t, marker, landingCycle, body))
	})
}

// landRawTDXWithDB runs one raw_tdx landing transaction, bounded by its own
// timeout so a dead Azure peer cannot block the pgx socket read indefinitely
// (there is no server statement_timeout, and TCP keepalive is too slow to
// notice). On timeout pgx cancels the query; Dump retries, and if all
// attempts fail the caller leaves the IMS cache un-advanced so this partition
// refetches next run.
func landRawTDXWithDB(
	ctx context.Context,
	db LandingBeginner,
	t Target,
	marker, landingCycle string,
	body io.Reader,
) error {
	table, partCol, partVal := t.Table, t.PartCol, t.PartVal
	if err := ValidateTarget(t); err != nil {
		return err
	}
	if strings.TrimSpace(marker) == "" {
		return _oops.Wrapf(errRawDump, "last-modified marker is empty")
	}
	if strings.TrimSpace(landingCycle) == "" {
		return _oops.Wrapf(errRawDump, "landing cycle is empty")
	}
	ctx, cancel := context.WithTimeout(ctx, 3*time.Minute)
	defer cancel()

	tx, err := db.Begin(ctx)
	if err != nil {
		return _oops.Wrapf(err, "begin")
	}
	// Roll back on a context independent of ctx: if this attempt was cancelled by
	// the deadline above, a Rollback(ctx) would be a no-op and the TRUNCATE/DELETE's
	// lock would linger, blocking the next retry's TRUNCATE until its own deadline.
	defer func() {
		rbCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = tx.Rollback(rbCtx)
	}()

	// Bound lock waits so a held lock fails this attempt fast (retryable) instead of
	// stalling TRUNCATE/DELETE for the full landing deadline.
	if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout = '20s'"); err != nil {
		return _oops.Wrapf(err, "set lock_timeout")
	}

	inject := "{}"
	if partCol != "" {
		if _, err := tx.Exec(ctx, rawDeleteSQL(t), partVal); err != nil {
			return _oops.Wrapf(err, "delete partition")
		}
		b, _ := json.Marshal(map[string]string{partCol: partVal})
		inject = string(b)
	} else if _, err := tx.Exec(ctx, fmt.Sprintf("TRUNCATE raw_tdx.%s", table)); err != nil {
		return _oops.Wrapf(err, "truncate")
	}
	rows, err := insertRawChunks(ctx, func(ctx context.Context, sql string, args ...any) (int64, error) {
		ct, err := tx.Exec(ctx, sql, args...)
		if err != nil {
			return 0, err
		}
		return ct.RowsAffected(), nil
	}, table, inject, body)
	if err != nil {
		return _oops.Wrapf(err, "insert")
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO raw_tdx.landing_state
			(table_name, partition_column, partition_value, last_modified, row_count, fetched_at, landing_cycle)
		VALUES ($1, $2, $3, $4, $5, now(), $6)
		ON CONFLICT (table_name, partition_column, partition_value) DO UPDATE SET
			last_modified=EXCLUDED.last_modified,
			row_count=EXCLUDED.row_count,
			fetched_at=EXCLUDED.fetched_at,
			landing_cycle=EXCLUDED.landing_cycle`,
		table, partCol, partVal, marker, rows, landingCycle); err != nil {
		return _oops.Wrapf(err, "upsert landing state")
	}
	if err := tx.Commit(ctx); err != nil {
		return _oops.Wrapf(err, "commit")
	}
	zap.S().Infow("success", "component", "raw_tdx", "table", table, "rows", rows, "event", "success")
	return nil
}

// _rawChunkBytes bounds the JSON slice bound to one INSERT during a raw_tdx
// landing. The server parses each jsonb bind parameter in backend-private
// memory (not bounded by work_mem), so binding a whole payload in one
// statement scales server memory with payload size — which OOM-crashed the
// 2GB B1ms Azure server. 4MB keeps per-statement parse memory trivial.
const _rawChunkBytes = 4 << 20

// insertRawChunks streams the landed JSON array into raw_tdx.<table> in
// rawChunkBytes slices via exec (one INSERT per slice, all inside the caller's
// transaction), so server-side parse memory is bounded by the chunk size
// rather than the payload. An element larger than rawChunkBytes still lands as
// its own single-element chunk. An empty array issues one 0-row insert,
// matching the previous single-statement behavior; a non-array payload is an
// error, as it was under jsonb_array_elements.
func insertRawChunks(ctx context.Context, exec func(context.Context, string, ...any) (int64, error), table, inject string, body io.Reader) (int64, error) {
	dec := json.NewDecoder(body)
	// Split rather than folded into one condition: a well-formed token that is
	// simply not "[" carries no error to wrap, and Wrapf(nil) is nil — folding
	// the two would return a nil error for a non-array payload.
	tok, err := dec.Token()
	if err != nil {
		return 0, _oops.With("table", table).Wrapf(err, "read payload opening token")
	}
	if tok != json.Delim('[') {
		return 0, _oops.With("table", table).With("token", tok).Errorf("payload is not a JSON array")
	}
	sql := rawInsertSQL(table)
	chunk := append(make([]byte, 0, _rawChunkBytes+(1<<20)), '[')
	var rows int64
	flush := func() error {
		n, err := exec(ctx, sql, inject, append(chunk, ']'))
		if err != nil {
			return err
		}
		rows += n
		chunk = chunk[:1]
		return nil
	}
	flushed := false
	for dec.More() {
		var elem json.RawMessage
		if err := dec.Decode(&elem); err != nil {
			return rows, _oops.Wrapf(err, "decode array element")
		}
		if len(chunk) > 1 {
			chunk = append(chunk, ',')
		}
		chunk = append(chunk, elem...)
		if len(chunk) >= _rawChunkBytes {
			if err := flush(); err != nil {
				return rows, err
			}
			flushed = true
		}
	}
	closing, err := dec.Token()
	if err != nil {
		return rows, _oops.Wrapf(err, "decode array closing delimiter")
	}
	if closing != json.Delim(']') {
		return rows, _oops.With("closing", closing).Errorf("payload has invalid array closing token")
	}
	var trailing json.RawMessage
	switch err := dec.Decode(&trailing); {
	case errors.Is(err, io.EOF):
		// Only JSON whitespace may follow the closing array delimiter.
	case err != nil:
		return rows, _oops.Wrapf(err, "decode data after JSON array")
	default:
		return rows, errors.New("payload contains data after JSON array")
	}
	if len(chunk) > 1 || !flushed {
		if err := flush(); err != nil {
			return rows, err
		}
	}
	return rows, nil
}
