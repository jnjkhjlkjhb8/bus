package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/go-redis/redis"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/functions/notify"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/protobuf/proto"
)

// fakeLiveSource is the liveSource seam's in-memory adapter: it serves committed
// fixture bytes for names it was seeded with, and reports a 304 Not-Modified
// (modified=false, err=nil) for every other name. That lets a test drive a job
// that loops over many partitions (cities/systems) while asserting on only the
// seeded one, and exercise the 304→TTL path for the rest.
type fakeLiveSource struct {
	fixtures    map[string][]byte // key: fetch name → raw TDX JSON array
	calls       []string
	acked       []string
	closed      []string
	invalidated []string
	ackErr      error
	ackErrors   map[string]error
	closeErr    error
}

func (s *fakeLiveSource) fetch(_ context.Context, _, name string) (*shared.TDXFetch, error) {
	s.calls = append(s.calls, name)
	body, ok := s.fixtures[name]
	if !ok {
		return &shared.TDXFetch{
			Modified: false,
			Invalidate: func() error {
				s.invalidated = append(s.invalidated, name)
				return nil
			},
		}, nil
	}
	return &shared.TDXFetch{
		Decoder:  json.NewDecoder(bytes.NewReader(body)),
		Modified: true,
		Ack: func() error {
			s.acked = append(s.acked, name)
			if err := s.ackErrors[name]; err != nil {
				return err
			}
			return s.ackErr
		},
		Close: func() error {
			s.closed = append(s.closed, name)
			return s.closeErr
		},
		Invalidate: func() error {
			s.invalidated = append(s.invalidated, name)
			return nil
		},
	}, nil
}

// setWrite records one pipelined SET.
type setWrite struct {
	key   string
	value []byte
	ttl   time.Duration
}

// publishWrite records one pipelined PUBLISH.
type publishWrite struct {
	channel string
	value   []byte
}

// hsetWrite records one pipelined HSET.
type hsetWrite struct {
	key   string
	field string
	value string
}

// expireWrite records one pipelined EXPIRE.
type expireWrite struct {
	key string
	ttl time.Duration
}

// captureLiveSink is the liveSink seam's recording adapter. It captures every
// pipelined write and every refreshTTL call so a test can assert on exact keys,
// channels, TTLs, and decoded protobuf payloads without a real Redis.
type captureLiveSink struct {
	sets     []setWrite
	publishs []publishWrite
	hsets    []hsetWrite
	expires  []expireWrite
	refresh  [][]ttlPattern
	// strings and hashes seed the read seam so a test can drive the bus weather
	// read and the tra delay-hash merge without a live Redis.
	strings map[string]string
	hashes  map[string]map[string]string
	execErr error
}

func (s *captureLiveSink) pipeline() livePipe { return &capturePipe{sink: s} }

func (s *captureLiveSink) refreshTTL(patterns []ttlPattern) {
	s.refresh = append(s.refresh, patterns)
}

func (s *captureLiveSink) getString(key string) (string, error) {
	if v, ok := s.strings[key]; ok {
		return v, nil
	}
	return "", redis.Nil
}

func (s *captureLiveSink) getHash(key string) (map[string]string, error) {
	if v, ok := s.hashes[key]; ok {
		return v, nil
	}
	return map[string]string{}, nil
}

// setFor returns the captured SET for key, or nil.
func (s *captureLiveSink) setFor(key string) *setWrite {
	for i := range s.sets {
		if s.sets[i].key == key {
			return &s.sets[i]
		}
	}
	return nil
}

func (s *captureLiveSink) expireFor(key string) *expireWrite {
	for i := range s.expires {
		if s.expires[i].key == key {
			return &s.expires[i]
		}
	}
	return nil
}

// capturePipe records writes into its sink; Exec is a no-op that never errors.
type capturePipe struct {
	sink *captureLiveSink
}

func (p *capturePipe) Set(key string, value any, ttl time.Duration) {
	p.sink.sets = append(p.sink.sets, setWrite{key: key, value: toBytes(value), ttl: ttl})
}

func (p *capturePipe) Publish(channel string, value any) {
	p.sink.publishs = append(p.sink.publishs, publishWrite{channel: channel, value: toBytes(value)})
}

func (p *capturePipe) HSet(key, field string, value any) {
	p.sink.hsets = append(p.sink.hsets, hsetWrite{key: key, field: field, value: toString(value)})
}

