package main

import (
	"sync"
	"testing"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type hubSource struct {
	mu            sync.Mutex
	channels      map[string]chan []byte
	subscriptions map[string]int
	cancellations map[string]int
}

func newHubSource() *hubSource {
	return &hubSource{
		channels:      map[string]chan []byte{},
		subscriptions: map[string]int{},
		cancellations: map[string]int{},
	}
}

func (s *hubSource) get(string) ([]byte, bool) {
	return nil, false
}

func (s *hubSource) scanKeys(string) []string {
	return nil
}

func (s *hubSource) subscribe(channel string) (<-chan []byte, func(), error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.subscriptions[channel]++
	ch := s.channels[channel]
	if ch == nil {
		ch = make(chan []byte, 16)
		s.channels[channel] = ch
	}
	return ch, func() {
		s.mu.Lock()
		defer s.mu.Unlock()
		s.cancellations[channel]++
	}, nil
}

func (s *hubSource) publish(channel string, payload []byte) {
	s.mu.Lock()
	ch := s.channels[channel]
	s.mu.Unlock()
	ch <- payload
}

func (s *hubSource) close(channel string) {
	s.mu.Lock()
	ch := s.channels[channel]
	s.mu.Unlock()
	close(ch)
}

func (s *hubSource) subscriptionCount(channel string) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.subscriptions[channel]
}

func (s *hubSource) cancellationCount(channel string) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.cancellations[channel]
}

func TestLiveHubSharesOneUpstreamSubscription(t *testing.T) {
	src := newHubSource()
	hub := newLiveHub(src, 10)

	first, closeFirst, err := hub.subscribe("route:1")
	if err != nil {
		t.Fatal(err)
	}
	second, closeSecond, err := hub.subscribe("route:1")
	if err != nil {
		t.Fatal(err)
	}

	src.publish("route:1", []byte("eta"))
	if got := string(<-first); got != "eta" {
		t.Fatalf("first frame = %q", got)
	}
	if got := string(<-second); got != "eta" {
		t.Fatalf("second frame = %q", got)
	}
	if got := src.subscriptionCount("route:1"); got != 1 {
		t.Fatalf("upstream subscriptions = %d, want 1", got)
	}

	closeFirst()
	closeSecond()
}

func TestLiveHubReplacesStaleFrameForSlowSubscriber(t *testing.T) {
	src := newHubSource()
	hub := newLiveHub(src, 10)

	stream, closeStream, err := hub.subscribe("route:1")
	if err != nil {
		t.Fatal(err)
	}
	defer closeStream()

	src.publish("route:1", []byte("stale"))
	src.publish("route:1", []byte("latest"))
	deadline := time.Now().Add(time.Second)
	for hub.stats().DroppedFrames == 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if got := string(<-stream); got != "latest" {
		t.Fatalf("frame = %q, want latest", got)
	}
}

func TestLiveHubClosesUpstreamAfterLastSubscriber(t *testing.T) {
	src := newHubSource()
	hub := newLiveHub(src, 10)

	_, closeStream, err := hub.subscribe("route:1")
	if err != nil {
		t.Fatal(err)
	}
	closeStream()
	if got := src.cancellationCount("route:1"); got != 1 {
		t.Fatalf("upstream cancellations = %d, want 1", got)
	}
}

func TestLiveHubClosesUpstreamAfterSourceDisconnect(t *testing.T) {
	src := newHubSource()
	hub := newLiveHub(src, 10)

	stream, closeStream, err := hub.subscribe("route:1")
	if err != nil {
		t.Fatal(err)
	}
	defer closeStream()

	src.close("route:1")
	if _, ok := <-stream; ok {
		t.Fatal("stream remained open after upstream disconnect")
	}
	deadline := time.Now().Add(time.Second)
	for src.cancellationCount("route:1") == 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if got := src.cancellationCount("route:1"); got != 1 {
		t.Fatalf("upstream cancellations = %d, want 1", got)
	}
}

func TestLiveHubRejectsStreamAboveLimit(t *testing.T) {
	src := newHubSource()
	hub := newLiveHub(src, 1)

	_, closeStream, err := hub.subscribe("route:1")
	if err != nil {
		t.Fatal(err)
	}
	defer closeStream()

	_, _, err = hub.subscribe("route:2")
	if got := status.Code(err); got != codes.ResourceExhausted {
		t.Fatalf("status code = %s, want %s", got, codes.ResourceExhausted)
	}
	if got := src.subscriptionCount("route:2"); got != 0 {
		t.Fatalf("upstream subscriptions = %d, want 0", got)
	}
}
