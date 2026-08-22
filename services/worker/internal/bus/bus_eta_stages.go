package bus

import (
	"slices"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/busmodel"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/history"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/pipeline"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/predict"
)

// This file holds the pure stages of processBusEtaCity (bus_eta.go): each is a
// deterministic function over plain values with no Redis/DB/network handle, lifted
// out of the live job so it can be exercised in isolation. The job still calls
// them in the same order at the same points; extraction changes structure, not
// behavior. I/O-bound steps (fetch/decode, weather load, batched DB lookups, the
// prediction/fill and proto-emit loop, Redis writes) stay in bus_eta.go where the
// collaborator handles live.

// parseSrcUpdateTime reads a TDX timestamp on an ETA entry (SrcUpdateTime, and
// DataTime, which carries the same shape). Usually RFC3339 with a +08:00 offset;
// some feeds drop the zone, which we read as Taipei local. Empty or unparseable
// values report false.
func parseSrcUpdateTime(s string) (time.Time, bool) {
	if s == "" {
		return time.Time{}, false
	}
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t, true
	}
	for _, layout := range []string{"2006-01-02T15:04:05", "2006-01-02 15:04:05"} {
		if t, err := time.ParseInLocation(layout, s, pipeline.Taipei); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

// etaSourceTime is the instant an ETA entry was published by its source:
// SrcUpdateTime where the city sends one, SrcTransTime otherwise. Both are the
// batch's publish stamp; no city sends neither, but one that did would report
// false and be used unaged.
func etaSourceTime(eta busmodel.RawEstimated) (time.Time, bool) {
	if t, ok := parseSrcUpdateTime(eta.SrcUpdateTime); ok {
		return t, true
	}
	return parseSrcUpdateTime(eta.SrcTransTime)
}

// adjustedEstimate is the live seconds-to-arrival for one ETA entry, net of the
// age of its source update: TDX reports EstimatedTime as of that publish stamp,
// so a stale snapshot is aged forward to now. When neither stamp parses the raw
// EstimatedTime is used unchanged. A snapshot older than its own estimate (or a
// negative EstimatedTime from TDX) clamps to 0 — "arriving now"; every consumer
// gates on est > 0, so 0 and a negative already behaved alike, but the history
// row stored the negative. Shared by the delay-propagation observation pass and
// the emit loop so both age the estimate identically.
func adjustedEstimate(eta busmodel.RawEstimated, now time.Time) int32 {
	est := eta.EstimatedTime
	if srcT, ok := etaSourceTime(eta); ok {
		est -= int32(now.Sub(srcT).Seconds())
	}
	return max(est, 0)
}

// _busEtaNoReading is the StopStatus published for a stop with no usable TDX
// entry at all. Outside TDX's own 0-4 range, so the app falls through to its
// unknown branch and renders '–' rather than a service state it was never told.
const _busEtaNoReading uint8 = 67

// How long past its own predicted arrival instant a StopStatus 0 entry still
// counts as 進站中. One ETA cron period plus a minute of slack for TDX's own
// publish lag.
const _busEtaArrivingGrace = 90 * time.Second

// arrivingExpired reports whether a StopStatus 0 entry has sat past its
// arrival instant long enough that "進站中" is no longer a claim we can make.
// TDX keeps republishing the last entry after a vehicle stops reporting, and
// adjustedEstimate clamps its elapsed estimate to 0 — the same shape as a bus
// genuinely at the kerb — so without this every stop on a route whose feed
// went quiet pins at 進站中 for the rest of the day. Entries with no parseable
// publish stamp cannot be aged and are left alone.
func arrivingExpired(eta busmodel.RawEstimated, now time.Time) bool {
	srcT, ok := etaSourceTime(eta)
	if !ok {
		return false
	}
	arrival := srcT.Add(time.Duration(eta.EstimatedTime) * time.Second)
	return now.Sub(arrival) > _busEtaArrivingGrace
}

// How far SrcUpdateTime may run ahead of DataTime before the entry counts as a
// frozen countdown rather than a fresh estimate. TDX documents a gap beyond this
// as normal: below 60 seconds to arrival the source stops recomputing, so it
// republishes the same estimate until the bus actually pulls in.
const _busEtaFrozenGap = 90 * time.Second

// countFrozenEstimates counts the entries whose estimate the source has stopped
// recomputing: DataTime older than the entry's publish stamp by more than the
// documented gap. Both must parse, so a feed that sends no DataTime at all
// (Taoyuan, New Taipei) contributes nothing.
//
// Measurement only, reported on the tick's completion log. adjustedEstimate ages
// every entry against SrcUpdateTime and arrivingExpired retires it 90 seconds
// past its own arrival instant; if these counts turn out to be material, a
// frozen entry must be exempted from both rather than read as a bus that never
// arrived (FDPL-79).
func countFrozenEstimates(eat []busmodel.RawEstimated) int {
	frozen := 0
	for _, e := range eat {
		srcT, srcOK := etaSourceTime(e)
		dataT, dataOK := parseSrcUpdateTime(e.DataTime)
		if !srcOK || !dataOK {
			continue
		}
		if srcT.Sub(dataT) > _busEtaFrozenGap {
			frozen++
		}
	}
	return frozen
}

// _busEtaDirectionUnknown is TDX's "direction not applicable" marker on an
// EstimatedTimeOfArrival entry. Tainan sends it on every schedule-only (StopStatus
// 1) entry, its SubRouteUID already naming the travel direction.
const _busEtaDirectionUnknown uint8 = 255

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
func buildBusEtaMap(city string, eat []busmodel.RawEstimated, mp []busmodel.StationMap) map[etaKey]busmodel.RawEstimated {
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
	etamap := make(map[etaKey]busmodel.RawEstimated)
	put := func(k etaKey, e busmodel.RawEstimated) {
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
			if dir == _busEtaDirectionUnknown {
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
		if t, err := time.ParseInLocation(layout, s, pipeline.Taipei); err == nil {
			return t.Unix()
		}
	}
	return 0
}

// etaForStop resolves one stop's ETA entry, falling back to the StopUIDs the
// other operators of a co-operated route use for the same stop. TDX keys each
// N1 estimate on the StopID of the operator running that trip, and the loader
// keeps one operator's stop list for ordering, so without the aliases every
// estimate published under a discarded list would read as no reading at all.
func etaForStop(etamap map[etaKey]busmodel.RawEstimated, b busmodel.StationMap) (busmodel.RawEstimated, bool) {
	if eta, ok := etamap[etaKey{b.SubRouteUID, b.Direction, b.StopUID}]; ok {
		return eta, true
	}
	for _, alias := range b.AliasStopUIDs {
		if eta, ok := etamap[etaKey{b.SubRouteUID, b.Direction, alias}]; ok {
			return eta, true
		}
	}
	return busmodel.RawEstimated{}, false
}

// buildTotalStops counts the stops per canonical subroute from the static map,
// giving each stop its route length (a model feature, and stored on history
// rows).
func buildTotalStops(mp []busmodel.StationMap) map[string]int {
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
func collectFillKeys(mp []busmodel.StationMap, etamap map[etaKey]busmodel.RawEstimated) ([]predict.RouteDirKey, map[string]bool) {
	var fillKeys []predict.RouteDirKey
	fillUIDs := make(map[string]bool)
	for _, b := range mp {
		uid, dir := b.SubRouteUID, b.Direction
		etaEnt, ok := etaForStop(etamap, b)
		if !ok {
			continue
		}
		if etaEnt.StopStatus == 1 && etaEnt.NextBusTime == "" {
			fillKeys = append(fillKeys, predict.RouteDirKey{SubRouteUID: uid, Direction: int32(dir)})
			fillUIDs[uid] = true
		}
		// Delay propagation needs the baseline (schedule + running time) at upstream
		// stops where a live bus is en route, so include those routes' departures
		// and stop offsets in the batched lookups too.
		if etaEnt.StopStatus == 0 {
			fillKeys = append(fillKeys, predict.RouteDirKey{SubRouteUID: uid, Direction: int32(dir)})
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
	mp []busmodel.StationMap,
	etamap map[etaKey]busmodel.RawEstimated,
	now time.Time,
	baselineFor func(b busmodel.StationMap, uid string, dir int32) time.Time,
) map[predict.RouteDirKey][]predict.UpstreamObs {
	upstreamByRoute := make(map[predict.RouteDirKey][]predict.UpstreamObs)
	for _, b := range mp {
		uid, cdir := b.SubRouteUID, b.Direction
		eta, ok := etaForStop(etamap, b)
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
		rk := predict.RouteDirKey{SubRouteUID: uid, Direction: dir}
		upstreamByRoute[rk] = append(upstreamByRoute[rk], predict.UpstreamObs{
			StopSequence: int(b.StopSequence),
			DelaySeconds: observedArrival.Sub(baseline).Seconds(),
			ObservedAt:   now,
		})
	}
	return upstreamByRoute
}

// _busDutyStatusEnded is TDX's DutyStatus 2: the vehicle passed the route's last
// stop and finished its duty. _busStatusNotInService is BusStatus 99: not
// serving passengers at all (depot shunting, refuelling, a chartered run). TDX's
// own system refuses to estimate arrivals from such a vehicle so it cannot
// distort the dynamic data, and the 99 case always carries DutyStatus 2.
const (
	_busDutyStatusEnded    uint8 = 2
	_busStatusNotInService uint8 = 99
)

// busInService reports whether a vehicle is serving passengers, and so whether
// it may be attributed to a stop. Out-of-service vehicles are still published to
// the app — the map labels them, and seeing a shunting bus is useful — they just
// cannot be the bus an estimate is about.
func busInService(bus *models.BusPosition) bool {
	return bus.DutyStatus != int32(_busDutyStatusEnded) &&
		bus.BusStatus != int32(_busStatusNotInService)
}

// nearestBus picks the in-service vehicle on a route closest to a stop and
// returns its plate, speed, and distance (metres) as history-row pointers. It
// returns all-nil when the stop has no coordinate (lat == 0) or the route has no
// in-service buses, matching the emit loop's original guard.
func nearestBus(lat, lon float64, buses []*models.BusPosition) (plate *string, speed *int16, dist *int) {
	if lat == 0 {
		return nil, nil, nil
	}
	var nearest *models.BusPosition
	var nearestDist float64
	for _, bus := range buses {
		if !busInService(bus) {
			continue
		}
		d := history.Haversine(lat, lon,
			float64(bus.PositionLat), float64(bus.PositionLon))
		if nearest == nil || d < nearestDist {
			nearestDist = d
			nearest = bus
		}
	}
	if nearest == nil {
		return nil, nil, nil
	}
	pn := nearest.PlateNumb
	spd := int16(nearest.Speed)
	di := int(nearestDist)
	return &pn, &spd, &di
}

// busAtStopKey identifies the stop one vehicle is standing at, on the same
// canonical subroute/direction axis as the rest of the ETA job.
type busAtStopKey struct {
	subRouteUID string
	direction   uint8
	stopUID     string
}

// stopPresence is one vehicle a feed reports at a named stop. Speed is a
// pointer because only the position feeds measure it: an A2 arrival/departure
// event names the vehicle and the stop but carries no speed, and a zero there
// would be recorded as an observed standstill.
type stopPresence struct {
	plate string
	speed *int16
}

// buildBusAtStopMap indexes the vehicles a position feed places at a named stop.
// Only Data.taipei fills StopUID (datataipei.go); TDX positions leave it empty
// and produce an empty map, which is what keeps every city without an A2 feed
// (bus_nearstop.go) on nearestBus.
//
// Last writer wins on the rare double: two vehicles of one subroute direction
// reported at the same stop are both legitimately there, and neither is a
// better answer than the other.
func buildBusAtStopMap(city string, positions []busmodel.RawPosition) map[busAtStopKey]stopPresence {
	out := make(map[busAtStopKey]stopPresence, len(positions))
	for _, p := range positions {
		if p.StopUID == "" {
			continue
		}
		// Same rule as nearestBus: a vehicle that ended its duty or is running
		// out of service is not the bus this stop's estimate is about, even when
		// the feed places it at the kerb.
		if p.DutyStatus == _busDutyStatusEnded || p.BusStatus == _busStatusNotInService {
			continue
		}
		plate := normalizeArrivalPlate(p.PlateNumb)
		if plate == "" {
			continue
		}
		speed := int16(p.Speed)
		uid, direction := shared.CanonicalSubroute(city, p.SubRouteUID, p.Direction)
		out[busAtStopKey{uid, direction, p.StopUID}] = stopPresence{plate: plate, speed: &speed}
	}
	return out
}

// busAtStop resolves the vehicle standing at one stop into the plate, speed and
// distance triple the emit loop carries. Distance is zero by definition: the
// feed reported this bus as having entered this stop, so there is nothing to
// estimate. Speed is whatever the feed measured, and nil when it measured none.
// Absent an entry it reports false and the caller keeps whatever nearestBus
// guessed.
func busAtStop(index map[busAtStopKey]stopPresence, key busAtStopKey) (*string, *int16, *int, bool) {
	p, ok := index[key]
	if !ok {
		return nil, nil, nil, false
	}
	dist := 0
	return &p.plate, p.speed, &dist, true
}

// crowdForPlate resolves the crowding of the one vehicle an estimate describes.
// The pairing is done here rather than on the client because the server is
// where the plate and the vehicle list already sit together (the same reason
// TRTC congestion is paired onto arrivals at ingest, CONTEXT.md).
//
// No plate, no match, or a vehicle with no reading all yield UNKNOWN, which the
// app renders as nothing at all — an unlabelled bus must never read as an empty
// one.
func crowdForPlate(buses []*models.BusPosition, plate *string) models.BusCrowdLevel {
	if plate == nil || *plate == "" {
		return models.BusCrowdLevel_BUS_CROWD_UNKNOWN
	}
	for _, bus := range buses {
		if normalizeArrivalPlate(bus.PlateNumb) == *plate {
			return bus.CrowdLevel
		}
	}
	return models.BusCrowdLevel_BUS_CROWD_UNKNOWN
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
