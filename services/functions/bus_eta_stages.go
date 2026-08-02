package main

import (
	"slices"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
)

// This file holds the pure stages of processBusEtaCity (bus_eta.go): each is a
// deterministic function over plain values with no Redis/DB/network handle, lifted
// out of the live job so it can be exercised in isolation. The job still calls
// them in the same order at the same points; extraction changes structure, not
// behavior. I/O-bound steps (fetch/decode, weather load, batched DB lookups, the
// prediction/fill and proto-emit loop, Redis writes) stay in bus_eta.go where the
// collaborator handles live.

// parseSrcUpdateTime reads a TDX SrcUpdateTime. Usually RFC3339 with a +08:00
// offset; some feeds drop the zone, which we read as Taipei local. Empty or
// unparseable values report false.
func parseSrcUpdateTime(s string) (time.Time, bool) {
	if s == "" {
		return time.Time{}, false
	}
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t, true
	}
	for _, layout := range []string{"2006-01-02T15:04:05", "2006-01-02 15:04:05"} {
		if t, err := time.ParseInLocation(layout, s, taipei); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

// adjustedEstimate is the live seconds-to-arrival for one ETA entry, net of the
// age of its source update: TDX reports EstimatedTime as of SrcUpdateTime, so a
// stale snapshot is aged forward to now. When SrcUpdateTime does not parse the raw
// EstimatedTime is used unchanged. A snapshot older than its own estimate (or a
// negative EstimatedTime from TDX) clamps to 0 — "arriving now"; every consumer
// gates on est > 0, so 0 and a negative already behaved alike, but the history
// row stored the negative. Shared by the delay-propagation observation pass and
// the emit loop so both age the estimate identically.
func adjustedEstimate(eta rawBusEsimated, now time.Time) int32 {
	est := eta.EstimatedTime
	if srcT, ok := parseSrcUpdateTime(eta.SrcUpdateTime); ok {
		est -= int32(now.Sub(srcT).Seconds())
	}
	return max(est, 0)
}

// busEtaNoReading is the StopStatus published for a stop with no usable TDX
// entry at all. Outside TDX's own 0-4 range, so the app falls through to its
// unknown branch and renders '–' rather than a service state it was never told.
const busEtaNoReading uint8 = 67

// How long past its own predicted arrival instant a StopStatus 0 entry still
// counts as 進站中. One ETA cron period plus a minute of slack for TDX's own
// publish lag.
const busEtaArrivingGrace = 90 * time.Second

// arrivingExpired reports whether a StopStatus 0 entry has sat past its
// arrival instant long enough that "進站中" is no longer a claim we can make.
// TDX keeps republishing the last entry after a vehicle stops reporting, and
// adjustedEstimate clamps its elapsed estimate to 0 — the same shape as a bus
// genuinely at the kerb — so without this every stop on a route whose feed
// went quiet pins at 進站中 for the rest of the day. Entries with no parseable
// SrcUpdateTime cannot be aged and are left alone.
func arrivingExpired(eta rawBusEsimated, now time.Time) bool {
	srcT, ok := parseSrcUpdateTime(eta.SrcUpdateTime)
	if !ok {
		return false
	}
	arrival := srcT.Add(time.Duration(eta.EstimatedTime) * time.Second)
	return now.Sub(arrival) > busEtaArrivingGrace
}

// busEtaDirectionUnknown is TDX's "direction not applicable" marker on an
// EstimatedTimeOfArrival entry. Tainan sends it on every schedule-only (StopStatus
// 1) entry, its SubRouteUID already naming the travel direction.
const busEtaDirectionUnknown uint8 = 255

// buildBusEtaMap collapses a city's raw TDX ETA array into one entry per
// (canonical subroute, derived direction, stop). TDX emits one entry per (stop x
// subroute x direction); canonicalizing the subroute/direction (ADR-0006) keeps
// multi-route stops from overwriting each other, and pickBusEstimate resolves
// collisions (prefer a bus en route, then the soonest). Canonicalization applies
// to the feed only — mp arrives canonical from the loader, so its UIDs are used
// as read.
//
// Two feeds identify arrivals more loosely than the key needs, and each is
// widened against mp — the same stop map the emit loop joins against. Neither
// fan-out can invent an arrival: etaKey still carries the StopUID, so a subroute
// only picks up an entry if it actually serves that stop.
//
//   - Taipei and NewTaipei omit SubRouteUID entirely and identify arrivals only by
//     RouteUID. Such an entry fans out to every subroute of its route.
//   - Tainan sends Direction 255 on schedule-only entries. Such an entry fans out
//     to every direction mp records for its subroute.
//
// Without the widening those stops stay unmatched, reported as StopStatus 67 with
// no estimate even though TDX supplied one.
func buildBusEtaMap(city string, eat []rawBusEsimated, mp []busStationmap) map[etaKey]rawBusEsimated {
	subsByRoute := make(map[string][]string)
	dirsBySub := make(map[string][]uint8)
	seenSub := make(map[string]bool)
	for _, b := range mp {
		if !slices.Contains(dirsBySub[b.SubRouteUID], b.Direction) {
			dirsBySub[b.SubRouteUID] = append(dirsBySub[b.SubRouteUID], b.Direction)
		}
		if b.RouteUID == "" || seenSub[b.SubRouteUID] {
			continue
		}
		seenSub[b.SubRouteUID] = true
		subsByRoute[b.RouteUID] = append(subsByRoute[b.RouteUID], b.SubRouteUID)
	}
	etamap := make(map[etaKey]rawBusEsimated)
	put := func(k etaKey, e rawBusEsimated) {
		if prev, seen := etamap[k]; seen {
			etamap[k] = pickBusEstimate(prev, e)
		} else {
			etamap[k] = e
		}
	}
	for _, e := range eat {
		uid, dir := shared.CanonicalSubroute(city, e.SubRouteUID, e.Direction)
		subs := []string{uid}
		if e.SubRouteUID == "" {
			subs = subsByRoute[e.RouteUID]
		}
		for _, sub := range subs {
			dirs := []uint8{dir}
			if dir == busEtaDirectionUnknown {
				dirs = dirsBySub[sub]
			}
			for _, d := range dirs {
				put(etaKey{sub, d, e.StopUID}, e)
			}
		}
	}
	return etamap
}

// parseGPSTimeUnix converts a TDX GPSTime string to epoch seconds. TDX usually
// sends RFC3339 with a +08:00 offset; some feeds drop the zone, which we read as
// Taipei local. Unparseable or empty values yield 0 (the client shows "無定位").
func parseGPSTimeUnix(s string) int64 {
	if s == "" {
		return 0
	}
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t.Unix()
	}
	for _, layout := range []string{"2006-01-02T15:04:05", "2006-01-02 15:04:05"} {
		if t, err := time.ParseInLocation(layout, s, taipei); err == nil {
			return t.Unix()
		}
	}
	return 0
}

