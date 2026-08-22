package gtfs

import (
	"context"
	"sort"
	"time"

	"github.com/MobilityData/gtfs-realtime-bindings/golang/gtfs"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/busmodel"
	"go.uber.org/zap"
	"google.golang.org/protobuf/proto"
)

// The GTFS-RT delay producer, bus half (ADR-0019, FDPL-29).
//
// The rail half is an identity join; this one is the hard case, and every line
// of it is a gate. The live ETA feed knows a plate, a stop and a predicted
// arrival, and says nothing about which of the day's departures that vehicle is
// running. A trip update is addressed by trip_id. Everything here exists to
// bridge that gap without ever guessing across it, because a wrong assignment
// does not degrade a plan, it reroutes one.
//
// Two gates, in order.
//
// A plate seen on more than one subroute is dropped. Taipei and New Taipei
// publish route-level arrivals, so buildBusEtaMap fans one entry across every
// subroute of the route and the same vehicle appears under all of them. This
// makes those cities self-answering rather than special-cased: where the feed
// really does distinguish subroutes the plate is unique and matching proceeds,
// and where it does not every vehicle there is dropped.
//
// Then vehicles are assigned to departures by a single greedy pass that is both
// injective and order-preserving. Time alone breaks on short headways, where
// back-projection error exceeds the gap and two vehicles claim one trip. Order
// alone breaks when the running and scheduled counts disagree, which shifts a
// whole route by one. Together, either failing yields no match rather than a
// wrong one.
//
// What is emitted is absolute arrival times, not a delay. A single propagated
// delay would flatten a bus held up in one congested segment into "late by that
// much at every remaining stop", which is exactly the input that makes a planner
// reject a downstream transfer that is in fact catchable.

const (
	// _gtfsRTBusMatchWindow bounds how far a back-projected departure may sit from
	// the scheduled one it is assigned to.
	//
	// The back-projection is a live arrival estimate minus an accumulated running
	// time, so it carries both feeds' error. The window has to be wide enough to
	// hold a genuinely late bus and narrow enough that a vehicle never reaches
	// the departure before or after the one it is running. Beyond it the vehicle
	// is left unmatched, which costs a trip update and states nothing false.
	_gtfsRTBusMatchWindow = 20 * time.Minute
	// _gtfsRTBusMinCalls is how many stops a vehicle must be predicted at before
	// its back-projected departure is trusted. One stop is one estimate and one
	// estimate's error; the median of several is what makes the assignment stable
	// enough for an order-preserving pass to mean anything.
	_gtfsRTBusMinCalls = 2
	// _gtfsRTScanBatch is the COUNT hint for the live-snapshot scan. It matches
	// the one the live jobs' own key sweep uses; the whole keyspace here is a few
	// thousand keys, so this is a handful of round trips.
	_gtfsRTScanBatch = 500
)

// _busPatternOffsetSQL is every stop's cumulative running time from its route
// direction's origin — the term that turns a predicted arrival back into the
// departure the vehicle must have left on.
//
// Only complete patterns are read, for the same reason busPatternTripsSQL only
// lays out complete ones: one unknown segment silently compresses every offset
// after it, and a back-projection off by that much lands on the wrong departure.
var _busPatternOffsetSQL = `
  SELECT p.sub_route_uid, p.direction, p.stop_uid, p.offset_secs
  FROM (` + busmodel.PatternSQL + `) p
  WHERE p.complete`

// readBusArrivals reads the whole live bus ETA snapshot.
//
// The whole of it, not just the subroutes with candidate trips: the plate gate
// asks whether anything else in the feed claims the same vehicle, and an answer
// drawn from a subset would call a plate unique because the sibling subroute
// contradicting it was never read.
func (b *gtfsRTBuilder) readBusArrivals(ctx context.Context) (map[string]*models.Bus_RouteArrival, error) {
	var keys []string
	var cursor uint64
	for {
		batch, next, err := b.rc.Scan(ctx, cursor, shared.BusRouteEtaPattern(""), _gtfsRTScanBatch).Result()
		if err != nil {
			return nil, _oops.Wrapf(err, "gtfs-rt: scan bus arrivals")
		}
		keys = append(keys, batch...)
		cursor = next
		if cursor == 0 {
			break
		}
	}
	arrivals := make(map[string]*models.Bus_RouteArrival, len(keys))
	for start := 0; start < len(keys); start += _gtfsRTMGetBatch {
		end := min(start+_gtfsRTMGetBatch, len(keys))
		values, err := b.rc.MGet(ctx, keys[start:end]...).Result()
		if err != nil {
			return nil, _oops.Wrapf(err, "gtfs-rt: read bus arrivals")
		}
		for _, value := range values {
			raw, ok := value.(string)
			if !ok || raw == "" {
				continue
			}
			arrival := &models.Bus_RouteArrival{}
			if err := proto.Unmarshal([]byte(raw), arrival); err != nil {
				// One undecodable snapshot costs its own subroute, not the tick.
				continue
			}
			if arrival.GetSubRouteUid() == "" {
				continue
			}
			arrivals[arrival.GetSubRouteUid()] = arrival
		}
	}
	return arrivals, nil
}

