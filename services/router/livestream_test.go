package main

import (
	"context"
	"errors"
	"testing"
	"time"
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

func (f *fakeLiveSource) get(key string) ([]byte, bool) {
	f.ops = append(f.ops, "get:"+key)
	v, ok := f.values[key]
	return v, ok
}

func (f *fakeLiveSource) scanKeys(pattern string) []string {
	f.ops = append(f.ops, "scan:"+pattern)
	return f.scans[pattern]
}

func (f *fakeLiveSource) subscribe(channel string) (<-chan []byte, func()) {
	f.ops = append(f.ops, "subscribe:"+channel)
	return f.ch, func() { f.ops = append(f.ops, "close:"+channel) }
}

// run streamLive in a goroutine, collecting sent frames; returns a cancel
// func and a way to wait for the final error.
func startStream(t *testing.T, src *fakeLiveSource, spec liveStreamSpec) (sent func() [][]byte, cancel func(), wait func() error) {
	t.Helper()
	ctx, cancelCtx := context.WithCancel(context.Background())
	var frames [][]byte
	got := make(chan []byte, 16)
	errc := make(chan error, 1)
	go func() {
		errc <- streamLive(ctx, src, spec, func(b []byte) error {
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
	spec := liveStreamSpec{channel: "k1", seedKeys: []string{"k1"}}
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
	spec := liveStreamSpec{channel: "k1", seedKeys: []string{"k1"}}
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
	spec := liveStreamSpec{
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
	spec := liveStreamSpec{channel: "pre", seedScan: "pre:*"}
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
	spec := liveStreamSpec{channel: "k1"}
	_, _, wait := startStream(t, src, spec)
	close(src.ch)
	if err := wait(); !errors.Is(err, errLiveSourceClosed) {
		t.Fatalf("want errLiveSourceClosed, got %v", err)
	}
}

func TestStreamLiveSendErrorStopsStream(t *testing.T) {
	src := newFakeLiveSource()
	sendErr := errors.New("client gone")
	errc := make(chan error, 1)
	go func() {
		errc <- streamLive(context.Background(), src, liveStreamSpec{channel: "k1"}, func([]byte) error {
			return sendErr
		})
	}()
	src.ch <- []byte("live")
	if err := <-errc; !errors.Is(err, sendErr) {
		t.Fatalf("want send error propagated, got %v", err)
	}
}
