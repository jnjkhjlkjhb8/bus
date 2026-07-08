package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/go-redis/redis"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/protobuf/proto"
)

// fakeLiveSource is the liveSource seam's in-memory adapter: it serves committed
// fixture bytes for names it was seeded with, and reports a 304 Not-Modified
// (modified=false, err=nil) for every other name. That lets a test drive a job
// that loops over many partitions (cities/systems) while asserting on only the
// seeded one, and exercise the 304→TTL path for the rest.
type fakeLiveSource struct {
	fixtures map[string][]byte // key: fetch name → raw TDX JSON array
	calls    []string
}

func (s *fakeLiveSource) fetch(_ context.Context, _, name string) (*json.Decoder, bool, func(), error) {
	s.calls = append(s.calls, name)
	body, ok := s.fixtures[name]
	if !ok {
		// 304 Not-Modified: no body, no close, no error.
		return &json.Decoder{}, false, nil, nil
	}
	return json.NewDecoder(bytes.NewReader(body)), true, func() {}, nil
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
}

func (s *captureLiveSink) pipeline() livePipe { return &capturePipe{sink: s} }

func (s *captureLiveSink) refreshTTL(patterns []ttlPattern) {
	s.refresh = append(s.refresh, patterns)
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

func (p *capturePipe) Exec() error { return nil }

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
	for _, s := range liveRegistry(nil, nil, nil) {
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

func TestTraSpecMergesDelayIntoLiveboard(t *testing.T) {
	// The tra spec must cache the delay hash + all-snapshot from the delay feed,
	// then build per-station live boards from the liveboard feed. The delay hash is
	// read back from Redis for the merge; that read-back is deliberately outside
	// the sink seam (it stays on the concrete *redis.Client), so this fixture test
	// points rc at an unreachable addr — HGetAll then returns no delays with no
	// live Redis, exactly like loader_db_test.go. The Redis-round-trip merge-when-
	// present branch needs a live hash and is exercised in the integration path,
	// not this fixture unit test.
	rc := unreachableRedis(t)
	src := &fakeLiveSource{fixtures: map[string][]byte{
		"tra_delay":     readFixture(t, "tdx_tra_delay.json"),
		"tra_liveboard": readFixture(t, "tdx_tra_liveboard.json"),
	}}
	sink := &captureLiveSink{}
	spec := liveSpec{
		key:         "tra",
		ttlPatterns: nil,
		run: func(ctx context.Context, fetch boundFetch, s liveSink) error {
			traEta(ctx, fetch, s, rc)
			return nil
		},
	}
	runLiveSpec(context.Background(), src, sink, spec)

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
	// All-delay snapshot cached with the 3m TTL.
	if sw := sink.setFor(shared.TraDelayAllKey); sw == nil || sw.ttl != traLiveTTL {
		t.Fatalf("expected SET %s ttl=%v; got %+v", shared.TraDelayAllKey, traLiveTTL, sw)
	}
	// Liveboard for station 1000 carries train 1234, built and cached with 3m TTL.
	sw := sink.setFor(shared.TraLiveboardKey("1000"))
	if sw == nil {
		t.Fatalf("expected liveboard SET for station 1000; got %v", setKeys(sink))
	}
	if sw.ttl != traLiveTTL {
		t.Fatalf("liveboard ttl = %v, want %v", sw.ttl, traLiveTTL)
	}
	var board models.Tra_LiveBoards
	if err := proto.Unmarshal(sw.value, &board); err != nil {
		t.Fatalf("unmarshal Tra_LiveBoards: %v", err)
	}
	if len(board.Items) != 1 || board.Items[0].TrainNo != "1234" {
		t.Fatalf("liveboard items = %+v", board.Items)
	}
	if board.Items[0].EndingStationName != "屏東" || board.Items[0].TrainTypeName != "自強" {
		t.Fatalf("liveboard payload = %+v", board.Items[0])
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
	_, modified, _, err := fetch(context.Background(), "/x", "unseeded")
	if err != nil {
		t.Fatalf("fetch error: %v", err)
	}
	if modified {
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
	// processBusEtaCity: an ETA 304 re-arms exactly that city's station and route
	// key patterns with the 180s window. Driven directly (no db needed on the
	// skip path) with an all-304 source, using a static-map cache seeded for one
	// city so the fetch is reached.
	src := &fakeLiveSource{fixtures: map[string][]byte{}}
	sink := &captureLiveSink{}
	// Seed the per-prefix static map so processBusEtaCity does not hit the (nil) db.
	storeBusStaticMap(citymap["Taipei"], []busStationmap{{SubRouteUID: "TPE1", StopUID: "S1"}})
	t.Cleanup(func() { storeBusStaticMap(citymap["Taipei"], nil) })

	fetch := bindFetch(src, sink, specByKey(t, "bus"))
	processBusEtaCity(context.Background(), fetch, sink, nil, nil, "Taipei", nil)

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

// unreachableRedis returns a *redis.Client pointed at an unreachable addr with
// sub-millisecond timeouts, so the tra delay read-back (rc.HGetAll) fails fast
// and log-and-continues instead of blocking — no live Redis needed, matching
// loader_db_test.go's pattern.
func unreachableRedis(t *testing.T) *redis.Client {
	t.Helper()
	rc := redis.NewClient(&redis.Options{
		Addr:         "127.0.0.1:1",
		DialTimeout:  time.Millisecond,
		ReadTimeout:  time.Millisecond,
		WriteTimeout: time.Millisecond,
		MaxRetries:   0,
	})
	t.Cleanup(func() { _ = rc.Close() })
	return rc
}

// setKeys lists captured SET keys for failure messages.
func setKeys(s *captureLiveSink) []string {
	out := make([]string, 0, len(s.sets))
	for _, w := range s.sets {
		out = append(out, w.key)
	}
	return out
}