func (p *capturePipe) Expire(key string, ttl time.Duration) {
	p.sink.expires = append(p.sink.expires, expireWrite{key: key, ttl: ttl})
}

func (p *capturePipe) Exec() error { return p.sink.execErr }

// toBytes normalizes the []byte / string values the jobs marshal into SET/PUBLISH.
func toBytes(v any) []byte {
	switch t := v.(type) {
	case []byte:
		return t
	case string:
		return []byte(t)
	default:
		return nil
	}
}

// toString normalizes the HSET value (jobs pass a uint16 delay).
func toString(v any) string {
	if s, ok := v.(string); ok {
		return s
	}
	// The value is a numeric delay; format it the way Redis would store it.
	b, _ := json.Marshal(v)
	return string(b)
}

// readFixture loads a committed TDX fixture from testdata/.
func readFixture(t *testing.T, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	return b
}

// specByKey returns the registered liveSpec with the given key.
func specByKey(t *testing.T, key string) liveSpec {
	t.Helper()
	for _, s := range liveRegistry(nil, nil) {
		if s.key == key {
			return s
		}
	}
	t.Fatalf("no live spec with key %q", key)
	return liveSpec{}
}

func TestMrtSpecRunWritesArrivals(t *testing.T) {
	// The mrt spec, run against a fixture source and capture sink, must write one
	// per-(station,line) key and publish per-station updates, with decoded
	// protobuf matching the fixture. Only TRTC is seeded; the other systems 304.
	src := &fakeLiveSource{fixtures: map[string][]byte{
		"mrt_LiveBoardTRTC": readFixture(t, "tdx_mrt_liveboard_trtc.json"),
	}}
	sink := &captureLiveSink{}
	runLiveSpec(context.Background(), src, sink, specByKey(t, "mrt"))

	key := shared.MrtLiveKey("TRTC", "BL12", "BL")
	sw := sink.setFor(key)
	if sw == nil {
		t.Fatalf("expected SET for %s; got keys %v", key, setKeys(sink))
	}
	if sw.ttl != mrtLiveTTL {
		t.Fatalf("mrt SET ttl = %v, want %v", sw.ttl, mrtLiveTTL)
	}
	var got models.MrtLive
	if err := proto.Unmarshal(sw.value, &got); err != nil {
		t.Fatalf("unmarshal MrtLive: %v", err)
	}
	if got.System != "TRTC" || got.StationID != "BL12" || got.LineID != "BL" {
		t.Fatalf("MrtLive identity = %+v", &got)
	}
	if got.EstimateTime != 120 || got.DestinationStationName != "南港展覽館" {
		t.Fatalf("MrtLive payload = %+v", &got)
	}
	// Both fixture rows share station BL12, so both publish the station channel.
	ch := shared.MrtLiveChannel("TRTC", "BL12")
	pubCount := 0
	for _, p := range sink.publishs {
		if p.channel == ch {
			pubCount++
		}
	}
	if pubCount != 2 {
		t.Fatalf("publishes to %s = %d, want 2", ch, pubCount)
	}
}

