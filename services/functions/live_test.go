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

	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"google.golang.org/protobuf/proto"
)

// fakeLiveSource is the liveSource seam's in-memory adapter: it serves committed
// fixture bytes for names it was seeded with, and reports a 304 Not-Modified
// (modified=false, err=nil) for every other name. That lets a test drive a job
// that loops over many partitions (cities/systems) while asserting on only the
// seeded one, and exercise the 304→TTL path for the rest.
type fakeLiveSource struct {
	fixtures      map[string][]byte // key: fetch name → raw TDX JSON array
	calls         []string
	acked         []string
	closed        []string
	invalidated   []string
	ackErr        error
	ackErrors     map[string]error
	closeErr      error
	invalidateErr error
}

func (s *fakeLiveSource) fetch(_ context.Context, _, name string) (*shared.TDXFetch, error) {
	s.calls = append(s.calls, name)
	body, ok := s.fixtures[name]
	if !ok {
		return &shared.TDXFetch{
			Modified: false,
			Invalidate: func() error {
				s.invalidated = append(s.invalidated, name)
				return s.invalidateErr
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
			return s.invalidateErr
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
	strings    map[string]string
	hashes     map[string]map[string]string
	owned      map[string][]string
	execErr    error
	execHook   func() error
	refreshErr error
	contexts   []context.Context
}

func (s *captureLiveSink) pipeline() livePipe {
	return &capturePipe{sink: s}
}

func (s *captureLiveSink) refreshTTL(_ context.Context, patterns []ttlPattern) error {
	s.refresh = append(s.refresh, patterns)
	return s.refreshErr
}

func (s *captureLiveSink) refreshOwnedTTL(ctx context.Context, key string, ttl time.Duration) error {
	members := s.owned[key]
	if len(members) == 0 {
		return nil
	}
	patterns := make([]ttlPattern, 0, len(members))
	for _, member := range members {
		patterns = append(patterns, ttlPattern{pattern: member, ttl: ttl})
	}
	return s.refreshTTL(ctx, patterns)
}

func (s *captureLiveSink) getString(_ context.Context, key string) (string, error) {
	if v, ok := s.strings[key]; ok {
		return v, nil
	}
	return "", redis.Nil
}

func (s *captureLiveSink) getHash(_ context.Context, key string) (map[string]string, error) {
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
	sink                *captureLiveSink
	pendingOwnedKey     string
	pendingOwnedMembers []string
}

func (p *capturePipe) Set(key string, value any, ttl time.Duration) {
	p.sink.sets = append(p.sink.sets, setWrite{key: key, value: toBytes(value), ttl: ttl})
	// Make the write visible to getString, as Redis would: liveDemandGate reads
	// back a marker it wrote on an earlier tick, so a write-only fake would let
	// it fetch every tick and the gate would test as working while doing nothing.
	if p.sink.strings == nil {
		p.sink.strings = map[string]string{}
	}
	p.sink.strings[key] = string(toBytes(value))
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

func (p *capturePipe) ReplaceOwnedKeys(key string, members []string, _ time.Duration) {
	p.pendingOwnedKey = key
	p.pendingOwnedMembers = append([]string(nil), members...)
}

func (p *capturePipe) Exec(ctx context.Context) error {
	// Recorded here rather than at pipeline construction: Exec is the call that
	// carries the context to Redis, so this is what the job must be propagating.
	p.sink.contexts = append(p.sink.contexts, ctx)
	if p.sink.execHook != nil {
		if err := p.sink.execHook(); err != nil {
			return err
		}
	}
	if p.sink.execErr != nil {
		return p.sink.execErr
	}
	if p.pendingOwnedKey != "" {
		if p.sink.owned == nil {
			p.sink.owned = make(map[string][]string)
		}
		p.sink.owned[p.pendingOwnedKey] = append([]string(nil), p.pendingOwnedMembers...)
	}
	return nil
}

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

// _trtcTestNames is the station-name fixture the TRTC live tests resolve
// against (mrt_station is not available in unit tests).
var _trtcTestNames = map[string][]string{
	"台北車站":  {"BL12", "R10"},
	"南港展覽館": {"BL23", "BR24"},
	"頂埔":    {"BL01"},
}

// _trtcTestTracks: two arrivals at BL12 toward opposite BL terminals; train 215
// has a congestion reading, train 222 does not.
var _trtcTestTracks = []trtcTrack{
	{TrainNumber: "215", StationName: "台北車站", DestinationName: "南港展覽館站", CountDown: "02:00", NowDateTime: "2026-07-22 15:09:55"},
	{TrainNumber: "222", StationName: "台北車站", DestinationName: "頂埔站", CountDown: "01:10", NowDateTime: "2026-07-22 15:09:55"},
}

func TestTrtcPublishWritesArrivals(t *testing.T) {
	// The TRTC publish core must write one per-(station,line,dest) key and
	// publish per-station updates, with the countdown parsed into EstimateTime
	// and train 215's congestion paired on (congestion pairing, CONTEXT.md).
	sink := &captureLiveSink{}
	exRows := []trtcWeightEx{{TrainNumber: "215", CN1: "163/164", StationID: "BL10",
		Cart1L: "1", Cart2L: "2", Cart3L: "2", Cart4L: "2", Cart5L: "2", Cart6L: "1"}}
	if err := trtcPublish(context.Background(), sink, _trtcTestNames, nil, time.Now(), _trtcTestTracks, exRows, nil); err != nil {
		t.Fatalf("trtcPublish: %v", err)
	}

	key := shared.MrtLiveKey("TRTC", "BL12", "BL", "BL23")
	sw := sink.setFor(key)
	if sw == nil {
		t.Fatalf("expected SET for %s; got keys %v", key, setKeys(sink))
	}
	if sw.ttl != _mrtLiveTTL {
		t.Fatalf("mrt SET ttl = %v, want %v", sw.ttl, _mrtLiveTTL)
	}
	var got models.MrtLive
	if err := proto.Unmarshal(sw.value, &got); err != nil {
		t.Fatalf("unmarshal MrtLive: %v", err)
	}
	if got.System != "TRTC" || got.StationID != "BL12" || got.LineID != "BL" {
		t.Fatalf("MrtLive identity = %+v", &got)
	}
	if got.EstimateTime != 120 || got.DestinationStationName != "南港展覽館" || got.CountDown != "02:00" {
		t.Fatalf("MrtLive payload = %+v", &got)
	}
	if got.Weight == nil || got.Weight.Cart2L != "2" || got.CN1 != "163/164" {
		t.Fatalf("MrtLive congestion = %+v", &got)
	}
	// The number-less pairing must not leak: train 222 has no congestion.
	other := sink.setFor(shared.MrtLiveKey("TRTC", "BL12", "BL", "BL01"))
	if other == nil {
		t.Fatalf("expected SET for opposite destination; got keys %v", setKeys(sink))
	}
	var plain models.MrtLive
	if err := proto.Unmarshal(other.value, &plain); err != nil {
		t.Fatalf("unmarshal MrtLive: %v", err)
	}
	if plain.Weight != nil {
		t.Fatalf("unpaired arrival carries congestion: %+v", &plain)
	}
	// Both rows share station BL12, so both publish the station channel.
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

func TestTrtcOppositeDestinationsUseDistinctRedisKeys(t *testing.T) {
	sink := &captureLiveSink{}
	if err := trtcPublish(context.Background(), sink, _trtcTestNames, nil, time.Now(), _trtcTestTracks, nil, nil); err != nil {
		t.Fatalf("trtcPublish: %v", err)
	}
	keys := map[string]struct{}{}
	for _, write := range sink.sets {
		if strings.HasPrefix(write.key, shared.MrtLiveChannel("TRTC", "BL12")+":") {
			keys[write.key] = struct{}{}
		}
	}
	if len(keys) != 2 {
		t.Fatalf("distinct Redis keys for opposite BL destinations = %d, want 2; writes=%v", len(keys), setKeys(sink))
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
	if sw := sink.setFor(shared.TraDelayAllKey); sw == nil || sw.ttl != _traLiveTTL {
		t.Fatalf("expected SET %s ttl=%v; got %+v", shared.TraDelayAllKey, _traLiveTTL, sw)
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
	trainChannel := shared.TraDelayTrainChannel("1234")
	var trainPublish *publishWrite
	for i := range sink.publishs {
		if sink.publishs[i].channel == trainChannel {
			trainPublish = &sink.publishs[i]
		}
	}
	if trainPublish == nil {
		t.Fatalf("expected per-train PUBLISH to %s; got %+v", trainChannel, sink.publishs)
	}
	var trainSnapshot models.TraDelays
	if err := proto.Unmarshal(trainPublish.value, &trainSnapshot); err != nil {
		t.Fatalf("unmarshal per-train delay: %v", err)
	}
	if len(trainSnapshot.Delay) != 1 || trainSnapshot.Delay["1234"] != 5 {
		t.Fatalf("per-train snapshot = %+v", trainSnapshot.Delay)
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
	if sw.ttl != _bikeLiveTTL {
		t.Fatalf("bike SET ttl = %v, want %v", sw.ttl, _bikeLiveTTL)
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

	date := time.Now().In(_taipei).Format(time.DateOnly)

	// Train 0801 carries both fixture segments, aggregated into one snapshot.
	sw := sink.setFor(shared.ThsrSeatsKey(date, "0801"))
	if sw == nil {
		t.Fatalf("expected SET for train 0801; got keys %v", setKeys(sink))
	}
	if sw.ttl != _thsrSeatsLiveTTL {
		t.Fatalf("thsr seats SET ttl = %v, want %v", sw.ttl, _thsrSeatsLiveTTL)
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
	date := time.Now().In(_taipei).Format(time.DateOnly)
	got := sink.refresh[0]
	if len(got) != 1 || got[0].pattern != shared.ThsrSeatsPattern(date) || got[0].ttl != _thsrSeatsLiveTTL {
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
		ttlPatterns: func(string) []ttlPattern {
			return []ttlPattern{{pattern: "mrt_live:*", ttl: _mrtLiveTTL}}
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
	if len(got) != 1 || got[0].pattern != "mrt_live:*" || got[0].ttl != _mrtLiveTTL {
		t.Fatalf("refresh patterns = %+v", got)
	}
}

func TestBoundFetchReturnsTTLRefreshError(t *testing.T) {
	wantErr := errors.New("expire failed")
	src := &fakeLiveSource{fixtures: map[string][]byte{}}
	sink := &captureLiveSink{refreshErr: wantErr}
	spec := liveSpec{
		key: "probe",
		ttlPatterns: func(string) []ttlPattern {
			return []ttlPattern{{pattern: "probe:*", ttl: time.Minute}}
		},
	}
	_, err := bindFetch(src, sink, spec)(context.Background(), "/probe", "probe")
	if !errors.Is(err, wantErr) {
		t.Fatalf("304 refresh error = %v, want %v", err, wantErr)
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

func TestRealtimePipelineFailureDoesNotAcknowledge(t *testing.T) {
	wantErr := errors.New("redis pipeline failed")
	tests := []struct {
		name    string
		specKey string
		fixture string
		body    []byte
	}{
		{name: "bike", specKey: "bike", fixture: "bike_availabilityTaipei", body: readFixture(t, "tdx_bike_availability.json")},
		{name: "tra", specKey: "tra", fixture: "tra_delay", body: readFixture(t, "tdx_tra_delay.json")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			src := &fakeLiveSource{fixtures: map[string][]byte{tt.fixture: tt.body}}
			sink := &captureLiveSink{execErr: wantErr}
			spec := specByKey(t, tt.specKey)
			err := spec.run(context.Background(), bindFetch(src, sink, spec), sink)
			if !errors.Is(err, wantErr) {
				t.Fatalf("pipeline error = %v, want wrapped %v", err, wantErr)
			}
			if len(src.acked) != 0 {
				t.Fatalf("pipeline failure acknowledged marker: %v", src.acked)
			}
		})
	}
}

// The TRTC job has no TDX marker to (not) acknowledge, but the pipeline
// invariant still holds: a failed Exec must surface as the job error.
func TestTrtcPublishExecFailure(t *testing.T) {
	wantErr := errors.New("redis pipeline failed")
	sink := &captureLiveSink{execErr: wantErr}
	err := trtcPublish(context.Background(), sink, _trtcTestNames, nil, time.Now(), _trtcTestTracks, nil, nil)
	if !errors.Is(err, wantErr) {
		t.Fatalf("pipeline error = %v, want wrapped %v", err, wantErr)
	}
}

func TestRealtimePipelineReceivesJobContext(t *testing.T) {
	type contextKey string
	ctx := context.WithValue(context.Background(), contextKey("job"), "bike")
	src := &fakeLiveSource{fixtures: map[string][]byte{
		"bike_availabilityTaipei": readFixture(t, "tdx_bike_availability.json"),
	}}
	sink := &captureLiveSink{}
	spec := specByKey(t, "bike")
	if err := spec.run(ctx, bindFetch(src, sink, spec), sink); err != nil {
		t.Fatalf("bike run: %v", err)
	}
	if len(sink.contexts) == 0 || sink.contexts[0] != ctx {
		t.Fatalf("pipeline contexts = %v, want job context", sink.contexts)
	}
}

func TestAllRealtimeWritersCancelDuringExecWithoutAck(t *testing.T) {
	tests := []struct {
		name     string
		fixtures map[string][]byte
		run      func(context.Context, *fakeLiveSource, *captureLiveSink) error
	}{
		{name: "bike", fixtures: map[string][]byte{"bike_availabilityTaipei": readFixture(t, "tdx_bike_availability.json")}, run: func(ctx context.Context, src *fakeLiveSource, sink *captureLiveSink) error {
			spec := specByKey(t, "bike")
			return spec.run(ctx, bindFetch(src, sink, spec), sink)
		}},
		// mrt is TRTC-sourced now (no TDX fetch/marker); it keeps the same
		// cancel-during-Exec invariant via trtcPublish, driven fixture-direct.
		{name: "mrt", fixtures: map[string][]byte{}, run: func(ctx context.Context, src *fakeLiveSource, sink *captureLiveSink) error {
			return trtcPublish(ctx, sink, _trtcTestNames, nil, time.Now(), _trtcTestTracks, nil, nil)
		}},
		{name: "tra", fixtures: map[string][]byte{"tra_delay": readFixture(t, "tdx_tra_delay.json")}, run: func(ctx context.Context, src *fakeLiveSource, sink *captureLiveSink) error {
			spec := specByKey(t, "tra")
			return spec.run(ctx, bindFetch(src, sink, spec), sink)
		}},
		{name: "thsr", fixtures: map[string][]byte{"thsr_availableseats": readFixture(t, "tdx_thsr_availableseats.json")}, run: func(ctx context.Context, src *fakeLiveSource, sink *captureLiveSink) error {
			spec := specByKey(t, "thsr_seats")
			return spec.run(ctx, bindFetch(src, sink, spec), sink)
		}},
		{name: "bus", fixtures: map[string][]byte{
			"bus_EstimatedTimeOfArrivalTaipei": []byte(`[]`),
			"bus_RealTimeByFrequencyTaipei":    []byte(`[]`),
		}, run: func(ctx context.Context, src *fakeLiveSource, sink *captureLiveSink) error {
			prefix := _citymap["Taipei"]
			_busStaticMapCache.Delete(prefix)
			t.Cleanup(func() { _busStaticMapCache.Delete(prefix) })
			job := busLiveJob{
				fetch: bindFetch(src, sink, specByKey(t, "bus")), sink: sink,
				store:    &fakeBusEtaStore{stops: []busStationmap{{StationUID: "S", SubRouteUID: "TPE1", StopUID: "STOP", StopSequence: 1}}},
				notifier: &captureBusArrivalNotifier{}, now: time.Now,
			}
			return job.runCity(ctx, "Taipei")
		}},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			ctx, cancel := context.WithCancel(context.Background())
			src := &fakeLiveSource{fixtures: test.fixtures}
			execStarted := false
			sink := &captureLiveSink{execHook: func() error {
				execStarted = true
				cancel()
				<-ctx.Done()
				return ctx.Err()
			}}
			err := test.run(ctx, src, sink)
			if !execStarted {
				t.Fatal("test did not cancel during Exec")
			}
			if !errors.Is(err, context.Canceled) {
				t.Fatalf("writer error = %v, want context canceled", err)
			}
			if len(src.acked) != 0 {
				t.Fatalf("canceled Exec acknowledged TDX marker: %v", src.acked)
			}
			if len(sink.contexts) == 0 || sink.contexts[0] != ctx {
				t.Fatalf("pipeline contexts = %v, want job context", sink.contexts)
			}
		})
	}
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
	prefix := _citymap["Taipei"]
	_busStaticMapCache.Delete(prefix)
	t.Cleanup(func() { _busStaticMapCache.Delete(prefix) })

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
	prefix := _citymap["Taipei"]
	_busStaticMapCache.Delete(prefix)
	t.Cleanup(func() { _busStaticMapCache.Delete(prefix) })

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

func TestReadBusFeedCacheRejectsNullButAcceptsEmptyArray(t *testing.T) {
	const key = "bus:raw:test"

	nullSink := &captureLiveSink{strings: map[string]string{key: `null`}}
	values, err := readBusFeedCache[rawBusEsimated](context.Background(), nullSink, key)
	if !errors.Is(err, errBusFeedCacheMiss) {
		t.Fatalf("null cache error = %v, want %v", err, errBusFeedCacheMiss)
	}
	if values != nil {
		t.Fatalf("null cache values = %#v, want nil", values)
	}

	emptySink := &captureLiveSink{strings: map[string]string{key: `[]`}}
	values, err = readBusFeedCache[rawBusEsimated](context.Background(), emptySink, key)
	if err != nil {
		t.Fatalf("empty array cache error = %v", err)
	}
	if values == nil || len(values) != 0 {
		t.Fatalf("empty array cache values = %#v, want non-nil empty slice", values)
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
			prefix := _citymap["Taipei"]
			_busStaticMapCache.Delete(prefix)
			t.Cleanup(func() { _busStaticMapCache.Delete(prefix) })

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
			if sw := sink.setFor(tt.writtenKey); sw == nil || sw.ttl != _busFeedCacheTTL || string(sw.value) != `[]` {
				t.Fatalf("raw feed cache %s = %+v, want ttl %v", tt.writtenKey, sw, _busFeedCacheTTL)
			}
			if ew := sink.expireFor(tt.cachedKey); ew == nil || ew.ttl != _busFeedCacheTTL {
				t.Fatalf("cached counterpart %s expiry = %+v, want ttl %v", tt.cachedKey, ew, _busFeedCacheTTL)
			}
			if sink.setFor(shared.BusRouteEtaKey("TPE1")) == nil {
				t.Fatal("combined route snapshot was not published")
			}
		})
	}
}

func TestBusMissingCachedCounterpartPersistsModifiedFeedAndInvalidatesMarker(t *testing.T) {
	prefix := _citymap["Taipei"]
	_busStaticMapCache.Delete(prefix)
	t.Cleanup(func() { _busStaticMapCache.Delete(prefix) })
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
	if sw := sink.setFor(shared.BusETARawKey("Taipei")); sw == nil || sw.ttl != _busFeedCacheTTL {
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
			prefix := _citymap["Taipei"]
			_busStaticMapCache.Delete(prefix)
			t.Cleanup(func() { _busStaticMapCache.Delete(prefix) })
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
				if sw := sink.setFor(key); sw == nil || sw.ttl != _busFeedCacheTTL {
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
	if len(sink.refresh) != 0 {
		t.Fatalf("never-owned systems refreshed keys on 304: %+v", sink.refresh)
	}
}

func TestBike304RefreshesOnlyPartitionOwnedKeys(t *testing.T) {
	src := &fakeLiveSource{fixtures: map[string][]byte{
		"bike_availabilityTaipei": readFixture(t, "tdx_bike_availability.json"),
	}}
	sink := &captureLiveSink{}
	spec := specByKey(t, "bike")
	if err := spec.run(context.Background(), bindFetch(src, sink, spec), sink); err != nil {
		t.Fatalf("initial bike update: %v", err)
	}

	src.fixtures = map[string][]byte{}
	sink.refresh = nil
	if err := spec.run(context.Background(), bindFetch(src, sink, spec), sink); err != nil {
		t.Fatalf("bike 304 update: %v", err)
	}
	want := map[string]bool{
		shared.BikeAvailabilityKey("TPE500101001"): true,
		shared.BikeAvailabilityKey("TPE500101002"): true,
	}
	if len(sink.refresh) != 1 || len(sink.refresh[0]) != len(want) {
		t.Fatalf("bike 304 refreshes = %+v, want owned keys %v", sink.refresh, want)
	}
	for _, refresh := range sink.refresh[0] {
		if !want[refresh.pattern] || refresh.ttl != _bikeLiveTTL {
			t.Fatalf("bike 304 refreshed unowned key or wrong TTL: %+v", refresh)
		}
	}
}

func TestFailedFullUpdateDoesNotReplacePartitionOwnership(t *testing.T) {
	wantErr := errors.New("redis exec failed")
	owner := shared.LiveOwnedKeysKey("bike", "Taipei")
	sink := &captureLiveSink{
		owned:   map[string][]string{owner: {"bike_availability:OLD"}},
		execErr: wantErr,
	}
	src := &fakeLiveSource{fixtures: map[string][]byte{
		"bike_availabilityTaipei": readFixture(t, "tdx_bike_availability.json"),
	}}
	spec := specByKey(t, "bike")
	if err := spec.run(context.Background(), bindFetch(src, sink, spec), sink); !errors.Is(err, wantErr) {
		t.Fatalf("bike update error = %v, want %v", err, wantErr)
	}
	if got := sink.owned[owner]; len(got) != 1 || got[0] != "bike_availability:OLD" {
		t.Fatalf("ownership after failed update = %v, want previous ownership", got)
	}
}

func TestRedisOwnedTTLIntegration(t *testing.T) {
	addr := os.Getenv("REDIS_TEST_ADDR")
	if addr == "" {
		t.Skip("REDIS_TEST_ADDR not set")
	}
	rc := redis.NewClient(&redis.Options{Addr: addr})
	defer func() { _ = rc.Close() }()
	if err := rc.FlushDB(context.Background()).Err(); err != nil {
		t.Fatalf("flush Redis: %v", err)
	}
	t.Cleanup(func() { _ = rc.FlushDB(context.Background()).Err() })
	owner := shared.LiveOwnedKeysKey("bike", "Taipei")
	owned := shared.BikeAvailabilityKey("TPE-OWNED")
	unowned := shared.BikeAvailabilityKey("NWT-UNOWNED")
	pipe := redisLiveSink{rc: rc}.pipeline()
	pipe.Set(owned, "owned", 5*time.Second)
	pipe.Set(unowned, "unowned", 5*time.Second)
	pipe.ReplaceOwnedKeys(owner, []string{owned}, _ownedKeysTTL)
	if err := pipe.Exec(context.Background()); err != nil {
		t.Fatalf("seed ownership: %v", err)
	}
	if err := (redisLiveSink{rc: rc}).refreshOwnedTTL(context.Background(), owner, _bikeLiveTTL); err != nil {
		t.Fatalf("refresh owned TTL: %v", err)
	}
	ownedTTL, err := rc.PTTL(context.Background(), owned).Result()
	if err != nil || ownedTTL < time.Minute {
		t.Fatalf("owned TTL = %v, err=%v, want refreshed", ownedTTL, err)
	}
	unownedTTL, err := rc.PTTL(context.Background(), unowned).Result()
	if err != nil || unownedTTL <= 0 || unownedTTL >= 30*time.Second {
		t.Fatalf("unowned TTL = %v, err=%v, want original short TTL", unownedTTL, err)
	}
}

type revalidationLiveSource struct {
	target               string
	body                 []byte
	markerPresent        bool
	invalidationAttempts int
	invalidateErr        error
}

func (s *revalidationLiveSource) fetch(_ context.Context, _, name string) (*shared.TDXFetch, error) {
	if name != s.target {
		return &shared.TDXFetch{Modified: false, Invalidate: func() error { return nil }}, nil
	}
	if !s.markerPresent {
		return &shared.TDXFetch{
			Modified: true,
			Decoder:  json.NewDecoder(bytes.NewReader(s.body)),
			Close:    func() error { return nil },
			Ack: func() error {
				s.markerPresent = true
				return nil
			},
		}, nil
	}
	return &shared.TDXFetch{Modified: false, Invalidate: func() error {
		s.invalidationAttempts++
		if s.invalidateErr != nil {
			return s.invalidateErr
		}
		s.markerPresent = false
		return nil
	}}, nil
}

func TestRedisMissingOwnedMemberRetriesInvalidationThenReplacesOwner(t *testing.T) {
	addr := os.Getenv("REDIS_TEST_ADDR")
	if addr == "" {
		t.Skip("REDIS_TEST_ADDR not set")
	}
	rc := redis.NewClient(&redis.Options{Addr: addr})
	defer func() { _ = rc.Close() }()
	if err := rc.FlushDB(context.Background()).Err(); err != nil {
		t.Fatalf("flush Redis: %v", err)
	}
	t.Cleanup(func() { _ = rc.FlushDB(context.Background()).Err() })
	owner := shared.LiveOwnedKeysKey("bike", "Taipei")
	missing := shared.BikeAvailabilityKey("EXPIRED")
	if err := rc.SAdd(context.Background(), owner, missing).Err(); err != nil {
		t.Fatalf("seed stale owner: %v", err)
	}
	if err := rc.Expire(context.Background(), owner, 5*time.Minute).Err(); err != nil {
		t.Fatalf("expire owner: %v", err)
	}
	invalidateErr := errors.New("invalidate marker failed")
	src := &revalidationLiveSource{
		target:        "bike_availabilityTaipei",
		body:          readFixture(t, "tdx_bike_availability.json"),
		markerPresent: true,
		invalidateErr: invalidateErr,
	}
	spec := specByKey(t, "bike")
	fetch := bindFetch(src, redisLiveSink{rc: rc}, spec)

	for attempt := 1; attempt <= 2; attempt++ {
		if _, err := fetch(context.Background(), "/bike", src.target); !errors.Is(err, invalidateErr) {
			t.Fatalf("attempt %d stale ownership error = %v, want joined invalidation error", attempt, err)
		}
		if !src.markerPresent {
			t.Fatalf("attempt %d cleared marker despite failed invalidation", attempt)
		}
		if exists, err := rc.Exists(context.Background(), owner).Result(); err != nil || exists != 1 {
			t.Fatalf("attempt %d stale owner exists=%d err=%v, want retained for retry", attempt, exists, err)
		}
	}
	if src.invalidationAttempts != 2 {
		t.Fatalf("invalidation attempts = %d, want 2", src.invalidationAttempts)
	}
	ownerTTL, err := rc.PTTL(context.Background(), owner).Result()
	if err != nil || ownerTTL <= 0 || ownerTTL >= 10*time.Minute {
		t.Fatalf("stale owner TTL = %v err=%v, want retained without 24h renewal", ownerTTL, err)
	}

	src.invalidateErr = nil
	if _, err := fetch(context.Background(), "/bike", src.target); err == nil {
		t.Fatal("successful marker invalidation hid stale ownership error")
	}
	if src.markerPresent {
		t.Fatal("successful invalidation left marker present")
	}
	if exists, err := rc.Exists(context.Background(), owner).Result(); err != nil || exists != 1 {
		t.Fatalf("stale owner after successful invalidation exists=%d err=%v, want retained until full write", exists, err)
	}

	if err := spec.run(context.Background(), bindFetch(src, redisLiveSink{rc: rc}, spec), redisLiveSink{rc: rc}); err != nil {
		t.Fatalf("full bike refresh after invalidation: %v", err)
	}
	wantMembers := map[string]bool{
		shared.BikeAvailabilityKey("TPE500101001"): true,
		shared.BikeAvailabilityKey("TPE500101002"): true,
	}
	members, err := rc.SMembers(context.Background(), owner).Result()
	if err != nil {
		t.Fatalf("read replacement owner: %v", err)
	}
	if len(members) != len(wantMembers) {
		t.Fatalf("replacement owner members = %v, want %v", members, wantMembers)
	}
	for _, member := range members {
		if !wantMembers[member] {
			t.Fatalf("replacement owner retained stale member %q", member)
		}
	}
}

func TestRedisCanceledTHSRExecDoesNotAcknowledge(t *testing.T) {
	addr := os.Getenv("REDIS_TEST_ADDR")
	if addr == "" {
		t.Skip("REDIS_TEST_ADDR not set")
	}
	rc := redis.NewClient(&redis.Options{Addr: addr})
	defer func() { _ = rc.Close() }()
	if err := rc.FlushDB(context.Background()).Err(); err != nil {
		t.Fatalf("flush Redis: %v", err)
	}
	if err := rc.Do(context.Background(), "CLIENT", "PAUSE", 250, "WRITE").Err(); err != nil {
		t.Fatalf("pause Redis writes: %v", err)
	}
	src := &fakeLiveSource{fixtures: map[string][]byte{
		"thsr_availableseats": readFixture(t, "tdx_thsr_availableseats.json"),
	}}
	spec := specByKey(t, "thsr_seats")
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Millisecond)
	defer cancel()
	started := time.Now()
	err := spec.run(ctx, bindFetch(src, redisLiveSink{rc: rc}, spec), redisLiveSink{rc: rc})
	elapsed := time.Since(started)
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("THSR Exec error = %v, want context deadline exceeded", err)
	}
	if elapsed < 150*time.Millisecond {
		t.Fatalf("canceled THSR returned after %v while paused transaction was still pending", elapsed)
	}
	if len(src.closed) != 1 {
		t.Fatalf("THSR response closes = %d, want decode reached before cancellation", len(src.closed))
	}
	if len(src.acked) != 0 {
		t.Fatalf("canceled Redis Exec acknowledged marker: %v", src.acked)
	}
	key := shared.ThsrSeatsKey(time.Now().In(_taipei).Format(time.DateOnly), "0801")
	const newer = "newer same-runner snapshot"
	if err := rc.Set(context.Background(), key, newer, time.Minute).Err(); err != nil {
		t.Fatalf("write newer snapshot after canceled call returned: %v", err)
	}
	time.Sleep(100 * time.Millisecond)
	got, err := rc.Get(context.Background(), key).Result()
	if err != nil {
		t.Fatalf("read final snapshot: %v", err)
	}
	if got != newer {
		t.Fatalf("final snapshot = %q, want newer write; canceled transaction landed late", got)
	}
}

func TestRedisLivePipelineRejectsUnboundedSocketWait(t *testing.T) {
	rc := redis.NewClient(&redis.Options{
		Addr:        "127.0.0.1:1",
		ReadTimeout: -1,
	})
	defer func() { _ = rc.Close() }()
	pipe := redisLiveSink{rc: rc}.pipeline()
	pipe.Set("unreachable", "value", time.Minute)
	if err := pipe.Exec(context.Background()); err == nil || !errMentions(err, "finite Redis read timeout") {
		t.Fatalf("Exec error = %v, want finite-timeout guard", err)
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

// TestLiveDemandGateSkipsUnwatchedCityUntilColdCadence covers the whole point
// of the gate (FDPL-90): an unwatched city must be fetched once per cold
// cadence, not once per tick, and a watched one must never be skipped. It runs
// ticks against one sink so the cold marker written by the first tick is the
// one later ticks read back.
func TestLiveDemandGateSkipsUnwatchedCityUntilColdCadence(t *testing.T) {
	ctx := context.Background()

	sink := &captureLiveSink{}
	fetched := 0
	for range 10 {
		if liveDemandGate(ctx, sink, "bus_eta", "YilanCounty") {
			fetched++
		}
	}
	if fetched != 1 {
		t.Fatalf("unwatched city fetched %d times across 10 ticks, want 1", fetched)
	}
	coldKey := shared.LiveColdKey("bus_eta", "YilanCounty")
	if got := sink.strings[coldKey]; got == "" {
		t.Fatalf("cold marker %q not written", coldKey)
	}
	for _, write := range sink.sets {
		if write.key == coldKey && write.ttl != _liveColdCadence {
			t.Fatalf("cold marker TTL = %v, want %v", write.ttl, _liveColdCadence)
		}
	}

	// The marker expiring is what lets the next fetch through; the fake has no
	// clock, so dropping the key is how a tick past the cadence is expressed.
	delete(sink.strings, coldKey)
	if !liveDemandGate(ctx, sink, "bus_eta", "YilanCounty") {
		t.Fatal("expired cold marker did not release the next fetch")
	}

	watched := &captureLiveSink{
		strings: map[string]string{shared.LiveDemandKey("bus_eta", "YilanCounty"): "1"},
	}
	for range 10 {
		if !liveDemandGate(ctx, watched, "bus_eta", "YilanCounty") {
			t.Fatal("watched city was skipped")
		}
	}
	if len(watched.sets) != 0 {
		t.Fatalf("watched city wrote %d cold markers, want 0", len(watched.sets))
	}

	// A city gated under one dataset must not silence the other: the two jobs
	// poll independently and share nothing but the city name.
	if !liveDemandGate(ctx, sink, "bike", "YilanCounty") {
		t.Fatal("bike was gated by the bus_eta cold marker")
	}
}

// TestLiveDemandGateFetchesWhenRedisFails proves the gate degrades to polling
// rather than to silence: a Redis read failure must not be read as "nobody is
// watching", which would stall every city at once.
func TestLiveDemandGateFetchesWhenRedisFails(t *testing.T) {
	sink := &errStringLiveSink{captureLiveSink: &captureLiveSink{}, err: errors.New("redis down")}
	if !liveDemandGate(context.Background(), sink, "bus_eta", "YilanCounty") {
		t.Fatal("gate skipped the city on a Redis read failure")
	}
}

// errStringLiveSink is a captureLiveSink whose reads always fail.
type errStringLiveSink struct {
	*captureLiveSink
	err error
}

func (s *errStringLiveSink) getString(context.Context, string) (string, error) {
	return "", s.err
}

// TestBusEtaSnapshotTickIgnoresDemandGate covers the interaction the demand
// gate would otherwise break silently (FDPL-90).
//
// snapshotTick is a fixed 30s window per 10 minutes of wall clock, so a
// reduced-cadence fetch lands inside it only about one time in twenty. Gating
// snapshot ticks would cost an unwatched city roughly nine tenths of its
// bus_eta_history rows, and those are the only input segmentsByEstimate
// reduces into bus_segment_time — the observed running times the ETA
// prediction leans on hardest in exactly the rural cities nobody streams.
func TestBusEtaSnapshotTickIgnoresDemandGate(t *testing.T) {
	ctx := context.Background()
	sink := &captureLiveSink{}

	// Go cold first, so the gate alone would skip every later tick.
	if !liveDemandGate(ctx, sink, "bus_eta", "YilanCounty") {
		t.Fatal("first tick was skipped")
	}
	if liveDemandGate(ctx, sink, "bus_eta", "YilanCounty") {
		t.Fatal("second tick was not skipped, so the city is not cold")
	}

	snapshot := busLiveJob{sink: sink, demandDataset: "bus_eta", snapshot: true}
	if !snapshot.shouldRunCity(ctx, "YilanCounty") {
		t.Fatal("a snapshot tick was gated away; bus_eta_history would lose the city")
	}

	// The same job on an ordinary tick is still gated, or the gate saves nothing.
	ordinary := busLiveJob{sink: sink, demandDataset: "bus_eta"}
	if ordinary.shouldRunCity(ctx, "YilanCounty") {
		t.Fatal("a cold city ran on an ordinary tick")
	}

	// busEtaFast carries no dataset, so it is never gated at all.
	fast := busLiveJob{sink: sink}
	if !fast.shouldRunCity(ctx, "YilanCounty") {
		t.Fatal("the ungated Data.taipei job was gated")
	}
}