// buildTotalStops counts the stops per canonical subroute from the static map,
// giving each stop its route length (a model feature, and stored on history
// rows).
func buildTotalStops(mp []busStationmap) map[string]int {
	totalStops := make(map[string]int)
	for _, b := range mp {
		totalStops[b.SubRouteUID]++
	}
	return totalStops
}

// collectFillKeys selects the route/directions whose baseline (schedule +
// running time) must be looked up: stops flagged status 1 with no TDX NextBusTime (the
// gap prediction fills), plus stops with a live bus en route (status 0) whose
// baseline the delay-propagation pass needs at upstream stops. It returns the
// route/direction keys (with duplicates, as the caller dedups) and the set of
// canonical UIDs for the stop-offset batch.
func collectFillKeys(mp []busStationmap, etamap map[etaKey]rawBusEsimated) ([]routeDirKey, map[string]bool) {
	var fillKeys []routeDirKey
	fillUIDs := make(map[string]bool)
	for _, b := range mp {
		uid, dir := b.SubRouteUID, b.Direction
		etaEnt, ok := etamap[etaKey{uid, dir, b.StopUID}]
		if !ok {
			continue
		}
		if etaEnt.StopStatus == 1 && etaEnt.NextBusTime == "" {
			fillKeys = append(fillKeys, routeDirKey{uid, int32(dir)})
			fillUIDs[uid] = true
		}
		// Delay propagation needs the baseline (schedule + running time) at upstream
		// stops where a live bus is en route, so include those routes' departures
		// and stop offsets in the batched lookups too.
		if etaEnt.StopStatus == 0 {
			fillKeys = append(fillKeys, routeDirKey{uid, int32(dir)})
			fillUIDs[uid] = true
		}
	}
	return fillKeys, fillUIDs
}