func TestTraSpecCachesDelays(t *testing.T) {
	// The tra spec caches the delay hash + all-snapshot from the delay feed.
	// Per-station live boards are no longer built here (the liveboard write path
	// was removed with the TRA read-path migration), so no tra:liveboard key may
	// be written.
	src := &fakeLiveSource{fixtures: map[string][]byte{
		"tra_delay": readFixture(t, "tdx_tra_delay.json"),
	}}
	sink := &captureLiveSink{
		hashes: map[string]map[string]string{
			shared.TraDelayHashKey: {"1234": "9"},
		},
	}
	runLiveSpec(context.Background(), src, sink, specByKey(t, "tra"))

	// Delay hash: train 1234 delayed 5 minutes (from the delay feed, via the sink).
	var hset *hsetWrite
	for i := range sink.hsets {
		if sink.hsets[i].key == shared.TraDelayHashKey && sink.hsets[i].field == "1234" {
			hset = &sink.hsets[i]
		}
	}
	if hset == nil || hset.value != "5" {
		t.Fatalf("expected HSET %s 1234 = 5; got %+v", shared.TraDelayHashKey, sink.hsets)
	}
	// All-delay snapshot cached with the 3m TTL and published for streaming.
	if sw := sink.setFor(shared.TraDelayAllKey); sw == nil || sw.ttl != traLiveTTL {
		t.Fatalf("expected SET %s ttl=%v; got %+v", shared.TraDelayAllKey, traLiveTTL, sw)
	}
	var pub *publishWrite
	for i := range sink.publishs {
		if sink.publishs[i].channel == shared.TraDelayAllKey {
			pub = &sink.publishs[i]
		}
	}
	if pub == nil {
		t.Fatalf("expected PUBLISH to %s; got %+v", shared.TraDelayAllKey, sink.publishs)
	}
	// No liveboard writes remain.
	for _, k := range setKeys(sink) {
		if strings.HasPrefix(k, "tra:liveboard") {
			t.Fatalf("unexpected liveboard write %s", k)
		}
	}
}
func TestBikeSpecWritesAvailability(t *testing.T) {
	// The bike spec must write one BikeEta per station under its availability key
	// with the 2-minute TTL and the decoded rentable/returnable counts. db is nil
	// so history sampling is skipped (the realtime path runs without a database).
	src := &fakeLiveSource{fixtures: map[string][]byte{
		"bike_availabilityTaipei": readFixture(t, "tdx_bike_availability.json"),
	}}
	sink := &captureLiveSink{}
	runLiveSpec(context.Background(), src, sink, specByKey(t, "bike"))

	key := shared.BikeAvailabilityKey("TPE500101001")
	sw := sink.setFor(key)
	if sw == nil {
		t.Fatalf("expected SET for %s; got %v", key, setKeys(sink))
	}
	if sw.ttl != bikeLiveTTL {
		t.Fatalf("bike SET ttl = %v, want %v", sw.ttl, bikeLiveTTL)
	}
	var got models.BikeEta
	if err := proto.Unmarshal(sw.value, &got); err != nil {
		t.Fatalf("unmarshal BikeEta: %v", err)
	}
	if got.StationUID != "TPE500101001" || got.GeneralBikes != 5 || got.ElectricBikes != 3 {
		t.Fatalf("BikeEta = %+v", &got)
	}
	if got.AvailableReturnBikes != 12 {
		t.Fatalf("AvailableReturnBikes = %d, want 12", got.AvailableReturnBikes)
	}
}

func TestThsrSeatsSpecWritesSeats(t *testing.T) {
	// The thsr_seats spec, run against a fixture source and capture sink, must
	// aggregate the OD segments per train into one ThsrAvailableSeats, SET it under
	// the per-train key with the 15-minute TTL, and PUBLISH each train to the
	// per-date channel so connected router streams get the update. The job fetches
	// under the fixed "thsr_availableseats" name for today's Taipei date, so the
	// keys/channel are computed the same way here.
	src := &fakeLiveSource{fixtures: map[string][]byte{
		"thsr_availableseats": readFixture(t, "tdx_thsr_availableseats.json"),
	}}
	sink := &captureLiveSink{}
	runLiveSpec(context.Background(), src, sink, specByKey(t, "thsr_seats"))

	date := time.Now().In(taipei).Format(time.DateOnly)

	// Train 0801 carries both fixture segments, aggregated into one snapshot.
	sw := sink.setFor(shared.ThsrSeatsKey(date, "0801"))
	if sw == nil {
		t.Fatalf("expected SET for train 0801; got keys %v", setKeys(sink))
	}
	if sw.ttl != thsrSeatsLiveTTL {
		t.Fatalf("thsr seats SET ttl = %v, want %v", sw.ttl, thsrSeatsLiveTTL)
	}
	var got models.ThsrAvailableSeats
	if err := proto.Unmarshal(sw.value, &got); err != nil {
		t.Fatalf("unmarshal ThsrAvailableSeats: %v", err)
	}
	if len(got.Segments) != 2 {
		t.Fatalf("train 0801 segments = %d, want 2", len(got.Segments))
	}
	if got.Segments[0].OriginStationId != "0990" || got.Segments[0].StandardSeatStatus != "O" {
		t.Fatalf("segment[0] = %+v", got.Segments[0])
	}
	if got.Segments[1].DestinationStationId != "1070" || got.Segments[1].StandardSeatStatus != "L" {
		t.Fatalf("segment[1] = %+v", got.Segments[1])
	}

	// Train 0803 has a single segment and is also written.
	if sw := sink.setFor(shared.ThsrSeatsKey(date, "0803")); sw == nil {
		t.Fatalf("expected SET for train 0803; got keys %v", setKeys(sink))
	}

	// Both trains publish to the per-date channel.
	channel := shared.ThsrSeatsPattern(date)
	pubCount := 0
	for _, p := range sink.publishs {
		if p.channel == channel {
			pubCount++
		}
	}
	if pubCount != 2 {
		t.Fatalf("publishes to %s = %d, want 2", channel, pubCount)
	}
}