// gtfsRTBusStats records why a running vehicle produced no trip update. Every
// counter is a gate, and their ratios are the only measure of how much of the
// live feed this producer can actually speak for.
type gtfsRTBusStats struct {
	vehiclesSeen    int
	plateAmbiguous  int
	patternUnknown  int
	tooFewCalls     int
	routeNoTrips    int
	unmatched       int
	matched         int
	stopTimeUpdates int
}

// gtfsRTVehicle is one plate observed on one subroute direction, reduced to the
// two things matching needs: where it must have started, and what it is
// predicted to do next.
type gtfsRTVehicle struct {
	plate string
	// projected is the back-projected origin departure as a unix time: the
	// median over its calls of (live arrival estimate - that stop's offset). The
	// median rather than the earliest call because each estimate carries its own
	// error and one of them being wrong should not move the vehicle.
	projected int64
	calls     []gtfsRTCall
}

// gtfsRTCall is one live arrival estimate.
type gtfsRTCall struct {
	stopUID  string
	sequence int32
	arrival  int64
}

// loadBusPatternOffsets reads the offsets for every complete route direction. It
// is refreshed with the rest of the static index rather than per tick: it
// changes when bus_segment_time is recomputed, which is nightly.
func loadBusPatternOffsets(ctx context.Context, db *pgxpool.Pool) (map[gtfsRTRouteKey]map[string]int64, error) {
	rows, err := db.Query(ctx, _busPatternOffsetSQL)
	if err != nil {
		return nil, _oops.Wrapf(err, "gtfs-rt: load bus pattern offsets")
	}
	defer rows.Close()
	offsets := make(map[gtfsRTRouteKey]map[string]int64, 8192)
	for rows.Next() {
		var subRouteUID, stopUID string
		var direction int32
		var offset int64
		if err := rows.Scan(&subRouteUID, &direction, &stopUID, &offset); err != nil {
			return nil, _oops.Wrapf(err, "gtfs-rt: load bus pattern offsets: scan")
		}
		key := gtfsRTRouteKey{subRouteUID: subRouteUID, direction: direction}
		if offsets[key] == nil {
			offsets[key] = make(map[string]int64, 32)
		}
		offsets[key][stopUID] = offset
	}
	if err := rows.Err(); err != nil {
		return nil, _oops.Wrapf(err, "gtfs-rt: load bus pattern offsets: rows")
	}
	return offsets, nil
}

// platesOnOneSubroute reports, per plate, whether the whole snapshot claims it
// for exactly one subroute.
//
// This is the first gate, and it is computed across the whole snapshot rather
// than per route: a plate is only unambiguous if nothing else in the feed claims
// it.
func platesOnOneSubroute(arrivals map[string]*models.Bus_RouteArrival) map[string]bool {
	seen := make(map[string]map[string]bool, 4096)
	for uid, arrival := range arrivals {
		for _, stop := range arrival.GetStops() {
			plate := stop.GetPlateNumb()
			if plate == "" {
				continue
			}
			if seen[plate] == nil {
				seen[plate] = make(map[string]bool, 2)
			}
			seen[plate][uid] = true
		}
	}
	unique := make(map[string]bool, len(seen))
	for plate, uids := range seen {
		unique[plate] = len(uids) == 1
	}
	return unique
}

