package main

import (
	"sync"
	"time"
)

// busStaticMapCache holds each city prefix's station map in memory so the 30s
// bus ETA cron does not re-query PostgreSQL every tick. A committed city rebuild
// invalidates its prefix locally and advances the durable Redis generation.
var busStaticMapCache sync.Map

const busStaticMapCacheTTL = 5 * time.Minute

type busStaticMapCacheEntry struct {
	stops      []busStationmap
	generation string
	loadedAt   time.Time
}

func cachedBusStaticMapFrom(cache *sync.Map, prefix, generation string, now time.Time) ([]busStationmap, bool) {
	v, ok := cache.Load(prefix)
	if !ok {
		return nil, false
	}
	entry, ok := v.(busStaticMapCacheEntry)
	if !ok || now.Sub(entry.loadedAt) >= busStaticMapCacheTTL {
		cache.Delete(prefix)
		return nil, false
	}
	// A non-empty durable generation is authoritative. During a Redis outage
	// generation is empty; the bounded TTL is the fallback that prevents an
	// offline worker from retaining yesterday's map indefinitely.
	if generation != "" && entry.generation != generation {
		cache.Delete(prefix)
		return nil, false
	}
	return entry.stops, true
}

// storeBusStaticMap caches a city prefix's station map for reuse by later ETA ticks.
func storeBusStaticMap(prefix string, list []busStationmap) {
	storeBusStaticMapIn(&busStaticMapCache, prefix, list, "", time.Now())
}

func storeBusStaticMapIn(cache *sync.Map, prefix string, list []busStationmap, generation string, now time.Time) {
	cache.Store(prefix, busStaticMapCacheEntry{stops: list, generation: generation, loadedAt: now})
}

// invalidateBusStaticMap clears all maps for tests/process teardown. Production
// commits use invalidateBusStaticMapCity to avoid evicting unrelated cities.
func invalidateBusStaticMap() {
	busStaticMapCache.Range(func(key, _ any) bool {
		busStaticMapCache.Delete(key)
		return true
	})
}

func invalidateBusStaticMapCity(prefix string) {
	busStaticMapCache.Delete(prefix)
}