func TestThsrSeatsSpec304RefreshesTTL(t *testing.T) {
	// With no fixture the seat fetch 304s, so the spec must re-arm today's seat-key
	// TTL once via boundFetch and write nothing.
	src := &fakeLiveSource{fixtures: map[string][]byte{}}
	sink := &captureLiveSink{}
	runLiveSpec(context.Background(), src, sink, specByKey(t, "thsr_seats"))

	if len(sink.sets) != 0 {
		t.Fatalf("expected no SETs on a 304; got %v", setKeys(sink))
	}
	if len(sink.refresh) != 1 {
		t.Fatalf("refreshTTL calls = %d, want 1", len(sink.refresh))
	}
	date := time.Now().In(taipei).Format(time.DateOnly)
	got := sink.refresh[0]
	if len(got) != 1 || got[0].pattern != shared.ThsrSeatsPattern(date) || got[0].ttl != thsrSeatsLiveTTL {
		t.Fatalf("refresh patterns = %+v", got)
	}
}

func TestBoundFetch304RefreshesTTL(t *testing.T) {
	// When TDX answers 304, boundFetch must re-arm the spec's ttlPatterns through
	// the sink before returning modified=false — the generalized 304→TTL rule for
	// jobs that previously just skipped (mrt/tra/bike).
	src := &fakeLiveSource{fixtures: map[string][]byte{}} // every name 304s
	sink := &captureLiveSink{}
	spec := liveSpec{
		key: "probe",
		ttlPatterns: func() []ttlPattern {
			return []ttlPattern{{pattern: "mrt_live:*", ttl: mrtLiveTTL}}
		},
	}
	fetch := bindFetch(src, sink, spec)
	result, err := fetch(context.Background(), "/x", "unseeded")
	if err != nil {
		t.Fatalf("fetch error: %v", err)
	}
	if result.Modified {
		t.Fatal("expected modified=false for a 304")
	}
	if len(sink.refresh) != 1 {
		t.Fatalf("refreshTTL calls = %d, want 1", len(sink.refresh))
	}
	got := sink.refresh[0]
	if len(got) != 1 || got[0].pattern != "mrt_live:*" || got[0].ttl != mrtLiveTTL {
		t.Fatalf("refresh patterns = %+v", got)
	}
}

func TestFailedDecodeOrPublishLeavesMarkerUnchanged(t *testing.T) {
	t.Run("decode", func(t *testing.T) {
		src := &fakeLiveSource{fixtures: map[string][]byte{
			"thsr_availableseats": []byte(`[{"TrainDate":`),
		}}
		sink := &captureLiveSink{}
		spec := specByKey(t, "thsr_seats")

		err := spec.run(context.Background(), bindFetch(src, sink, spec), sink)
		if err == nil {
			t.Fatal("malformed TDX payload returned nil error")
		}
		if len(src.acked) != 0 {
			t.Fatalf("malformed payload acked marker: %v", src.acked)
		}
		if len(src.closed) != 1 {
			t.Fatalf("malformed payload closes = %d, want 1", len(src.closed))
		}
	})

	t.Run("publish", func(t *testing.T) {
		publishErr := errors.New("redis publish failed")
		src := &fakeLiveSource{fixtures: map[string][]byte{
			"thsr_availableseats": readFixture(t, "tdx_thsr_availableseats.json"),
		}}
		sink := &captureLiveSink{execErr: publishErr}
		spec := specByKey(t, "thsr_seats")

		err := spec.run(context.Background(), bindFetch(src, sink, spec), sink)
		if !errors.Is(err, publishErr) {
			t.Fatalf("publish error = %v, want %v", err, publishErr)
		}
		if len(src.acked) != 0 {
			t.Fatalf("failed publish acked marker: %v", src.acked)
		}
		if len(src.closed) != 1 {
			t.Fatalf("failed publish closes = %d, want 1", len(src.closed))
		}
	})
}

