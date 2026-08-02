package main

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
	"github.com/redis/go-redis/v9"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// fakeLiveSource is the in-memory adapter at the liveSource seam. publish
// pushes a live frame; the ops slice records call order so ordering
// invariants (subscribe before seed) are assertable.
type fakeLiveSource struct {
	values map[string][]byte
	scans  map[string][]string
	ch     chan []byte
	ops    []string
}

func newFakeLiveSource() *fakeLiveSource {
	return &fakeLiveSource{
		values: map[string][]byte{},
		scans:  map[string][]string{},
		ch:     make(chan []byte, 16),
	}
}

func (f *fakeLiveSource) get(_ context.Context, key string) ([]byte, bool) {
	f.ops = append(f.ops, "get:"+key)
	v, ok := f.values[key]
	return v, ok
}

func (f *fakeLiveSource) scanKeys(_ context.Context, pattern string) []string {
	f.ops = append(f.ops, "scan:"+pattern)
	return f.scans[pattern]
}

func (f *fakeLiveSource) subscribe(_ context.Context, channel string) (<-chan []byte, func(), error) {
	f.ops = append(f.ops, "subscribe:"+channel)
	return f.ch, func() { f.ops = append(f.ops, "close:"+channel) }, nil
}

// run streamLive in a goroutine, collecting sent frames; returns a cancel
// func and a way to wait for the final error.
func startStream(t *testing.T, src *fakeLiveSource, spec LiveStreamSpec) (sent func() [][]byte, cancel func(), wait func() error) {
	t.Helper()
	ctx, cancelCtx := context.WithCancel(context.Background())
	var frames [][]byte
	got := make(chan []byte, 16)
	errc := make(chan error, 1)
	go func() {
		errc <- StreamLive(ctx, src, spec, func(b []byte) error {
			got <- b
			return nil
		})
	}()
	sent = func() [][]byte {
		for {
			select {
			case b := <-got:
				frames = append(frames, b)
			case <-time.After(50 * time.Millisecond):
				return frames
			}
		}
	}
	return sent, cancelCtx, func() error { return <-errc }
}

func TestStreamLiveSeedsThenForwards(t *testing.T) {
	src := newFakeLiveSource()
	src.values["k1"] = []byte("seed")
	spec := LiveStreamSpec{channel: "k1", seedKeys: []string{"k1"}}
	sent, cancel, wait := startStream(t, src, spec)
	src.ch <- []byte("live")
	frames := sent()
	cancel()
	if err := wait(); !errors.Is(err, context.Canceled) {
		t.Fatalf("want context.Canceled, got %v", err)
	}
	if len(frames) != 2 || string(frames[0]) != "seed" || string(frames[1]) != "live" {
		t.Fatalf("want [seed live], got %q", frames)
	}
}

func TestStreamLiveSubscribesBeforeSeeding(t *testing.T) {
	src := newFakeLiveSource()
	src.values["k1"] = []byte("seed")
	spec := LiveStreamSpec{channel: "k1", seedKeys: []string{"k1"}}
	sent, cancel, wait := startStream(t, src, spec)
	sent()
	cancel()
	_ = wait()
	if len(src.ops) < 2 || src.ops[0] != "subscribe:k1" || src.ops[1] != "get:k1" {
		t.Fatalf("want subscribe before get, ops=%v", src.ops)
	}
}

func TestStreamLiveSkipsEmptyAndUnusable(t *testing.T) {
	src := newFakeLiveSource()
	src.values["k1"] = []byte("") // empty seed must not be sent
	spec := LiveStreamSpec{
		channel:  "k1",
		seedKeys: []string{"k1", "missing"},
		usable:   func(b []byte) bool { return string(b) != "junk" && len(b) > 0 },
	}
	sent, cancel, wait := startStream(t, src, spec)
	src.ch <- []byte("junk")
	src.ch <- []byte("good")
	frames := sent()
	cancel()
	_ = wait()
	if len(frames) != 1 || string(frames[0]) != "good" {
		t.Fatalf("want [good], got %q", frames)
	}
}

func TestStreamLiveSeedsFromScan(t *testing.T) {
	src := newFakeLiveSource()
	src.scans["pre:*"] = []string{"pre:a", "pre:b"}
	src.values["pre:a"] = []byte("A")
	src.values["pre:b"] = []byte("B")
	spec := LiveStreamSpec{channel: "pre", seedScan: "pre:*"}
	sent, cancel, wait := startStream(t, src, spec)
	frames := sent()
	cancel()
	_ = wait()
	if len(frames) != 2 || string(frames[0]) != "A" || string(frames[1]) != "B" {
		t.Fatalf("want [A B], got %q", frames)
	}
}

func TestStreamLiveClosedChannelReturnsError(t *testing.T) {
	src := newFakeLiveSource()
	spec := LiveStreamSpec{channel: "k1"}
	_, _, wait := startStream(t, src, spec)
	close(src.ch)
	if err := wait(); !errors.Is(err, errLiveSourceClosed) {
		t.Fatalf("want errLiveSourceClosed, got %v", err)
	}
}

