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

// stopOffsetCache holds each subroute's stop offsets, keyed by sub_route_uid.
//
// batchStopOffsets runs busPatternSQL, whose known_stop CTE unnests every
// raw_tdx.bus_stopofroute row before the uid filter is applied — so the cost is
// the same whether one subroute is asked for or a thousand. On the 30s tick
// across twenty cities that was ~2,400 executions an hour against the 2 GB Azure
// server, and it is what the "batchStopOffsets rows error: context deadline
// exceeded" line in the logs was.
//
// bus_segment_time, the only input that moves, is rewritten once a night by the
// 04:00 segmentTimes job. An hour's TTL is well inside that cadence and needs no
// invalidation hook: the worst case is one hour of yesterday's offsets, on a
// figure that is a seven-day median.
var stopOffsetCache sync.Map

const stopOffsetCacheTTL = time.Hour

type stopOffset struct {
	direction int32
	stopUID   string
	secs      int
}

type stopOffsetCacheEntry struct {
	offsets  []stopOffset
	loadedAt time.Time
}

// cachedStopOffsets fills out from the cache and returns the uids that missed.
func cachedStopOffsets(cache *sync.Map, uids []string, now time.Time, out map[stopOffsetKey]int) []string {
	var missing []string
	for _, uid := range uids {
		v, ok := cache.Load(uid)
		entry, typed := v.(stopOffsetCacheEntry)
		if !ok || !typed || now.Sub(entry.loadedAt) >= stopOffsetCacheTTL {
			cache.Delete(uid)
			missing = append(missing, uid)
			continue
		}
		for _, o := range entry.offsets {
			out[stopOffsetKey{subRouteUID: uid, direction: o.direction, stopUID: o.stopUID}] = o.secs
		}
	}
	return missing
}

func storeStopOffsets(cache *sync.Map, fetched map[string][]stopOffset, now time.Time) {
	for uid, offsets := range fetched {
		cache.Store(uid, stopOffsetCacheEntry{offsets: offsets, loadedAt: now})
	}
}