func TestLiveConsumerReturnsAckAndCloseErrors(t *testing.T) {
	tests := []struct {
		name     string
		ackErr   error
		closeErr error
		wantAcks int
	}{
		{name: "ack", ackErr: errors.New("marker write failed"), wantAcks: 1},
		{name: "close", closeErr: errors.New("response close failed"), wantAcks: 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			src := &fakeLiveSource{
				fixtures: map[string][]byte{
					"thsr_availableseats": readFixture(t, "tdx_thsr_availableseats.json"),
				},
				ackErr:   tt.ackErr,
				closeErr: tt.closeErr,
			}
			sink := &captureLiveSink{}
			spec := specByKey(t, "thsr_seats")

			err := spec.run(context.Background(), bindFetch(src, sink, spec), sink)
			want := tt.ackErr
			if want == nil {
				want = tt.closeErr
			}
			if !errors.Is(err, want) {
				t.Fatalf("consumer error = %v, want %v", err, want)
			}
			if len(src.acked) != tt.wantAcks || len(src.closed) != 1 {
				t.Fatalf("acked/closed = %v/%v, want %d/1", src.acked, src.closed, tt.wantAcks)
			}
		})
	}
}

func TestLiveDecodersRejectWrongDelimitersAndTrailingData(t *testing.T) {
	for _, body := range []string{`{}`, `[] {}`, `[{"StationUID":"S1"}] trailing`} {
		t.Run(body, func(t *testing.T) {
			err := decodeLiveItems(json.NewDecoder(strings.NewReader(body)), func(bikeAvailability) error { return nil })
			if err == nil {
				t.Fatalf("decodeLiveItems(%q) returned nil", body)
			}

			_, complete := decodeBusEtaArray(json.NewDecoder(strings.NewReader(body)))
			if complete {
				t.Fatalf("decodeBusEtaArray(%q) reported complete", body)
			}
		})
	}
}

func TestCommitTDXFetchClosesBeforeAck(t *testing.T) {
	closeErr := errors.New("close failed")
	acked := false
	fetch := &shared.TDXFetch{
		Decoder:  json.NewDecoder(strings.NewReader(`[]`)),
		Modified: true,
		Ack: func() error {
			acked = true
			return nil
		},
		Close: func() error { return closeErr },
	}
	err := commitTDXFetch(fetch, func(dec *json.Decoder) error {
		return decodeLiveItems(dec, func(struct{}) error { return nil })
	})
	if !errors.Is(err, closeErr) {
		t.Fatalf("commit error = %v, want %v", err, closeErr)
	}
	if acked {
		t.Fatal("fetch was acknowledged despite close failure")
	}
}

func TestCommitTDXFetchRequiresCloseBeforeAck(t *testing.T) {
	acked := false
	fetch := &shared.TDXFetch{
		Decoder:  json.NewDecoder(strings.NewReader(`[]`)),
		Modified: true,
		Ack: func() error {
			acked = true
			return nil
		},
	}
	err := commitTDXFetch(fetch, func(dec *json.Decoder) error {
		return decodeLiveItems(dec, func(struct{}) error { return nil })
	})
	if err == nil {
		t.Fatal("commit without Close returned nil error")
	}
	if acked {
		t.Fatal("fetch without Close was acknowledged")
	}
}

func TestCorruptGzipChecksumDoesNotAck(t *testing.T) {
	var compressed bytes.Buffer
	zw := gzip.NewWriter(&compressed)
	_, _ = zw.Write([]byte(`[]`))
	_ = zw.Close()
	data := compressed.Bytes()
	data = data[:len(data)-4]
	zr, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		t.Fatalf("gzip.NewReader: %v", err)
	}
	acked := false
	fetch := &shared.TDXFetch{
		Decoder:  json.NewDecoder(zr),
		Modified: true,
		Ack: func() error {
			acked = true
			return nil
		},
		Close: zr.Close,
	}
	err = commitTDXFetch(fetch, func(dec *json.Decoder) error {
		return decodeLiveItems(dec, func(struct{}) error { return nil })
	})
	if err == nil {
		t.Fatal("corrupt gzip checksum returned nil error")
	}
	if acked {
		t.Fatal("corrupt gzip response was acknowledged")
	}
}

