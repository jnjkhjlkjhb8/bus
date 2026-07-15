package main

import (
	"sync"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// defaultSubscriberQueueSize bounds how many undelivered frames a single
// subscriber's downstream channel may hold before it is evicted as too slow.
const defaultSubscriberQueueSize = 32

// errLiveSubscriberOverflow is returned to a subscriber whose downstream
// queue filled up. The subscriber is evicted rather than having a distinct
// delta frame silently dropped or replaced; the client is expected to
// reconnect.
var errLiveSubscriberOverflow = status.Error(codes.Unavailable, "live stream subscriber fell behind, reconnect")

type liveHubStats struct {
	ActiveStreams      int64
	ActiveChannels     int64
	EvictedSubscribers int64
}

type liveHubEntry struct {
	upstreamClose func()
	subscribers   map[uint64]chan []byte
}

type liveHub struct {
	source              liveSource
	maxStreams          int64
	subscriberQueueSize int

	mu                 sync.Mutex
	entries            map[string]*liveHubEntry
	nextSubscriber     uint64
	activeStreams      int64
	evictedSubscribers int64
	// closeReasons records why a specific downstream channel was closed, for
	// channels closed by evictSlowSubscriber. Absence means the generic
	// upstream-disconnect case: streamLive falls back to errLiveSourceClosed.
	closeReasons map[<-chan []byte]error
}

func newLiveHub(source liveSource, maxStreams int) *liveHub {
	return newLiveHubWithQueueSize(source, maxStreams, defaultSubscriberQueueSize)
}

// newLiveHubWithQueueSize is newLiveHub with an explicit per-subscriber
// queue bound; queueSize <= 0 falls back to defaultSubscriberQueueSize.
func newLiveHubWithQueueSize(source liveSource, maxStreams, queueSize int) *liveHub {
	if queueSize <= 0 {
		queueSize = defaultSubscriberQueueSize
	}
	return &liveHub{
		source:              source,
		maxStreams:          int64(maxStreams),
		subscriberQueueSize: queueSize,
		entries:             map[string]*liveHubEntry{},
		closeReasons:        map[<-chan []byte]error{},
	}
}

func (h *liveHub) get(key string) ([]byte, bool) {
	return h.source.get(key)
}

func (h *liveHub) scanKeys(pattern string) []string {
	return h.source.scanKeys(pattern)
}

func (h *liveHub) subscribe(channel string) (<-chan []byte, func(), error) {
	h.mu.Lock()
	if h.maxStreams > 0 && h.activeStreams >= h.maxStreams {
		h.mu.Unlock()
		return nil, nil, status.Error(codes.ResourceExhausted, "live stream capacity reached")
	}

	entry := h.entries[channel]
	if entry == nil {
		upstream, upstreamClose, err := h.source.subscribe(channel)
		if err != nil {
			h.mu.Unlock()
			return nil, nil, err
		}
		entry = &liveHubEntry{
			upstreamClose: upstreamClose,
			subscribers:   map[uint64]chan []byte{},
		}
		h.entries[channel] = entry
		go h.forward(channel, entry, upstream)
	}

	h.nextSubscriber++
	id := h.nextSubscriber
	downstream := make(chan []byte, h.subscriberQueueSize)
	entry.subscribers[id] = downstream
	h.activeStreams++
	h.mu.Unlock()

	var once sync.Once
	closeSubscriber := func() {
		once.Do(func() {
			h.unsubscribe(channel, entry, id, downstream)
		})
	}
	return downstream, closeSubscriber, nil
}

// unsubscribe removes id's subscription. downstream is the channel handed
// back by subscribe, passed in directly (rather than re-read from
// entry.subscribers) so cleanup still finds it after eviction has already
// removed the subscribers[id] entry.
func (h *liveHub) unsubscribe(channel string, entry *liveHubEntry, id uint64, downstream chan []byte) {
	h.mu.Lock()
	if h.entries[channel] != entry {
		// The entry is already gone — e.g. forward's eviction path removed
		// the last subscriber and closeEntryIfEmptyLocked dropped the entry
		// before this caller's own cleanup ran. downstream may still hold a
		// closeReasons entry from evictSlowSubscriber; clear it so it does
		// not leak for the process lifetime.
		delete(h.closeReasons, downstream)
		h.mu.Unlock()
		return
	}
	current, ok := entry.subscribers[id]
	if !ok {
		// Already evicted by evictSlowSubscriber: the subscribers[id] entry
		// and channel are gone, but closeReasons may still hold this
		// channel's eviction cause if the caller's handler exited (e.g. via
		// ctx.Done()) without reading it through subscriptionCloseCause.
		// Clear it here too, or it leaks for the process lifetime.
		delete(h.closeReasons, downstream)
		h.mu.Unlock()
		return
	}
	delete(entry.subscribers, id)
	delete(h.closeReasons, current)
	close(current)
	h.activeStreams--
	upstreamClose := h.closeEntryIfEmptyLocked(channel, entry)
	h.mu.Unlock()

	if upstreamClose != nil {
		upstreamClose()
	}
}

// evictSlowSubscriber removes a subscriber whose downstream queue is full
// and closes its channel with errLiveSubscriberOverflow, so the client sees
// a reconnectable error instead of having a distinct delta frame silently
// dropped or replaced. Callers must hold h.mu.
func (h *liveHub) evictSlowSubscriber(entry *liveHubEntry, id uint64, downstream chan []byte) {
	delete(entry.subscribers, id)
	h.activeStreams--
	h.evictedSubscribers++
	h.closeReasons[downstream] = errLiveSubscriberOverflow
	close(downstream)
}

// closeEntryIfEmptyLocked removes channel's entry once its subscriber set is
// empty and returns the upstream close func to invoke after unlocking (nil
// if the entry is still in use or already gone). Callers must hold h.mu.
func (h *liveHub) closeEntryIfEmptyLocked(channel string, entry *liveHubEntry) func() {
	if h.entries[channel] != entry || len(entry.subscribers) != 0 {
		return nil
	}
	delete(h.entries, channel)
	return entry.upstreamClose
}

func (h *liveHub) forward(channel string, entry *liveHubEntry, upstream <-chan []byte) {
	for payload := range upstream {
		h.mu.Lock()
		if h.entries[channel] != entry {
			h.mu.Unlock()
			return
		}
		for id, downstream := range entry.subscribers {
			select {
			case downstream <- payload:
			default:
				// The subscriber's bounded queue is full: it is falling
				// behind. Evict it rather than dropping or replacing this
				// frame, so no distinct delta is silently lost.
				h.evictSlowSubscriber(entry, id, downstream)
			}
		}
		upstreamClose := h.closeEntryIfEmptyLocked(channel, entry)
		h.mu.Unlock()
		if upstreamClose != nil {
			upstreamClose()
		}
	}

	var upstreamClose func()
	h.mu.Lock()
	if h.entries[channel] == entry {
		delete(h.entries, channel)
		upstreamClose = entry.upstreamClose
		for id, downstream := range entry.subscribers {
			delete(entry.subscribers, id)
			delete(h.closeReasons, downstream)
			close(downstream)
			h.activeStreams--
		}
	}
	h.mu.Unlock()

	if upstreamClose != nil {
		upstreamClose()
	}
}

// subscriptionCloseCause reports why ch was closed when the cause is a
// specific, reconnectable per-subscriber event (overflow eviction) rather
// than a generic upstream disconnect. It satisfies liveSourceCloseCause.
func (h *liveHub) subscriptionCloseCause(ch <-chan []byte) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	err := h.closeReasons[ch]
	delete(h.closeReasons, ch)
	return err
}

func (h *liveHub) stats() liveHubStats {
	h.mu.Lock()
	defer h.mu.Unlock()
	return liveHubStats{
		ActiveStreams:      h.activeStreams,
		ActiveChannels:     int64(len(h.entries)),
		EvictedSubscribers: h.evictedSubscribers,
	}
}
