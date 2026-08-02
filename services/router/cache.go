package main

import (
	"sync"
	"sync/atomic"
	"time"
)

type ttlEntry struct {
	data      []byte
	expiresAt time.Time
}

type TTLCache struct {
	m sync.Map

	// maxEntries bounds the live key count; 0 leaves the cache unbounded.
	// Callers whose keys come from a fixed keyspace (a route uid, a station
	// uid) can stay unbounded because the map cannot outgrow the data set.
	// Callers keyed by user input cannot, and must pass a cap.
	maxEntries int
	// entries tracks the live key count so set can tell when the cap is
	// reached. It is advisory: get/set race against each other, so a few
	// keys either way only shifts when the flush happens.
	entries atomic.Int64
}

func NewTTLCache() *TTLCache {
	return &TTLCache{}
}

// NewBoundedTTLCache returns a cache that drops everything once it holds
// more than maxEntries keys.
//
// whole-cache flush at the cap, not LRU eviction. Tracking recency needs
// a lock and a list on a path that is otherwise two atomic map ops; for a
// cache whose entries expire on their own anyway, an occasional cold start
// is the cheaper trade. Switch to LRU if the flush ever lands often enough
// to show up in the hit rate.
func NewBoundedTTLCache(maxEntries int) *TTLCache {
	return &TTLCache{maxEntries: maxEntries}
}

func (c *TTLCache) get(key string) ([]byte, bool) {
	v, ok := c.m.Load(key)
	if !ok {
		return nil, false
	}
	e, ok := v.(ttlEntry)
	if !ok {
		return nil, false
	}
	if time.Now().After(e.expiresAt) {
		c.delete(key)
		return nil, false
	}
	return e.data, true
}

func (c *TTLCache) set(key string, data []byte, ttl time.Duration) {
	_, loaded := c.m.Swap(key, ttlEntry{data: data, expiresAt: time.Now().Add(ttl)})
	if loaded || c.maxEntries <= 0 {
		return
	}
	if c.entries.Add(1) > int64(c.maxEntries) {
		c.flush()
	}
}

func (c *TTLCache) delete(key string) {
	if _, loaded := c.m.LoadAndDelete(key); loaded && c.maxEntries > 0 {
		c.entries.Add(-1)
	}
}

func (c *TTLCache) flush() {
	c.m.Range(func(k, _ any) bool {
		c.m.Delete(k)
		return true
	})
	c.entries.Store(0)
}