// collectBusVehicles groups one subroute's estimates into vehicles and
// back-projects each one's origin departure.
func collectBusVehicles(
	arrival *models.Bus_RouteArrival,
	offsets map[gtfsRTRouteKey]map[string]int64,
	onOneSubroute map[string]bool,
	stats *gtfsRTBusStats,
) map[gtfsRTRouteKey][]gtfsRTVehicle {
	type vehicleKey struct {
		key   gtfsRTRouteKey
		plate string
	}
	calls := make(map[vehicleKey][]gtfsRTCall, 64)
	projections := make(map[vehicleKey][]int64, 64)
	for _, stop := range arrival.GetStops() {
		plate := stop.GetPlateNumb()
		if plate == "" || stop.GetArrivalUnix() <= 0 || stop.GetStopUid() == "" {
			continue
		}
		key := gtfsRTRouteKey{subRouteUID: arrival.GetSubRouteUid(), direction: stop.GetDirection()}
		id := vehicleKey{key: key, plate: plate}
		calls[id] = append(calls[id], gtfsRTCall{
			stopUID:  stop.GetStopUid(),
			sequence: stop.GetStopSequence(),
			arrival:  stop.GetArrivalUnix(),
		})
		if offset, known := offsets[key][stop.GetStopUid()]; known {
			projections[id] = append(projections[id], stop.GetArrivalUnix()-offset)
		}
	}

	vehicles := make(map[gtfsRTRouteKey][]gtfsRTVehicle, 4)
	for id, seen := range calls {
		stats.vehiclesSeen++
		if !onOneSubroute[id.plate] {
			stats.plateAmbiguous++
			continue
		}
		projected := projections[id]
		if len(projected) == 0 {
			// No stop on this vehicle's route has a known offset, so there is
			// nothing to project from. The route direction has no complete
			// pattern (FDPL-23, FDPL-26).
			stats.patternUnknown++
			continue
		}
		if len(projected) < _gtfsRTBusMinCalls {
			stats.tooFewCalls++
			continue
		}
		sort.Slice(seen, func(i, j int) bool { return seen[i].sequence < seen[j].sequence })
		vehicles[id.key] = append(vehicles[id.key], gtfsRTVehicle{
			plate:     id.plate,
			projected: medianUnix(projected),
			calls:     seen,
		})
	}
	return vehicles
}

// medianUnix is the middle of an unordered set of instants. An even count takes
// the lower of the two middles rather than averaging: the inputs are seconds
// from a feed that reports whole seconds, and an average invents a value none of
// the sources stated.
func medianUnix(values []int64) int64 {
	sorted := make([]int64, len(values))
	copy(sorted, values)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] < sorted[j] })
	return sorted[(len(sorted)-1)/2]
}

// matchBusVehicles assigns vehicles to scheduled departures.
//
// Both sides are sorted by departure and walked once. The pass is injective —
// each side advances past whatever it consumes — and order-preserving, because
// buses do not overtake, so the nth vehicle out is running the nth departure.
// Where the two disagree, the pointer that is behind advances alone and that
// side's entry goes unmatched rather than being forced onto the other.
func matchBusVehicles(vehicles []gtfsRTVehicle, trips []gtfsRTTrip, midnight time.Time) map[string]gtfsRTVehicle {
	sort.Slice(vehicles, func(i, j int) bool { return vehicles[i].projected < vehicles[j].projected })
	scheduled := make([]gtfsRTTrip, len(trips))
	copy(scheduled, trips)
	sort.Slice(scheduled, func(i, j int) bool { return scheduled[i].departure < scheduled[j].departure })

	window := int64(_gtfsRTBusMatchWindow / time.Second)
	matched := make(map[string]gtfsRTVehicle, len(vehicles))
	vehicleIndex, tripIndex := 0, 0
	for vehicleIndex < len(vehicles) && tripIndex < len(scheduled) {
		planned := midnight.Unix() + int64(scheduled[tripIndex].departure)*60
		gap := vehicles[vehicleIndex].projected - planned
		switch {
		case gap < -window:
			// This vehicle left long before the earliest departure still on
			// offer, so nothing here can be its trip.
			vehicleIndex++
		case gap > window:
			// This departure has no vehicle near it; a later one may.
			tripIndex++
		default:
			// Inside the window. Hold the vehicle if the next departure fits it
			// better — otherwise a vehicle running late would consume the trip in
			// front of the one it is actually on.
			if tripIndex+1 < len(scheduled) {
				next := midnight.Unix() + int64(scheduled[tripIndex+1].departure)*60
				if abs64(vehicles[vehicleIndex].projected-next) < abs64(gap) {
					tripIndex++
					continue
				}
			}
			matched[scheduled[tripIndex].tripID] = vehicles[vehicleIndex]
			vehicleIndex++
			tripIndex++
		}
	}
	return matched
}

func abs64(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}