func TestBusPublishFailureDoesNotAckEitherFeed(t *testing.T) {
	prefix := citymap["Taipei"]
	busStaticMapCache.Delete(prefix)
	t.Cleanup(func() { busStaticMapCache.Delete(prefix) })

	src := &fakeLiveSource{fixtures: map[string][]byte{
		"bus_EstimatedTimeOfArrivalTaipei": []byte(`[]`),
		"bus_RealTimeByFrequencyTaipei":    []byte(`[]`),
	}}
	publishErr := errors.New("redis pipeline failed")
	sink := &captureLiveSink{execErr: publishErr}
	store := &fakeBusEtaStore{stops: []busStationmap{{
		StationUID: "STATION1", StationName: "站牌一", SubRouteUID: "TPE1",
		SubRouteName: "一路", StopUID: "STOP1", StopSequence: 1,
	}}}
	job := busLiveJob{
		fetch: bindFetch(src, sink, specByKey(t, "bus")), sink: sink, store: store,
		notifier: &captureBusArrivalNotifier{}, now: time.Now,
	}

	err := job.runCity(context.Background(), "Taipei")
	if !errors.Is(err, publishErr) {
		t.Fatalf("runCity error = %v, want %v", err, publishErr)
	}
	if len(src.acked) != 0 {
		t.Fatalf("failed combined publish acked feeds: %v", src.acked)
	}
	if len(src.closed) != 2 {
		t.Fatalf("closed feeds = %v, want both feeds", src.closed)
	}
}

func TestBusAcknowledgesBothFeedsAfterPublish(t *testing.T) {
	prefix := citymap["Taipei"]
	busStaticMapCache.Delete(prefix)
	t.Cleanup(func() { busStaticMapCache.Delete(prefix) })

	src := &fakeLiveSource{fixtures: map[string][]byte{
		"bus_EstimatedTimeOfArrivalTaipei": []byte(`[]`),
		"bus_RealTimeByFrequencyTaipei":    []byte(`[]`),
	}}
	sink := &captureLiveSink{}
	store := &fakeBusEtaStore{stops: []busStationmap{{
		StationUID: "STATION1", StationName: "站牌一", SubRouteUID: "TPE1",
		SubRouteName: "一路", StopUID: "STOP1", StopSequence: 1,
	}}}
	job := busLiveJob{
		fetch: bindFetch(src, sink, specByKey(t, "bus")), sink: sink, store: store,
		notifier: &captureBusArrivalNotifier{}, now: time.Now,
	}

	if err := job.runCity(context.Background(), "Taipei"); err != nil {
		t.Fatalf("runCity: %v", err)
	}
	want := []string{
		"bus_EstimatedTimeOfArrivalTaipei",
		"bus_RealTimeByFrequencyTaipei",
	}
	if len(src.acked) != len(want) {
		t.Fatalf("acked feeds = %v, want %v", src.acked, want)
	}
	for i := range want {
		if src.acked[i] != want[i] {
			t.Fatalf("acked feed[%d] = %q, want %q", i, src.acked[i], want[i])
		}
	}
	if len(src.closed) != 2 {
		t.Fatalf("closed feeds = %v, want both feeds", src.closed)
	}
}

func TestBusOneModifiedFeedUsesCachedCounterpartAndAdvances(t *testing.T) {
	tests := []struct {
		name       string
		fixtures   map[string][]byte
		cachedKey  string
		modified   string
		writtenKey string
	}{
		{
			name: "ETA 200 positions 304",
			fixtures: map[string][]byte{
				"bus_EstimatedTimeOfArrivalTaipei": []byte(`[]`),
			},
			cachedKey:  shared.BusPositionRawKey("Taipei"),
			modified:   "bus_EstimatedTimeOfArrivalTaipei",
			writtenKey: shared.BusETARawKey("Taipei"),
		},
		{
			name: "ETA 304 positions 200",
			fixtures: map[string][]byte{
				"bus_RealTimeByFrequencyTaipei": []byte(`[]`),
			},
			cachedKey:  shared.BusETARawKey("Taipei"),
			modified:   "bus_RealTimeByFrequencyTaipei",
			writtenKey: shared.BusPositionRawKey("Taipei"),
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			prefix := citymap["Taipei"]
			busStaticMapCache.Delete(prefix)
			t.Cleanup(func() { busStaticMapCache.Delete(prefix) })

			src := &fakeLiveSource{fixtures: tt.fixtures}
			sink := &captureLiveSink{strings: map[string]string{tt.cachedKey: `[]`}}
			store := &fakeBusEtaStore{stops: []busStationmap{{
				StationUID: "STATION1", StationName: "站牌一", SubRouteUID: "TPE1",
				SubRouteName: "一路", StopUID: "STOP1", StopSequence: 1,
			}}}
			job := busLiveJob{
				fetch: bindFetch(src, sink, specByKey(t, "bus")), sink: sink, store: store,
				notifier: &captureBusArrivalNotifier{}, now: time.Now,
			}

			if err := job.runCity(context.Background(), "Taipei"); err != nil {
				t.Fatalf("runCity: %v", err)
			}
			if len(src.acked) != 1 || src.acked[0] != tt.modified {
				t.Fatalf("acked feeds = %v, want [%s]", src.acked, tt.modified)
			}
			if sw := sink.setFor(tt.writtenKey); sw == nil || sw.ttl != busFeedCacheTTL || string(sw.value) != `[]` {
				t.Fatalf("raw feed cache %s = %+v, want ttl %v", tt.writtenKey, sw, busFeedCacheTTL)
			}
			if ew := sink.expireFor(tt.cachedKey); ew == nil || ew.ttl != busFeedCacheTTL {
				t.Fatalf("cached counterpart %s expiry = %+v, want ttl %v", tt.cachedKey, ew, busFeedCacheTTL)
			}
			if sink.setFor(shared.BusRouteEtaKey("TPE1")) == nil {
				t.Fatal("combined route snapshot was not published")
			}
		})
	}
}