// buildUpstreamObs runs the delay-propagation observation pass: for every stop
// with a live bus en route (StopStatus 0) and a usable baseline, it records how
// far that vehicle runs behind (or ahead of) the schedule+running-time
// baseline, keyed per route/direction. A downstream stop TDX later left blank
// inherits the closest upstream vehicle's decayed delay before falling through to
// the model. baselineFor is injected (it closes over the batched departure and
// stop-offset lookups) so this pass stays a pure function over its inputs.
func buildUpstreamObs(
	mp []busStationmap,
	etamap map[etaKey]rawBusEsimated,
	now time.Time,
	baselineFor func(b busStationmap, uid string, dir int32) time.Time,
) map[routeDirKey][]upstreamObs {
	upstreamByRoute := make(map[routeDirKey][]upstreamObs)
	for _, b := range mp {
		uid, cdir := b.SubRouteUID, b.Direction
		eta, ok := etamap[etaKey{uid, cdir, b.StopUID}]
		if !ok || eta.StopStatus != 0 {
			continue
		}
		dir := int32(cdir)
		est := adjustedEstimate(eta, now)
		baseline := baselineFor(b, uid, dir)
		if baseline.IsZero() {
			continue
		}
		observedArrival := now.Add(time.Duration(est) * time.Second)
		rk := routeDirKey{uid, dir}
		upstreamByRoute[rk] = append(upstreamByRoute[rk], upstreamObs{
			stopSequence: int(b.StopSequence),
			delaySeconds: observedArrival.Sub(baseline).Seconds(),
			observedAt:   now,
		})
	}
	return upstreamByRoute
}

// nearestBus picks the vehicle on a route closest to a stop and returns its plate,
// speed, and distance (metres) as history-row pointers. It returns all-nil when
// the stop has no coordinate (lat == 0) or the route has no live buses, matching
// the emit loop's original guard.
func nearestBus(lat, lon float64, buses []*models.BusPosition) (plate *string, speed *int16, dist *int) {
	if len(buses) == 0 || lat == 0 {
		return nil, nil, nil
	}
	nearest := buses[0]
	nearestDist := haversine(lat, lon,
		float64(nearest.PositionLat), float64(nearest.PositionLon))
	for _, bus := range buses[1:] {
		d := haversine(lat, lon,
			float64(bus.PositionLat), float64(bus.PositionLon))
		if d < nearestDist {
			nearestDist = d
			nearest = bus
		}
	}
	pn := nearest.PlateNumb
	spd := int16(nearest.Speed)
	di := int(nearestDist)
	return &pn, &spd, &di
}

// computeArrivalUnix resolves the absolute arrival instant the app decays locally
// between server pushes. Status 0 with a positive live estimate derives it from
// now+est; status 1 uses the (predicted or TDX) NextBusTime when it parses as
// RFC3339; otherwise it stays 0 and the app falls back to the estimate field.
func computeArrivalUnix(status uint8, est int32, nextBusTime string, now time.Time) int64 {
	if status == 0 && est > 0 {
		return now.Add(time.Duration(est) * time.Second).Unix()
	}
	if status == 1 && nextBusTime != "" {
		if t, err := time.Parse(time.RFC3339, nextBusTime); err == nil {
			return t.Unix()
		}
	}
	return 0
}
