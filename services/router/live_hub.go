package main

import (
	"sync"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type liveHubStats struct {
	ActiveStreams  int64
	ActiveChannels int64
	DroppedFrames  int64
}

type liveHubEntry struct {
	upstreamClose func()
	subscribers   map[uint64]chan []byte
}

type liveHub struct {
	source     liveSource
	maxStreams int64

	mu             sync.Mutex
	entries        map[string]*liveHubEntry
	nextSubscriber uint64
	activeStreams  int64
	droppedFrames  int64
}

func newLiveHub(source liveSource, maxStreams int) *liveHub {
	return &liveHub{
		source:     source,
		maxStreams: int64(maxStreams),
		entries:    map[string]*liveHubEntry{},
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
	downstream := make(chan []byte, 1)
	entry.subscribers[id] = downstream
	h.activeStreams++
	h.mu.Unlock()

	var once sync.Once
	closeSubscriber := func() {
		once.Do(func() {
			h.unsubscribe(channel, entry, id)
		})
	}
	return downstream, closeSubscriber, nil
}

func (h *liveHub) unsubscribe(channel string, entry *liveHubEntry, id uint64) {
	var upstreamClose func()

	h.mu.Lock()
	if h.entries[channel] != entry {
		h.mu.Unlock()
		return
	}
	downstream, ok := entry.subscribers[id]
	if !ok {
		h.mu.Unlock()
		return
	}
	delete(entry.subscribers, id)
	close(downstream)
	h.activeStreams--
	if len(entry.subscribers) == 0 {
		delete(h.entries, channel)
		upstreamClose = entry.upstreamClose
	}
	h.mu.Unlock()

	if upstreamClose != nil {
		upstreamClose()
	}
}

func (h *liveHub) forward(channel string, entry *liveHubEntry, upstream <-chan []byte) {
	for payload := range upstream {
		h.mu.Lock()
		if h.entries[channel] != entry {
			h.mu.Unlock()
			return
		}
		for _, downstream := range entry.subscribers {
			select {
			case downstream <- payload:
			default:
				select {
				case <-downstream:
				default:
				}
				select {
				case downstream <- payload:
					h.droppedFrames++
				default:
				}
			}
		}
		h.mu.Unlock()
	}

	var upstreamClose func()
	h.mu.Lock()
	if h.entries[channel] == entry {
		delete(h.entries, channel)
		upstreamClose = entry.upstreamClose
		for id, downstream := range entry.subscribers {
			delete(entry.subscribers, id)
			close(downstream)
			h.activeStreams--
		}
	}
	h.mu.Unlock()

	if upstreamClose != nil {
		upstreamClose()
	}
}

func (h *liveHub) stats() liveHubStats {
	h.mu.Lock()
	defer h.mu.Unlock()
	return liveHubStats{
		ActiveStreams:  h.activeStreams,
		ActiveChannels: int64(len(h.entries)),
		DroppedFrames:  h.droppedFrames,
	}
}