func TestBusMissingCachedCounterpartPersistsModifiedFeedAndInvalidatesMarker(t *testing.T) {
	prefix := citymap["Taipei"]
	busStaticMapCache.Delete(prefix)
	t.Cleanup(func() { busStaticMapCache.Delete(prefix) })
	src := &fakeLiveSource{fixtures: map[string][]byte{
		"bus_EstimatedTimeOfArrivalTaipei": []byte(`[]`),
	}}
	sink := &captureLiveSink{}
	store := &fakeBusEtaStore{stops: []busStationmap{{
		StationUID: "STATION1", StationName: "站牌一", SubRouteUID: "TPE1",
		SubRouteName: "一路", StopUID: "STOP1", StopSequence: 1,
	}}}
	job := busLiveJob{
		fetch: bindFetch(src, sink, specByKey(t, "bus")), sink: sink, store: store,
		notifier: &captureBusArrivalNotifier{}, now: time.Now,
	}

	if err := job.runCity(context.Background(), "Taipei"); err == nil {
		t.Fatal("missing cached counterpart returned nil error")
	}
	if sw := sink.setFor(shared.BusETARawKey("Taipei")); sw == nil || sw.ttl != busFeedCacheTTL {
		t.Fatalf("ETA raw cache = %+v, want durable bounded cache", sw)
	}
	if len(src.acked) != 1 || src.acked[0] != "bus_EstimatedTimeOfArrivalTaipei" {
		t.Fatalf("acked feeds = %v, want modified ETA", src.acked)
	}
	if len(src.invalidated) != 1 || src.invalidated[0] != "bus_RealTimeByFrequencyTaipei" {
		t.Fatalf("invalidated feeds = %v, want missing position marker", src.invalidated)
	}
}

func TestBusIndependentAckFailuresLeaveBothRawFeedsDurable(t *testing.T) {
	for _, failedFeed := range []string{
		"bus_EstimatedTimeOfArrivalTaipei",
		"bus_RealTimeByFrequencyTaipei",
	} {
		t.Run(failedFeed, func(t *testing.T) {
			prefix := citymap["Taipei"]
			busStaticMapCache.Delete(prefix)
			t.Cleanup(func() { busStaticMapCache.Delete(prefix) })
			ackErr := errors.New("marker write failed")
			src := &fakeLiveSource{
				fixtures: map[string][]byte{
					"bus_EstimatedTimeOfArrivalTaipei": []byte(`[]`),
					"bus_RealTimeByFrequencyTaipei":    []byte(`[]`),
				},
				ackErrors: map[string]error{failedFeed: ackErr},
			}
			sink := &captureLiveSink{}
			store := &fakeBusEtaStore{stops: []busStationmap{{
				StationUID: "STATION1", StationName: "站牌一", SubRouteUID: "TPE1",
				SubRouteName: "一路", StopUID: "STOP1", StopSequence: 1,
			}}}
			job := busLiveJob{
				fetch: bindFetch(src, sink, specByKey(t, "bus")), sink: sink, store: store,
				notifier: &captureBusArrivalNotifier{}, now: time.Now,
			}

			if err := job.runCity(context.Background(), "Taipei"); !errors.Is(err, ackErr) {
				t.Fatalf("runCity error = %v, want %v", err, ackErr)
			}
			if len(src.acked) != 2 {
				t.Fatalf("Ack attempts = %v, want both independent feeds", src.acked)
			}
			for _, key := range []string{shared.BusETARawKey("Taipei"), shared.BusPositionRawKey("Taipei")} {
				if sw := sink.setFor(key); sw == nil || sw.ttl != busFeedCacheTTL {
					t.Fatalf("raw feed cache %s = %+v", key, sw)
				}
			}
		})
	}
}