// TestStreamLiveReturnsUnavailableWhenHubEvictsSlowSubscriber runs streamLive
// against a real liveHub (which implements liveSource) to prove that a
// subscriber evicted for falling behind surfaces a reconnectable Unavailable
// error to its stream, rather than the generic errLiveSourceClosed used for
// an upstream disconnect.
func TestStreamLiveReturnsUnavailableWhenHubEvictsSlowSubscriber(t *testing.T) {
	src := newHubSource()
	hub := NewLiveHubWithQueueSize(src, 10, 4)

	firstSendStarted := make(chan struct{})
	release := make(chan struct{})
	var once sync.Once

	errc := make(chan error, 1)
	go func() {
		errc <- StreamLive(context.Background(), hub, LiveStreamSpec{channel: "route:1"}, func([]byte) error {
			once.Do(func() { close(firstSendStarted) })
			<-release
			return nil
		})
	}()

	subscribeDeadline := time.Now().Add(time.Second)
	for src.subscriptionCount("route:1") == 0 && time.Now().Before(subscribeDeadline) {
		time.Sleep(time.Millisecond)
	}
	src.publish("route:1", []byte("frame-0")) // triggers the first, blocking send
	<-firstSendStarted                        // consumer is now stuck in send, no longer draining its queue

	for i := 1; i < 6; i++ {
		src.publish("route:1", []byte(fmt.Sprintf("frame-%d", i)))
	}

	deadline := time.Now().Add(time.Second)
	for hub.stats().EvictedSubscribers == 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}

	close(release) // unblock send so streamLive loops back and observes the closed channel

	select {
	case err := <-errc:
		if status.Code(err) != codes.Unavailable {
			t.Fatalf("error = %v, want status code %s", err, codes.Unavailable)
		}
	case <-time.After(time.Second):
		t.Fatal("streamLive did not return after subscriber eviction")
	}
}

// TestStreamLiveIncrementsStreamDisconnectOnEveryTermination proves
// router_stream_disconnects_total advances once per completed stream,
// covering both termination causes exercised elsewhere in this file
// (upstream close and send failure), but not the initial subscribe error
// path (subscribeErrSource below), which never establishes a stream to
// disconnect from.
func TestStreamLiveIncrementsStreamDisconnectOnEveryTermination(t *testing.T) {
	before := parseCounterTotal(t, "router_stream_disconnects_total")

	closedSrc := newFakeLiveSource()
	_, _, waitClosed := startStream(t, closedSrc, LiveStreamSpec{channel: "k1"})
	close(closedSrc.ch)
	_ = waitClosed()

	sendErrSrc := newFakeLiveSource()
	sendErrDone := make(chan error, 1)
	go func() {
		sendErrDone <- StreamLive(context.Background(), sendErrSrc, LiveStreamSpec{channel: "k1"}, func([]byte) error {
			return errors.New("client gone")
		})
	}()
	sendErrSrc.ch <- []byte("live")
	<-sendErrDone

	subscribeErrSrc := &subscribeErrLiveSource{err: errors.New("capacity reached")}
	_ = StreamLive(context.Background(), subscribeErrSrc, LiveStreamSpec{channel: "k1"}, func([]byte) error { return nil })

	after := parseCounterTotal(t, "router_stream_disconnects_total")
	if after != before+2 {
		t.Fatalf("router_stream_disconnects_total = %d, want %d (before %d + 2 established streams; the subscribe-error stream must not count)", after, before+2, before)
	}
}

// subscribeErrLiveSource fails subscribe unconditionally, exercising
// streamLive's earliest return path (before any stream is established).
type subscribeErrLiveSource struct{ err error }

func (s *subscribeErrLiveSource) get(context.Context, string) ([]byte, bool) { return nil, false }
func (s *subscribeErrLiveSource) scanKeys(context.Context, string) []string  { return nil }
func (s *subscribeErrLiveSource) subscribe(context.Context, string) (<-chan []byte, func(), error) {
	return nil, nil, s.err
}

// TestRedisLiveSourceRecordsRedisErrorButNotNil proves get/scanKeys count a
// genuine Redis failure (here: nothing listening on the configured address)
// in router_redis_errors_total, while a plain missing key (redis.Nil) does
// not -- see redisLiveSource.get's doc comment for why that distinction
// matters (an absent key is expected traffic, not a Redis health signal).
func TestRedisLiveSourceRecordsRedisErrorButNotNil(t *testing.T) {
	unreachable := RedisLiveSource{rc: redis.NewClient(&redis.Options{
		Addr:        "127.0.0.1:1", // nothing listens here; every call fails fast
		DialTimeout: 200 * time.Millisecond,
	})}

	before := parseCounterTotal(t, "router_redis_errors_total")
	if _, ok := unreachable.get(context.Background(), "any-key"); ok {
		t.Fatal("get against an unreachable Redis must report ok=false")
	}
	unreachable.scanKeys(context.Background(), "any:*")
	after := parseCounterTotal(t, "router_redis_errors_total")
	if after != before+2 {
		t.Fatalf("router_redis_errors_total = %d, want %d (before %d + get + scanKeys failures)", after, before+2, before)
	}
}

func parseCounterTotal(t *testing.T, name string) int64 {
	t.Helper()
	for _, line := range strings.Split(obs.MetricsText(), "\n") {
		if strings.HasPrefix(line, name+" ") {
			var value int64
			if _, err := fmt.Sscanf(line, name+" %d", &value); err != nil {
				t.Fatalf("parse metric line %q: %v", line, err)
			}
			return value
		}
	}
	return 0
}

func TestStreamLiveSendErrorStopsStream(t *testing.T) {
	src := newFakeLiveSource()
	sendErr := errors.New("client gone")
	errc := make(chan error, 1)
	go func() {
		errc <- StreamLive(context.Background(), src, LiveStreamSpec{channel: "k1"}, func([]byte) error {
			return sendErr
		})
	}()
	src.ch <- []byte("live")
	if err := <-errc; !errors.Is(err, sendErr) {
		t.Fatalf("want send error propagated, got %v", err)
	}
}