// buildGTFSRTBusDelays turns the live ETA snapshot into trip updates.
//
// running is the candidate set buildGTFSRTCancellations already pruned: a trip
// cancelled today is not a trip a vehicle can be running.
func buildGTFSRTBusDelays(
	running map[gtfsRTRouteKey][]gtfsRTTrip,
	arrivals map[string]*models.Bus_RouteArrival,
	offsets map[gtfsRTRouteKey]map[string]int64,
	now time.Time,
) ([]*gtfs.FeedEntity, gtfsRTBusStats) {
	var stats gtfsRTBusStats
	onOneSubroute := platesOnOneSubroute(arrivals)
	midnight := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	serviceDate := now.Format("20060102")

	byKey := make(map[gtfsRTRouteKey][]gtfsRTVehicle, len(arrivals))
	for _, arrival := range arrivals {
		for key, vehicles := range collectBusVehicles(arrival, offsets, onOneSubroute, &stats) {
			byKey[key] = append(byKey[key], vehicles...)
		}
	}

	keys := make([]gtfsRTRouteKey, 0, len(byKey))
	for key := range byKey {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].subRouteUID != keys[j].subRouteUID {
			return keys[i].subRouteUID < keys[j].subRouteUID
		}
		return keys[i].direction < keys[j].direction
	})

	entities := make([]*gtfs.FeedEntity, 0, 512)
	for _, key := range keys {
		trips := running[key]
		if len(trips) == 0 {
			stats.routeNoTrips += len(byKey[key])
			continue
		}
		matched := matchBusVehicles(byKey[key], trips, midnight)
		stats.unmatched += len(byKey[key]) - len(matched)
		for tripID, vehicle := range matched {
			stats.matched++
			updates := busStopTimeUpdates(vehicle)
			stats.stopTimeUpdates += len(updates)
			entities = append(entities, &gtfs.FeedEntity{
				Id: proto.String(tripID),
				TripUpdate: &gtfs.TripUpdate{
					Trip: &gtfs.TripDescriptor{
						TripId:               proto.String(tripID),
						StartDate:            proto.String(serviceDate),
						ScheduleRelationship: gtfs.TripDescriptor_SCHEDULED.Enum(),
					},
					Vehicle:        &gtfs.VehicleDescriptor{Id: proto.String(vehicle.plate)},
					StopTimeUpdate: updates,
				},
			})
		}
	}
	sort.Slice(entities, func(i, j int) bool { return entities[i].GetId() < entities[j].GetId() })
	return entities, stats
}

// busStopTimeUpdates turns a matched vehicle's predictions into stop time
// updates, clamped so they never move backwards.
//
// TDX computes each stop's estimate independently and they can invert; a trip
// update whose times go backwards along the trip is rejected outright by some
// consumers and silently reordered by others.
//
// No stop_sequence is stated. gtfsStopTimesSQL renumbers the sequence with
// ROW_NUMBER because TDX repeats it within a trip, so the live sequence is not
// the feed's, and a StopTimeUpdate is addressable by stop_id alone — which is
// unique within a trip there by construction (DISTINCT ON (trip_id, stop_id)).
func busStopTimeUpdates(vehicle gtfsRTVehicle) []*gtfs.TripUpdate_StopTimeUpdate {
	updates := make([]*gtfs.TripUpdate_StopTimeUpdate, 0, len(vehicle.calls))
	var previous int64
	for _, call := range vehicle.calls {
		arrival := call.arrival
		if arrival < previous {
			arrival = previous
		}
		previous = arrival
		updates = append(updates, &gtfs.TripUpdate_StopTimeUpdate{
			StopId:  proto.String(call.stopUID),
			Arrival: &gtfs.TripUpdate_StopTimeEvent{Time: proto.Int64(arrival)},
		})
	}
	return updates
}

// logGTFSRTBusStats reports the matcher's coverage. Every counter but the last
// two is a vehicle the live feed knows about and the published feed says nothing
// for, which is the number that says whether the gates are set right.
func logGTFSRTBusStats(stats gtfsRTBusStats) {
	zap.S().Infow("built",
		"component", "gtfs_rt",
		"action", "bus_delay",
		"event", "built",
		"vehicles_seen", stats.vehiclesSeen,
		"plate_ambiguous", stats.plateAmbiguous,
		"pattern_unknown", stats.patternUnknown,
		"too_few_calls", stats.tooFewCalls,
		"route_no_trips", stats.routeNoTrips,
		"unmatched", stats.unmatched,
		"matched", stats.matched,
		"stop_time_updates", stats.stopTimeUpdates,
	)
}
