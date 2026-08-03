package main

import (
	"sync"
	"testing"
	"time"
)

func TestBusStaticCacheObservesGenerationAcrossProcessInstances(t *testing.T) {
	// Two independent maps model loader/functions containers. The loader's local
	// invalidation cannot touch the reader, so only the shared durable generation
	// causes the reader to reject generation 1 after generation 2 commits.
	var loaderCache sync.Map
	var readerCache sync.Map
	now := time.Now()
	storeBusStaticMapIn(&loaderCache, "TPE", []busStationmap{{StopUID: "loader"}}, "1", now)
	storeBusStaticMapIn(&readerCache, "TPE", []busStationmap{{StopUID: "old"}}, "1", now)
	loaderCache.Delete("TPE")

	if stops, ok := cachedBusStaticMapFrom(&readerCache, "TPE", "1", now.Add(time.Minute)); !ok || stops[0].StopUID != "old" {
		t.Fatalf("generation 1 cache = %v/%v, want old hit", stops, ok)
	}
	if _, ok := cachedBusStaticMapFrom(&readerCache, "TPE", "2", now.Add(time.Minute)); ok {
		t.Fatal("reader reused generation 1 after durable generation advanced to 2")
	}
}

func TestBusStaticCacheRedisOutageFallsBackOnlyUntilTTL(t *testing.T) {
	var cache sync.Map
	now := time.Now()
	storeBusStaticMapIn(&cache, "TPE", []busStationmap{{StopUID: "old"}}, "7", now)
	if _, ok := cachedBusStaticMapFrom(&cache, "TPE", "", now.Add(busStaticMapCacheTTL-time.Second)); !ok {
		t.Fatal("Redis outage should allow the bounded local fallback before TTL")
	}
	if _, ok := cachedBusStaticMapFrom(&cache, "TPE", "", now.Add(busStaticMapCacheTTL)); ok {
		t.Fatal("Redis outage allowed stale cache at/after TTL")
	}
}

// The subroutes busPatternSQL returns nothing for are the majority, and they are
// the ones worth caching: without a negative entry every incomplete direction
// re-runs the statement on every tick, which is most of the cost the cache
// exists to avoid.
func TestStopOffsetCacheRemembersMisses(t *testing.T) {
	var cache sync.Map
	now := time.Now()

	out := map[stopOffsetKey]int{}
	missing := cachedStopOffsets(&cache, []string{"A", "B"}, now, out)
	if len(missing) != 2 {
		t.Fatalf("cold missing = %v, want both", missing)
	}

	// A returned one stop; B returned nothing but was still queried.
	storeStopOffsets(&cache, map[string][]stopOffset{
		"A": {{direction: 0, stopUID: "S1", secs: 42}},
		"B": nil,
	}, now)

	out = map[stopOffsetKey]int{}
	if missing := cachedStopOffsets(&cache, []string{"A", "B"}, now, out); missing != nil {
		t.Errorf("warm missing = %v, want none: the empty result must be cached too", missing)
	}
	if got := out[stopOffsetKey{subRouteUID: "A", direction: 0, stopUID: "S1"}]; got != 42 {
		t.Errorf("A/S1 = %d, want 42", got)
	}
	if len(out) != 1 {
		t.Errorf("out = %v, want only A's stop", out)
	}

	out = map[stopOffsetKey]int{}
	if missing := cachedStopOffsets(&cache, []string{"A", "B"}, now.Add(stopOffsetCacheTTL), out); len(missing) != 2 {
		t.Errorf("expired missing = %v, want both re-queried at TTL", missing)
	}
}
