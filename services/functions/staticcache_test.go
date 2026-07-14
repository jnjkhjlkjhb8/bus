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
