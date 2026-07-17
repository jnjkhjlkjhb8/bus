package obs

import (
	"fmt"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
)

// methodCounter tracks request and error counts for one label (a gRPC full
// method or an HTTP path). Aggregating by label rather than by caller or
// request keeps the cardinality bounded to the API's own surface area, which
// is fixed at compile time and small (tens, not thousands).
type methodCounter struct {
	requests atomic.Int64
	errors   atomic.Int64
}

// counterSet is a label -> *methodCounter registry. The zero value is ready
// to use; entries are created lazily on first observation and never removed,
// which is safe because the label set is bounded (see methodCounter).
type counterSet struct {
	entries sync.Map // map[string]*methodCounter
}

func (s *counterSet) record(label string, failed bool) {
	v, ok := s.entries.Load(label)
	if !ok {
		v, _ = s.entries.LoadOrStore(label, &methodCounter{})
	}
	c := v.(*methodCounter)
	c.requests.Add(1)
	if failed {
		c.errors.Add(1)
	}
}

// counterRow is one label's request/error totals at snapshot time.
type counterRow struct {
	label           string
	requests, fails int64
}

// snapshot returns label -> (requests, errors) sorted by label so repeated
// calls (and the resulting metrics text) are deterministic.
func (s *counterSet) snapshot() []counterRow {
	var rows []counterRow
	s.entries.Range(func(k, v any) bool {
		c := v.(*methodCounter)
		rows = append(rows, counterRow{k.(string), c.requests.Load(), c.errors.Load()})
		return true
	})
	sort.Slice(rows, func(i, j int) bool { return rows[i].label < rows[j].label })
	return rows
}

var (
	grpcCounters           counterSet
	httpCounters           counterSet
	streamDisconnectsTotal atomic.Int64
	redisErrorsTotal       atomic.Int64
	dbErrorsTotal          atomic.Int64
)

// RecordGRPCRequest tallies one completed gRPC call under fullMethod (e.g.
// "/pb.Bus_Route_Service/Static"), counting it as an error when err is
// non-nil. Call once per RPC from the interceptor layer so every method the
// server exposes is covered without touching individual handlers.
func RecordGRPCRequest(fullMethod string, err error) {
	grpcCounters.record(fullMethod, err != nil)
}

// RecordHTTPRequest tallies one completed HTTP request under path, counting
// it as an error when status is >= 500 (a server-side failure; 4xx client
// errors are not infrastructure health signals).
func RecordHTTPRequest(path string, status int) {
	httpCounters.record(path, status >= 500)
}

// IncStreamDisconnect counts one gRPC live-stream termination, regardless of
// cause (client disconnect, upstream close, send failure). It is a single
// unlabeled counter -- per-stream-channel labels would reintroduce the
// unbounded cardinality the method-keyed counters above avoid, since stream
// channels are keyed by user-supplied route/station/station-group IDs.
func IncStreamDisconnect() {
	streamDisconnectsTotal.Add(1)
}

// IncRedisError counts one failed Redis operation on the live-stream hot
// path (get, scan, subscribe). Unlabeled for the same cardinality reason as
// IncStreamDisconnect.
func IncRedisError() {
	redisErrorsTotal.Add(1)
}

// IncDBError counts one PostgreSQL query failure that is not a plain
// not-found result (see grpcStatusFor in services/router/main.go, the sole
// caller): a missing row is expected traffic, not a database health signal.
func IncDBError() {
	dbErrorsTotal.Add(1)
}

// MetricsText renders every counter registered through this file as
// Prometheus-compatible plain text (one "name{label=\"...\"} value" line per
// series), matching the hand-rolled exposition format router/http.go already
// uses for its liveHub gauges rather than pulling in a metrics client
// library.
func MetricsText() string {
	var b strings.Builder
	writeLabeled(&b, "router_grpc_requests_total", "router_grpc_errors_total", "method", grpcCounters.snapshot())
	writeLabeled(&b, "router_http_requests_total", "router_http_errors_total", "path", httpCounters.snapshot())
	fmt.Fprintf(&b, "router_stream_disconnects_total %d\n", streamDisconnectsTotal.Load())
	fmt.Fprintf(&b, "router_redis_errors_total %d\n", redisErrorsTotal.Load())
	fmt.Fprintf(&b, "router_db_errors_total %d\n", dbErrorsTotal.Load())
	return b.String()
}

func writeLabeled(b *strings.Builder, requestsName, errorsName, labelName string, rows []counterRow) {
	for _, row := range rows {
		fmt.Fprintf(b, "%s{%s=%q} %d\n", requestsName, labelName, row.label, row.requests)
		fmt.Fprintf(b, "%s{%s=%q} %d\n", errorsName, labelName, row.label, row.fails)
	}
}

// resetMetricsForTest clears every counter. Test-only (unexported); package
// obs has no exported reset because production code never needs one -- the
// process lifetime is the only scope that matters outside tests.
func resetMetricsForTest() {
	grpcCounters = counterSet{}
	httpCounters = counterSet{}
	streamDisconnectsTotal.Store(0)
	redisErrorsTotal.Store(0)
	dbErrorsTotal.Store(0)
}
