package history

import (
	"bytes"
	"compress/gzip"
	"context"
	"io"
	"sort"
	"strings"
	"sync"
	"time"

	"go.uber.org/zap"
)

// live_archive holds the realtime streams' upstream payloads verbatim
// (ADR-0023). bus_eta_history and bus_stop_event are parsed derivatives shaped
// for the ETA model; these rows are what upstream actually said, so a day whose
// parser was wrong can still be read correctly afterwards.
var _liveArchiveCols = []string{"dataset", "partition_val", "recorded_at", "payload"}

// The two retention classes are two tables, not a column: pruning is
// DROP PARTITION, which takes every dataset in the partition with it, so a
// partition cannot be dropped for the bus streams and kept for the metro ones.
const (
	_liveArchiveTable    = "live_archive"     // kept indefinitely
	_liveArchiveBusTable = "live_archive_bus" // kept 90 days
)

// liveArchiveTable routes a dataset to its retention class.
func liveArchiveTable(dataset string) string {
	if strings.HasPrefix(dataset, "live_bus") {
		return _liveArchiveBusTable
	}
	return _liveArchiveTable
}

// _liveArchiveStreams is the whitelist of observed fetches, mapping a fetch name
// to its dataset and the partition value carried in the name's tail (a city, a
// metro system, or "" where the fetch is nationwide).
//
// A whitelist rather than "archive whatever is fetched", for the same reason
// dataset.go keeps one: this list is where the retention decisions in ADR-0023
// are actually expressed, and a stream that quietly starts archiving itself
// because someone added a fetch is a storage bill nobody chose to pay.
//
// Deliberately absent:
//   - bike_availability — its sampled rows go to bike_availability_history; the
//     raw payload adds a copy of data that is already kept in a readable shape.
//   - anything gtfs_rt — self-produced, recomputable from the archived inputs.
//   - weather — CWA serves historical observations, so it is the one stream that
//     can be refetched.
var _liveArchiveStreams = []struct {
	prefix  string
	dataset string
}{
	{prefix: "bus_EstimatedTimeOfArrival", dataset: "live_bus_eta"},
	{prefix: "bus_RealTimeByFrequency", dataset: "live_bus_position"},
	{prefix: "bus_RealTimeNearStop", dataset: "live_bus_nearstop"},
	{prefix: "mrt_LiveBoard", dataset: "live_mrt_liveboard"},
	{prefix: "tra_delay", dataset: "live_tra"},
	{prefix: "thsr_availableseats", dataset: "live_thsr"},
}

// Datasets written by the streams that do not go through the TDX client: the
// Data.taipei bus blob, the Metro Taipei SOAP endpoints, and the alert feed.
const (
	DatasetBusFast = "live_bus_fast"
	DatasetMRT     = "live_mrt"
	DatasetMQTT    = "live_mqtt"
)

// _liveDataTaipeiBlobs are the Data.taipei blobs that carry realtime data.
// GetSpecTimeTable is deliberately absent: it lands in raw_tdx and is archived
// against its upstream version there, so archiving it here too would keep the
// same bytes twice under two different retention rules.
var _liveDataTaipeiBlobs = map[string]bool{
	"GetBusData":      true,
	"GetBusEvent":     true,
	"BusSeatEvent":    true,
	"GetEstimateTime": true,
}

func IsLiveDataTaipeiBlob(name string) bool { return _liveDataTaipeiBlobs[name] }

// liveArchiveStream resolves a fetch name to its dataset and partition, and
// reports whether the stream is archived at all.
func liveArchiveStream(name string) (dataset, partition string, ok bool) {
	for _, s := range _liveArchiveStreams {
		if rest, found := strings.CutPrefix(name, s.prefix); found {
			return s.dataset, rest, true
		}
	}
	return "", "", false
}

// ArchiveMQTTMessage keeps one alert message, partitioned by its topic. Push
// streams get one row per message rather than a per-minute batch: what makes
// these worth keeping is the second at which each alert arrived, which is what
// answers "why did nobody get notified then", and batching erases exactly that.
func ArchiveMQTTMessage(topic string, payload []byte) {
	ArchiveLivePayload(DatasetMQTT, topic, time.Now(), payload)
}

// LiveArchiveTap is the shared.TDXTap the live TDX client is built with. It
// returns nil — meaning "not observed" — for a stream off the whitelist and for
// every environment without an archive host, which is all of them but prod.
func LiveArchiveTap(name string) io.WriteCloser {
	dataset, partition, ok := liveArchiveStream(name)
	if !ok || Target() == nil {
		return nil
	}
	return newLiveArchiveSink(dataset, partition, time.Now())
}

// liveArchiveSink compresses one response body as it streams past and hands the
// result to the background flusher on Close.
//
// Compressing inline rather than buffering the payload and compressing later is
// what keeps this off the live tick's memory: the tick holds the compressed
// bytes, which are a fraction of the JSON, and never a second copy of the whole
// response.
type liveArchiveSink struct {
	dataset    string
	partition  string
	recordedAt time.Time
	buf        bytes.Buffer
	gz         *gzip.Writer
}