func TestMrtSpec304RefreshesTTLPerSystem(t *testing.T) {
	// The real mrt spec fetches four systems; with no fixtures every fetch 304s,
	// so its boundFetch must refresh the mrt_live TTL once per system (4×), never
	// writing an arrival.
	src := &fakeLiveSource{fixtures: map[string][]byte{}}
	sink := &captureLiveSink{}
	runLiveSpec(context.Background(), src, sink, specByKey(t, "mrt"))

	if len(sink.sets) != 0 {
		t.Fatalf("expected no SETs on all-304; got %v", setKeys(sink))
	}
	if len(sink.refresh) != 4 {
		t.Fatalf("refreshTTL calls = %d, want 4 (one per system)", len(sink.refresh))
	}
}

func TestBusSpec304RefreshesCityTTL(t *testing.T) {
	// The bus spec keeps its own precise per-city 304 refresh inside
	// busLiveJob.runCity: an ETA 304 re-arms exactly that city's station and route
	// key patterns with the 180s window. Driven directly (no db needed on the
	// skip path) with an all-304 source, using a static-map cache seeded for one
	// city so the fetch is reached.
	src := &fakeLiveSource{fixtures: map[string][]byte{}}
	sink := &captureLiveSink{}
	// Seed the per-prefix static map so busLiveJob.runCity does not hit the store.
	storeBusStaticMap(citymap["Taipei"], []busStationmap{{SubRouteUID: "TPE1", StopUID: "S1"}})
	t.Cleanup(func() { storeBusStaticMap(citymap["Taipei"], nil) })

	fetch := bindFetch(src, sink, specByKey(t, "bus"))
	job := busLiveJob{
		fetch:    fetch,
		sink:     sink,
		store:    pgBusEtaStore{},
		notifier: (*notify.Dispatcher)(nil),
		now:      time.Now,
	}
	job.runCity(context.Background(), "Taipei")

	if len(sink.refresh) != 1 {
		t.Fatalf("refreshTTL calls = %d, want 1", len(sink.refresh))
	}
	got := sink.refresh[0]
	want := busEtaTTLPatterns("Taipei")
	if len(got) != len(want) {
		t.Fatalf("refresh patterns = %+v, want %+v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("refresh pattern[%d] = %+v, want %+v", i, got[i], want[i])
		}
	}
}

func TestRunLiveIsolatesFailingSpec(t *testing.T) {
	// One spec whose run returns an error (or panics) must not prevent the others
	// from running: runLive isolates each job.
	var ran []string
	specs := []liveSpec{
		{key: "ok1", run: func(context.Context, boundFetch, liveSink) error {
			ran = append(ran, "ok1")
			return nil
		}},
		{key: "boom", run: func(context.Context, boundFetch, liveSink) error {
			return errors.New("boom")
		}},
		{key: "panic", run: func(context.Context, boundFetch, liveSink) error {
			panic("kaboom")
		}},
		{key: "ok2", run: func(context.Context, boundFetch, liveSink) error {
			ran = append(ran, "ok2")
			return nil
		}},
	}
	runLive(context.Background(), &fakeLiveSource{}, &captureLiveSink{}, specs, nil)
	if len(ran) != 2 || ran[0] != "ok1" || ran[1] != "ok2" {
		t.Fatalf("healthy specs ran = %v, want [ok1 ok2]", ran)
	}
}

func TestRunLiveFiltersByKey(t *testing.T) {
	// A non-empty keys slice runs only the matching specs.
	var ran []string
	specs := []liveSpec{
		{key: "a", run: func(context.Context, boundFetch, liveSink) error { ran = append(ran, "a"); return nil }},
		{key: "b", run: func(context.Context, boundFetch, liveSink) error { ran = append(ran, "b"); return nil }},
	}
	runLive(context.Background(), &fakeLiveSource{}, &captureLiveSink{}, specs, []string{"b"})
	if len(ran) != 1 || ran[0] != "b" {
		t.Fatalf("ran = %v, want [b]", ran)
	}
}

// setKeys lists captured SET keys for failure messages.
func setKeys(s *captureLiveSink) []string {
	out := make([]string, 0, len(s.sets))
	for _, w := range s.sets {
		out = append(out, w.key)
	}
	return out
}
