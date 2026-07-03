package main

import "sync"

// busStaticMapCache holds each city prefix's station map in memory so the 30s
// bus ETA cron does not re-query PostgreSQL every tick. It is invalidated after a
// daily static rebuild (invalidateBusStaticMap).
var busStaticMapCache sync.Map

// cachedBusStaticMap returns the cached station map for a city prefix, or
// (nil, false) on a miss (including a value of an unexpected type).
func cachedBusStaticMap(prefix string) ([]busStationmap, bool) {
	v, ok := busStaticMapCache.Load(prefix)
	if !ok {
		return nil, false
	}
	list, ok := v.([]busStationmap)
	if !ok {
		return nil, false
	}
	return list, true
}

// storeBusStaticMap caches a city prefix's station map for reuse by later ETA ticks.
func storeBusStaticMap(prefix string, list []busStationmap) {
	busStaticMapCache.Store(prefix, list)
}

// invalidateBusStaticMap clears every cached station map, called after a daily
// static rebuild so the ETA path reloads fresh data on its next tick.
func invalidateBusStaticMap() {
	busStaticMapCache.Range(func(key, _ any) bool {
		busStaticMapCache.Delete(key)
		return true
	})
}