func newLiveArchiveSink(dataset, partition string, recordedAt time.Time) *liveArchiveSink {
	s := &liveArchiveSink{dataset: dataset, partition: partition, recordedAt: recordedAt}
	s.gz = gzip.NewWriter(&s.buf)
	_liveArchiveGaps.due(dataset)
	return s
}

func (s *liveArchiveSink) Write(p []byte) (int, error) {
	return s.gz.Write(p)
}

// Close finishes the gzip stream and queues the row. The write itself happens on
// the flusher, off the live tick's clock: these bytes describe a snapshot that
// has already been published to Redis, and nothing downstream waits on them.
func (s *liveArchiveSink) Close() error {
	if err := s.gz.Close(); err != nil {
		zap.S().Errorw("compress error",
			"component", "live_archive", "dataset", s.dataset, "partition", s.partition, "err", err)
		return err
	}
	submitLiveArchiveRow(s.dataset, s.partition, s.recordedAt, s.buf.Bytes())
	return nil
}

// submitLiveArchiveRow queues one archive row. A full queue drops it — the live
// path is never made to wait on the archive host (ADR-0023) — and the drop is
// counted, not merely logged: the gap between what was fetched and what was
// stored is the only thing that stops a partial archive from being read months
// later as a complete one.
func submitLiveArchiveRow(dataset, partition string, recordedAt time.Time, payload []byte) {
	target := Target()
	if target == nil || len(payload) == 0 {
		return
	}
	row := []any{dataset, partition, recordedAt, payload}
	table := liveArchiveTable(dataset)
	Submit(table, 1, func(ctx context.Context) {
		if err := Insert(ctx, target, table, _liveArchiveCols, [][]any{row}); err != nil {
			zap.S().Errorw("insert error",
				"component", "live_archive", "dataset", dataset, "partition", partition, "err", err)
			return
		}
		_liveArchiveGaps.stored(dataset)
	})
}

// ArchiveLivePayload is the entrypoint for the streams that do not go through
// the TDX client — Data.taipei's bus blob, the Metro Taipei SOAP responses, and
// each MQTT alert. They already hold the bytes, so they compress and queue in
// one call instead of teeing a stream.
func ArchiveLivePayload(dataset, partition string, recordedAt time.Time, payload []byte) {
	if Target() == nil || len(payload) == 0 {
		return
	}
	_liveArchiveGaps.due(dataset)
	var buf bytes.Buffer
	zw := gzip.NewWriter(&buf)
	if _, err := zw.Write(payload); err != nil {
		zap.S().Errorw("compress error",
			"component", "live_archive", "dataset", dataset, "partition", partition, "err", err)
		return
	}
	if err := zw.Close(); err != nil {
		zap.S().Errorw("compress error",
			"component", "live_archive", "dataset", dataset, "partition", partition, "err", err)
		return
	}
	submitLiveArchiveRow(dataset, partition, recordedAt, buf.Bytes())
}

// liveArchiveGaps counts, per dataset, payloads seen against payloads actually
// stored. Dropping under backpressure is the accepted behaviour; dropping
// invisibly is not, and a log line per drop is not visibility — nobody reads it,
// and it cannot answer "is the window I am about to analyse complete".
type liveArchiveGaps struct {
	mu     sync.Mutex
	counts map[string]*liveArchiveCount
}

type liveArchiveCount struct {
	seen   int
	stored int
}

var _liveArchiveGaps = &liveArchiveGaps{}

func (g *liveArchiveGaps) due(dataset string) {
	g.bump(dataset, func(c *liveArchiveCount) { c.seen++ })
}

func (g *liveArchiveGaps) stored(dataset string) {
	g.bump(dataset, func(c *liveArchiveCount) { c.stored++ })
}

func (g *liveArchiveGaps) bump(dataset string, fn func(*liveArchiveCount)) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.counts == nil {
		g.counts = make(map[string]*liveArchiveCount)
	}
	c, ok := g.counts[dataset]
	if !ok {
		c = &liveArchiveCount{}
		g.counts[dataset] = c
	}
	fn(c)
}

// drain returns the counts accumulated since the last drain and clears them, so
// each report covers one interval rather than all of
func (g *liveArchiveGaps) drain() map[string]liveArchiveCount {
	g.mu.Lock()
	defer g.mu.Unlock()
	out := make(map[string]liveArchiveCount, len(g.counts))
	for dataset, c := range g.counts {
		out[dataset] = *c
	}
	g.counts = nil
	return out
}

// ReportGaps logs one line per dataset covering the interval since the
// last report. A dataset with seen == stored is reported too: "the archive was
// complete yesterday" is the statement worth having on the record, and only a
// line that appears either way can make it.
func ReportGaps() {
	counts := _liveArchiveGaps.drain()
	datasets := make([]string, 0, len(counts))
	for dataset := range counts {
		datasets = append(datasets, dataset)
	}
	sort.Strings(datasets)
	for _, dataset := range datasets {
		c := counts[dataset]
		zap.S().Infow("archive coverage",
			"component", "live_archive",
			"action", "coverage",
			"dataset", dataset,
			"seen", c.seen,
			"stored", c.stored,
			"missing", c.seen-c.stored,
		)
	}
}
