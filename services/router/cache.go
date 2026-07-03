package main

import (
	"sync"
	"time"
)

type ttlEntry struct {
	data      []byte
	expiresAt time.Time
}

type ttlCache struct {
	m sync.Map
}

func newTTLCache() *ttlCache {
	return &ttlCache{}
}

func (c *ttlCache) get(key string) ([]byte, bool) {
	v, ok := c.m.Load(key)
	if !ok {
		return nil, false
	}
	e, ok := v.(ttlEntry)
	if !ok {
		return nil, false
	}
	if time.Now().After(e.expiresAt) {
		c.m.Delete(key)
		return nil, false
	}
	return e.data, true
}

func (c *ttlCache) set(key string, data []byte, ttl time.Duration) {
	c.m.Store(key, ttlEntry{data: data, expiresAt: time.Now().Add(ttl)})
}
