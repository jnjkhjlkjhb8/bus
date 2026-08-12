package main

import (
	"bytes"
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"go.uber.org/zap"
	"google.golang.org/protobuf/proto"
)

var (
	errBusSnapshotIncomplete = errors.New("bus city snapshot incomplete")
	errBusSnapshotConflict   = errors.New("bus city snapshot conflict")
	errBusSnapshotInvalid    = errors.New("bus city snapshot invalid")
)

type rawBusStation struct {
	StationUID  string `json:"stationuid"`
	StationID   string `json:"stationid"`
	StationName struct {
		Zhtw string `json:"Zh_tw"`
	} `json:"stationname"`
	StationPosition struct {
		PositionLon float64 `json:"PositionLon"`
		PositionLat float64 `json:"PositionLat"`
	} `json:"stationposition"`
	StationGroupID string `json:"stationgroupid"`
}

type rawBusStationGroup struct {
	StationGroupUID  string `json:"stationgroupuid"`
	StationGroupID   string `json:"stationgroupid"`
	StationGroupName struct {
		Zhtw string `json:"Zh_tw"`
	} `json:"stationgroupname"`
	StationGroupPosition struct {
		PositionLon float64 `json:"PositionLon"`
		PositionLat float64 `json:"PositionLat"`
	} `json:"stationgroupposition"`
}

// busCitySnapshot is a complete, validated, write-ready city replacement.
// Every JSON/protobuf value is built before a target transaction starts.
type busCitySnapshot struct {
	city         string
	prefix       string
	landingCycle string
	subroutes    map[string]*models.BusSubroute
	operatorRows [][]any
	subrouteRows [][]any
	stationRows  [][]any
	groupRows    [][]any
	memberRows   [][]any
	scheduleRows [][]any
	staticRows   [][]any
	stopMapRows  [][]any
	aliasRows    [][]any
}

func readBusCitySnapshot(ctx context.Context, src loadSource, city string) (*busCitySnapshot, error) {
	if src == nil {
		return nil, _oops.Wrapf(errBusSnapshotIncomplete, "nil source")
	}
	prefix := _citymap[city]
	if prefix == "" {
		return nil, _oops.With("city", city).Wrapf(errBusSnapshotInvalid, "city has no UID prefix")
	}
	cycleSource, ok := src.(busLandingCycleSource)
	if !ok {
		return nil, _oops.Wrapf(errBusSnapshotIncomplete, "source cannot return an atomic landing cycle")
	}
	q := newLoadQuarantine("bus", city)
	defer q.report()
	landingCycle := ""
	readDataset := func(table string) ([]byte, error) {
		body, cycle, err := readBusRawDataset(ctx, cycleSource, city, table)
		if err != nil {
			return nil, err
		}
		if landingCycle == "" {
			landingCycle = cycle
		} else if cycle != landingCycle {
			return nil, _oops.With("table", table).With("city", city).With("cycle", cycle).With("landing_cycle", landingCycle).Wrapf(errBusSnapshotIncomplete, "landing cycle does not match")
		}
		return body, nil
	}
	var operators []rawBusOperator
	operatorBody, err := readDataset("bus_operator")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(operatorBody, &operators); err != nil {
		return nil, _oops.Wrapf(err, "Operator")
	}
	opByID := make(map[string]rawBusOperator, len(operators))
	for i, op := range operators {
		hasID := strings.TrimSpace(op.OperatorID) != ""
		hasName := strings.TrimSpace(op.OperatorName.Zhtw) != ""
		hasAuthority := strings.TrimSpace(op.AuthorityCode) != ""
		if !hasID || !hasName || !hasAuthority {
			return nil, _oops.With("index", i).Wrapf(errBusSnapshotInvalid, "Operator has incomplete identity")
		}
		if op.AuthorityCode != prefix {
			return nil, _oops.With("index", i).With("authority_code", op.AuthorityCode).With("city", city).Wrapf(errBusSnapshotInvalid, "Operator authority does not belong")
		}
		if old, ok := opByID[op.OperatorID]; ok && !jsonSemanticEqual(old, op) {
			return nil, _oops.With("operator_id", op.OperatorID).Wrapf(errBusSnapshotConflict, "OperatorID has divergent variants")
		}
		opByID[op.OperatorID] = op
	}

	var routes []rawBusRoute
	routeBody, err := readDataset("bus_route")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(routeBody, &routes); err != nil {
		return nil, _oops.Wrapf(err, "Route")
	}
	snapshot := &busCitySnapshot{city: city, prefix: prefix, landingCycle: landingCycle, subroutes: make(map[string]*models.BusSubroute)}
	operatorIDs := make([]string, 0, len(opByID))
	for operatorID := range opByID {
		operatorIDs = append(operatorIDs, operatorID)
	}
	sort.Strings(operatorIDs)
	for _, operatorID := range operatorIDs {
		op := opByID[operatorID]
		snapshot.operatorRows = append(snapshot.operatorRows, []any{
			op.OperatorID, op.AuthorityCode, op.OperatorName.Zhtw,
			sanitizeOperatorPhone(op.OperatorPhone), op.OperatorURL,
		})
	}
	subrouteCount := 0
	for _, r := range routes {
		subrouteCount += len(r.SubRoutes)
	}
	q.consider("subroute", subrouteCount)
	routeToCanonical := make(map[string]map[string]struct{})
	nativeToCanonical := make(map[string]string)
	for ri, route := range routes {
		hasUID := strings.TrimSpace(route.RouteUID) != ""
		hasName := strings.TrimSpace(route.RouteName.Zhtw) != ""
		if !hasUID || !hasName || len(route.SubRoutes) == 0 {
			return nil, _oops.With("route_index", ri).Wrapf(errBusSnapshotInvalid, "Route missing route identity or subroutes")
		}
		if !uidBelongsToPrefix(route.RouteUID, prefix) {
			return nil, _oops.With("route_index", ri).With("route_uid", route.RouteUID).With("city", city).Wrapf(errBusSnapshotInvalid, "Route UID does not belong")
		}
		var ops []*models.BusOperator
		for _, ref := range route.Operators {
			op, ok := opByID[ref.OperatorID]
			if !ok {
				return nil, _oops.With("route_uid", route.RouteUID).With("operator_id", ref.OperatorID).Wrapf(errBusSnapshotInvalid, "Route references unknown operator")
			}
			ops = appendUniqueOperator(ops, &models.BusOperator{
				OperatorId: ref.OperatorID, OperatorName: op.OperatorName.Zhtw,
				OperatorPhone: sanitizeOperatorPhone(op.OperatorPhone), OperatorUrl: op.OperatorURL,
			})
		}
		for si, sub := range route.SubRoutes {
			uid, dir := shared.CanonicalSubroute(city, sub.SubRouteUID, sub.Direction)
			hasCanonicalUID := strings.TrimSpace(uid) != ""
			hasNativeUID := strings.TrimSpace(sub.SubRouteUID) != ""
			hasSubName := strings.TrimSpace(sub.SubRouteName.Zhtw) != ""
			if !hasCanonicalUID || !hasNativeUID || !hasSubName || dir > 1 {
				// Unusable identity: nothing downstream can key off this
				// subroute, so it goes rather than the city.
				q.drop("subroute", "subroute_identity", fmt.Sprintf("Route[%d].SubRoutes[%d] uid=%q dir=%d", ri, si, sub.SubRouteUID, sub.Direction))
				continue
			}
			if !uidBelongsToPrefix(sub.SubRouteUID, prefix) || !uidBelongsToPrefix(uid, prefix) {
				return nil, _oops.With("route_index", ri).With("subroute_index", si).With("sub_route_uid", sub.SubRouteUID).With("uid", uid).With("city", city).Wrapf(errBusSnapshotInvalid, "Route.SubRoutes UID canonical does not belong")
			}
			// sub is a range copy, so normalizing in place is what reaches the
			// candidate Direction below: the snapshot stores the canonical
			// "HH:MM" form regardless of which shape the city published. An
			// unparseable time blanks that one field rather than dropping the
			// subroute — empty already means "not published" to every reader,
			// and the route itself is still perfectly usable without it.
			for _, f := range []struct {
				label string
				value *string
			}{
				{label: "FirstBusTime", value: &sub.FirstBusTime}, {label: "LastBusTime", value: &sub.LastBusTime},
				{label: "HolidayFirstBusTime", value: &sub.HolidayFirstBusTime}, {label: "HolidayLastBusTime", value: &sub.HolidayLastBusTime},
			} {
				if *f.value == "" {
					continue
				}
				norm, ok := normalizeClock(*f.value)
				if !ok {
					q.drop("subroute", "subroute_clock", fmt.Sprintf("%s/%d %s=%q", uid, dir, f.label, *f.value))
					*f.value = ""
					continue
				}
				*f.value = norm
			}
			dep, dest := sub.DepartureStopNameZh, sub.DestinationStopNameZh
			if dep == "" {
				dep = route.DepartureStopNameZh
			}
			if dest == "" {
				dest = route.DestinationStopNameZh
			}
			if dir == 1 {
				dep, dest = dest, dep
			}
			candidate := &models.Direction{
				DepartureStopName: dep, DestinationStopName: dest,
				FirstBusTime: sub.FirstBusTime, LastBusTime: sub.LastBusTime,
				HolidayFirstBusTime: sub.HolidayFirstBusTime, HolidayLastBusTime: sub.HolidayLastBusTime,
			}
			existing := snapshot.subroutes[uid]
			if existing == nil {
				existing = &models.BusSubroute{
					RouteUID: route.RouteUID, RouteName: route.RouteName.Zhtw,
					SubRouteUID: uid, SubRouteName: sub.SubRouteName.Zhtw, City: city,
					DepartureStopName: dep, DestinationStopName: dest,
					Directions: make(map[int32]*models.Direction), Operators: ops,
				}
				snapshot.subroutes[uid] = existing
			} else {
				sameRouteUID := existing.RouteUID == route.RouteUID
				sameRouteName := existing.RouteName == route.RouteName.Zhtw
				sameSubName := existing.SubRouteName == sub.SubRouteName.Zhtw
				if !sameRouteUID || !sameRouteName || !sameSubName {
					return nil, _oops.With("uid", uid).Wrapf(errBusSnapshotConflict, "canonical route has divergent route/name variants")
				}
				for _, op := range ops {
					existing.Operators = appendUniqueOperator(existing.Operators, op)
				}
			}
			if prior := existing.Directions[int32(dir)]; prior != nil && !proto.Equal(prior, candidate) {
				return nil, _oops.With("uid", uid).With("dir", dir).Wrapf(errBusSnapshotConflict, "canonical route direction has divergent route variants")
			}
			if existing.Directions[int32(dir)] == nil {
				existing.Directions[int32(dir)] = candidate
			}
			if routeToCanonical[route.RouteUID] == nil {
				routeToCanonical[route.RouteUID] = make(map[string]struct{})
			}
			routeToCanonical[route.RouteUID][uid] = struct{}{}
			for _, native := range []string{sub.SubRouteUID, sub.SubRouteID, prefixID(prefix, sub.SubRouteID)} {
				if native != "" {
					if mapped := nativeToCanonical[native]; mapped != "" && mapped != uid {
						return nil, _oops.With("native", native).With("mapped", mapped).With("uid", uid).Wrapf(errBusSnapshotConflict, "native subroute maps to both")
					}
					nativeToCanonical[native] = uid
				}
			}
		}
	}
	if len(snapshot.subroutes) == 0 {
		return nil, _oops.Wrapf(errBusSnapshotInvalid, "Route produced zero canonical subroutes")
	}
	for _, sub := range snapshot.subroutes {
		sort.Slice(sub.Operators, func(i, j int) bool {
			return sub.Operators[i].OperatorId < sub.Operators[j].OperatorId
		})
		applySubrouteEndpoints(sub)
	}

	var stopVariants []rawStopofroute
	stopBody, err := readDataset("bus_stopofroute")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(stopBody, &stopVariants); err != nil {
		return nil, _oops.Wrapf(err, "StopOfRoute")
	}
	q.consider("stopofroute", len(stopVariants))
	// A stop or station whose survey has not finished is published with a (0,0)
	// coordinate — TDX names Keelung — so a zero position is source state, not a
	// broken record: the record is kept and counted rather than failing the city
	// over it. Everything downstream already tolerates it (the station-group join
	// matches nothing within a kilometre of (0,0), and the ETA path guards on
	// lat == 0), so the count exists to keep an invisible condition visible.
	unsurveyedStops := 0
	seenStops := make(map[string]rawStopofroute)
	for i, variant := range stopVariants {
		uid, dir := shared.CanonicalSubroute(city, variant.SubRouteUID, variant.Direction)
		route := snapshot.subroutes[uid]
		direction := directionFor(snapshot.subroutes, uid, dir)
		if !uidBelongsToPrefix(variant.RouteUID, prefix) || !uidBelongsToPrefix(variant.SubRouteUID, prefix) {
			return nil, _oops.With("index", i).With("sub_route_uid", variant.SubRouteUID).With("city", city).Wrapf(errBusSnapshotInvalid, "StopOfRoute UID does not belong")
		}
		if !uidBelongsToPrefix(uid, prefix) || route == nil || direction == nil {
			// Dangling reference: the parent subroute was never published, or
			// was itself dropped above. Nothing to attach these stops to.
			q.drop("stopofroute", "stopofroute_dangling", fmt.Sprintf("StopOfRoute[%d] -> %s/%d", i, uid, dir))
			continue
		}
		if variant.RouteUID != route.RouteUID {
			return nil, _oops.With("index", i).With("route_uid", variant.RouteUID).With("route_uid_2", route.RouteUID).With("uid", uid).Wrapf(errBusSnapshotInvalid, "StopOfRoute parent does not match")
		}
		if len(variant.Stops) == 0 {
			return nil, _oops.With("index", i).Wrapf(errBusSnapshotInvalid, "StopOfRoute has no stops")
		}
		lastSequence := uint8(0)
		unordered := false
		for j, stop := range variant.Stops {
			hasStopUID := strings.TrimSpace(stop.StopUID) != ""
			hasStopName := strings.TrimSpace(stop.StopName.Zhtw) != ""
			hasStationID := strings.TrimSpace(stop.StationID) != ""
			if !hasStopUID || !hasStopName || !hasStationID || stop.StopSequence == 0 {
				return nil, _oops.With("index", i).With("index_2", j).Wrapf(errBusSnapshotInvalid, "StopOfRoute.Stops has invalid identity/sequence")
			}
			if !validPosition(stop.StopPosition.PositionLon, stop.StopPosition.PositionLat) {
				unsurveyedStops++
			}
			if stop.StopSequence <= lastSequence {
				// TDX publishes lists whose sequence repeats or restarts mid-list
				// (a loop route renumbering, two segments concatenated). Nothing
				// downstream can order those stops, so the variant goes rather
				// than the city; the ratio gate decides if it is more than a tail.
				q.drop("stopofroute", "stopofroute_unordered", fmt.Sprintf("StopOfRoute[%d] %s/%d seq=%d", i, uid, dir, stop.StopSequence))
				unordered = true
				break
			}
			lastSequence = stop.StopSequence
		}
		if unordered {
			continue
		}
		key := fmt.Sprintf("%s/%d", uid, dir)
		if prior, ok := seenStops[key]; ok {
			// First variant wins for the stop order. TDX publishes one list per
			// operator on a co-operated route, and the same physical stop carries
			// a different StopID in each; picking the first is deterministic (the
			// payload order is stable) and beats discarding the city. Counted so a
			// rising tally is visible.
			if !jsonSemanticEqual(prior.Stops, variant.Stops) {
				q.drop("stopofroute", "stopofroute_divergent", key)
			}
			// The list is not kept, but its StopUIDs are: N1 keys each estimate on
			// the StopID of the operator that runs it, so without the alias every
			// arrival published under the discarded list matches no stop at all.
			snapshot.aliasRows = append(snapshot.aliasRows,
				busStopAliasRows(uid, dir, prior, variant)...)
			continue
		}
		seenStops[key] = variant
		for _, stop := range variant.Stops {
			direction.Stops = append(direction.Stops, &models.BusStop{
				StopName: stop.StopName.Zhtw, StopSequence: int32(stop.StopSequence),
				PositionLat: stop.StopPosition.PositionLat, PositionLon: stop.StopPosition.PositionLon,
				StationID: stop.StationID, StopUID: stop.StopUID,
			})
		}
	}
	// A direction whose stop lists were all dropped above cannot be served, and a
	// subroute that loses its last direction has nothing left to publish. Both go
	// rather than the city — the ratio gate above decides whether this many
	// missing lists means the whole payload is suspect.
	for _, uid := range sortedKeys(snapshot.subroutes) {
		sub := snapshot.subroutes[uid]
		pruned := false
		for _, dir := range []int32{0, 1} {
			if direction := sub.Directions[dir]; direction != nil && len(direction.Stops) == 0 {
				q.drop("stopofroute", "stopofroute_missing", fmt.Sprintf("%s/%d", uid, dir))
				delete(sub.Directions, dir)
				pruned = true
			}
		}
		if !pruned {
			continue
		}
		if len(sub.Directions) == 0 {
			delete(snapshot.subroutes, uid)
			continue
		}
		// The surviving direction now owns the subroute-level endpoints.
		applySubrouteEndpoints(sub)
	}
	if len(snapshot.subroutes) == 0 {
		return nil, _oops.Wrapf(errBusSnapshotInvalid, "every canonical subroute lost its StopOfRoute")
	}

	var shapes []rawBusShape
	shapeBody, err := readDataset("bus_shape")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(shapeBody, &shapes); err != nil {
		return nil, _oops.Wrapf(err, "Shape")
	}
	q.consider("shape", len(shapes))
	seenShapes := make(map[string]string)
	for i, shape := range shapes {
		if strings.TrimSpace(shape.Geometry) == "" {
			return nil, _oops.With("index", i).Wrapf(errBusSnapshotInvalid, "Shape has empty Geometry")
		}
		var targets []string
		if shape.SubRouteUID != "" {
			uid, _ := shared.CanonicalSubroute(city, shape.SubRouteUID, shape.Direction)
			ownRoute := uidBelongsToPrefix(shape.RouteUID, prefix)
			ownNativeSub := uidBelongsToPrefix(shape.SubRouteUID, prefix)
			ownCanonicalSub := uidBelongsToPrefix(uid, prefix)
			if !ownRoute || !ownNativeSub || !ownCanonicalSub {
				return nil, _oops.With("index", i).With("city", city).Wrapf(errBusSnapshotInvalid, "Shape subroute UID does not belong")
			}
			targets = []string{uid}
		} else {
			if !uidBelongsToPrefix(shape.RouteUID, prefix) {
				return nil, _oops.With("index", i).With("city", city).Wrapf(errBusSnapshotInvalid, "Shape route UID does not belong")
			}
			for uid := range routeToCanonical[shape.RouteUID] {
				targets = append(targets, uid)
			}
		}
		if len(targets) == 0 {
			// A shape whose RouteUID is absent from bus_route entirely.
			// Geometry is the map polyline only, so the route stays fully
			// usable without it.
			q.drop("shape", "shape_unknown_route", fmt.Sprintf("Shape[%d]->route:%s", i, shape.RouteUID))
			continue
		}
		for _, uid := range targets {
			_, dir := shared.CanonicalSubroute(city, shape.SubRouteUID, shape.Direction)
			route := snapshot.subroutes[uid]
			direction := directionFor(snapshot.subroutes, uid, dir)
			if direction == nil || route == nil {
				// The route exists but not this direction. A route-level shape
				// (no SubRouteUID) fans out to every subroute of the route and
				// drops once per subroute lacking shape.Direction, so this one
				// multiplies — scope tells them apart in the log.
				scope := "sub"
				if shape.SubRouteUID == "" {
					scope = "routelevel"
				}
				q.drop("shape", "shape_unknown_direction", fmt.Sprintf("Shape[%d]/%s->%s/%d", i, scope, uid, dir))
				continue
			}
			// A parent mismatch is a payload-integrity signal, not a per-record
			// defect: it stays fatal alongside the foreign-UID checks.
			if shape.RouteUID != "" && shape.RouteUID != route.RouteUID {
				return nil, _oops.With("index", i).With("route_uid", shape.RouteUID).With("route_uid_2", route.RouteUID).With("uid", uid).Wrapf(errBusSnapshotInvalid, "Shape parent does not match")
			}
			key := fmt.Sprintf("%s/%d", uid, dir)
			if prior, ok := seenShapes[key]; ok && prior != shape.Geometry {
				// First variant wins, as for StopOfRoute above.
				q.drop("shape", "shape_divergent", key)
				continue
			}
			seenShapes[key] = shape.Geometry
			direction.Geometry = shape.Geometry
		}
	}

	var schedules []rawBusSchedule
	scheduleBody, err := readDataset("bus_schedule")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(scheduleBody, &schedules); err != nil {
		return nil, _oops.Wrapf(err, "Schedule")
	}
	q.consider("schedule", len(schedules))
	seenSchedules := make(map[string]rawBusSchedule)
	for i, schedule := range schedules {
		uid, dir := shared.CanonicalSubroute(city, schedule.SubRouteUID, schedule.Direction)
		route := snapshot.subroutes[uid]
		direction := directionFor(snapshot.subroutes, uid, dir)
		if !uidBelongsToPrefix(schedule.RouteUID, prefix) || !uidBelongsToPrefix(schedule.SubRouteUID, prefix) {
			return nil, _oops.With("index", i).With("sub_route_uid", schedule.SubRouteUID).With("city", city).Wrapf(errBusSnapshotInvalid, "Schedule UID does not belong")
		}
		if !uidBelongsToPrefix(uid, prefix) || route == nil || direction == nil {
			q.drop("schedule", "schedule_dangling", fmt.Sprintf("Schedule[%d] -> %s/%d", i, uid, dir))
			continue
		}
		// A parent mismatch is a payload-integrity signal, not a per-record
		// defect: it stays fatal alongside the foreign-UID checks.
		if schedule.RouteUID != route.RouteUID {
			return nil, _oops.With("index", i).With("route_uid", schedule.RouteUID).With("route_uid_2", route.RouteUID).With("uid", uid).Wrapf(errBusSnapshotInvalid, "Schedule parent does not match")
		}
		key := fmt.Sprintf("%s/%d", uid, dir)
		if prior, ok := seenSchedules[key]; ok {
			// First variant wins, as for StopOfRoute and Shape above.
			if !jsonSemanticEqual(prior, schedule) {
				q.drop("schedule", "schedule_divergent", key)
			}
			continue
		}
		seenSchedules[key] = schedule
		rows, modelRows, err := buildScheduleRows(uid, dir, schedule)
		if err != nil {
			// One malformed timetable (an empty TripID, an unparseable stop
			// time) costs this subroute its schedule, not the city its load.
			q.drop("schedule", "schedule_malformed", fmt.Sprintf("Schedule[%d] %s/%d: %v", i, uid, dir, err))
			continue
		}
		snapshot.scheduleRows = append(snapshot.scheduleRows, rows...)
		direction.Schedules = append(direction.Schedules, modelRows...)
	}

	var stations []rawBusStation
	stationBody, err := readDataset("bus_station")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(stationBody, &stations); err != nil {
		return nil, _oops.Wrapf(err, "Station")
	}
	stationUIDs := make(map[string]struct{}, len(stations))
	stationIDs := make(map[string]string, len(stations))
	stationsByUID := make(map[string]rawBusStation, len(stations))
	unsurveyedStations := 0
	for i, station := range stations {
		ownUID := uidBelongsToPrefix(station.StationUID, prefix)
		if !ownUID || station.StationID == "" || station.StationName.Zhtw == "" {
			return nil, _oops.With("index", i).Wrapf(errBusSnapshotInvalid, "Station has invalid identity")
		}
		// Same pending-survey case as the stop positions above. A station cannot
		// be dropped over it: every route stop referencing it would then fail the
		// missing-station check below and take the city with it.
		if !validPosition(station.StationPosition.PositionLon, station.StationPosition.PositionLat) {
			unsurveyedStations++
		}
		if prior, exists := stationsByUID[station.StationUID]; exists {
			if !jsonSemanticEqual(prior, station) {
				return nil, _oops.With("station_uid", station.StationUID).Wrapf(errBusSnapshotConflict, "StationUID has divergent variants")
			}
			continue
		}
		if priorUID := stationIDs[station.StationID]; priorUID != "" && priorUID != station.StationUID {
			return nil, _oops.With("station_id", station.StationID).With("prior_uid", priorUID).With("station_uid", station.StationUID).Wrapf(errBusSnapshotConflict, "StationID maps to both")
		}
		stationsByUID[station.StationUID] = station
		stationUIDs[station.StationUID] = struct{}{}
		stationIDs[station.StationID] = station.StationUID
		snapshot.stationRows = append(snapshot.stationRows, []any{
			station.StationUID, station.StationID, normalizeStationName(station.StationName.Zhtw),
			station.StationPosition.PositionLon, station.StationPosition.PositionLat, station.StationGroupID,
		})
	}
	stationOrder := make([]string, 0, len(stationsByUID))
	for uid := range stationsByUID {
		stationOrder = append(stationOrder, uid)
	}
	sort.Strings(stationOrder)
	uniqueStations := make([]rawBusStation, 0, len(stationOrder))
	for _, uid := range stationOrder {
		uniqueStations = append(uniqueStations, stationsByUID[uid])
	}
	for uid, sub := range snapshot.subroutes {
		for _, direction := range sub.Directions {
			for _, stop := range direction.Stops {
				fullID := prefixID(prefix, stop.StationID)
				if _, ok := stationUIDs[fullID]; !ok {
					if _, localOK := stationIDs[stop.StationID]; !localOK {
						return nil, _oops.With("uid", uid).With("stop_uid", stop.StopUID).With("station_id", stop.StationID).Wrapf(errBusSnapshotInvalid, "route stop references missing station")
					}
				}
			}
		}
	}

	var groups []rawBusStationGroup
	groupBody, err := readDataset("bus_stationgroup")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(groupBody, &groups); err != nil {
		return nil, _oops.Wrapf(err, "StationGroup")
	}
	groupsByID := make(map[string]rawBusStationGroup)
	groupsByUID := make(map[string]rawBusStationGroup)
	for i, group := range groups {
		ownUID := uidBelongsToPrefix(group.StationGroupUID, prefix)
		hasPosition := validPosition(group.StationGroupPosition.PositionLon, group.StationGroupPosition.PositionLat)
		if !ownUID || group.StationGroupID == "" || group.StationGroupName.Zhtw == "" || !hasPosition {
			return nil, _oops.With("index", i).Wrapf(errBusSnapshotInvalid, "StationGroup has invalid identity/position")
		}
		if prior, ok := groupsByID[group.StationGroupID]; ok && !jsonSemanticEqual(prior, group) {
			return nil, _oops.With("station_group_id", group.StationGroupID).Wrapf(errBusSnapshotConflict, "StationGroupID has divergent UID/payload")
		}
		if prior, ok := groupsByUID[group.StationGroupUID]; ok {
			if !jsonSemanticEqual(prior, group) {
				return nil, _oops.With("station_group_uid", group.StationGroupUID).Wrapf(errBusSnapshotConflict, "StationGroupUID has divergent variants")
			}
			continue
		}
		groupsByID[group.StationGroupID] = group
		groupsByUID[group.StationGroupUID] = group
		snapshot.groupRows = append(snapshot.groupRows, []any{
			group.StationGroupUID, group.StationGroupID, normalizeStationName(group.StationGroupName.Zhtw),
			group.StationGroupPosition.PositionLon, group.StationGroupPosition.PositionLat, "tdx",
		})
	}
	type manualGroupAggregate struct {
		name       string
		lonSum     float64
		latSum     float64
		stationCnt int
	}
	manualGroups := make(map[string]*manualGroupAggregate)
	for _, station := range uniqueStations {
		stationName := normalizeStationName(station.StationName.Zhtw)
		groupUID := ""
		if group, ok := groupsByID[station.StationGroupID]; ok {
			groupUID = group.StationGroupUID
		} else {
			groupUID = manualGroupUID(city, stationName)
			aggregate := manualGroups[groupUID]
			if aggregate == nil {
				aggregate = &manualGroupAggregate{name: stationName}
				manualGroups[groupUID] = aggregate
			}
			aggregate.lonSum += station.StationPosition.PositionLon
			aggregate.latSum += station.StationPosition.PositionLat
			aggregate.stationCnt++
		}
		snapshot.memberRows = append(snapshot.memberRows, []any{
			station.StationUID, groupUID, station.StationID, stationName,
			station.StationPosition.PositionLon, station.StationPosition.PositionLat,
		})
	}
	manualUIDs := make([]string, 0, len(manualGroups))
	for uid := range manualGroups {
		manualUIDs = append(manualUIDs, uid)
	}
	sort.Strings(manualUIDs)
	for _, uid := range manualUIDs {
		aggregate := manualGroups[uid]
		snapshot.groupRows = append(snapshot.groupRows, []any{
			uid, uid, aggregate.name,
			aggregate.lonSum / float64(aggregate.stationCnt),
			aggregate.latSum / float64(aggregate.stationCnt),
			"manual_name",
		})
	}

	var fares []rawBusFare
	fareBody, err := readDataset("bus_routefare")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(fareBody, &fares); err != nil {
		return nil, _oops.Wrapf(err, "RouteFare")
	}
	q.consider("routefare", len(fares))
	fareCandidates := make(map[string][]*models.Bus_Fare)
	for i, rawFare := range fares {
		fare := &models.Bus_Fare{
			FarePricingType: rawFare.FarePricingType, IsFreeBus: rawFare.IsFreeBus == 1,
			SectionFaresJson: jsonOrNil(rawFare.SectionFares), StageFaresJson: jsonOrNil(rawFare.StageFares), OdFaresJson: jsonOrNil(rawFare.ODFares),
		}
		var targets []string
		if rawFare.SubRouteID != "" {
			for _, native := range []string{rawFare.SubRouteID, prefixID(prefix, rawFare.SubRouteID)} {
				if uid := nativeToCanonical[native]; uid != "" {
					targets = append(targets, uid)
				}
			}
			if len(targets) == 0 {
				uid, _ := shared.CanonicalSubroute(city, prefixID(prefix, rawFare.SubRouteID), 0)
				if snapshot.subroutes[uid] != nil {
					targets = append(targets, uid)
				}
			}
		}
		if rawFare.IsForAllSubRoutes == 1 && rawFare.RouteID != "" {
			for uid := range routeToCanonical[prefixID(prefix, rawFare.RouteID)] {
				targets = append(targets, uid)
			}
			for uid := range routeToCanonical[rawFare.RouteID] {
				targets = append(targets, uid)
			}
		}
		if len(targets) == 0 {
			return nil, _oops.With("index", i).Wrapf(errBusSnapshotInvalid, "RouteFare cannot map native route/subroute IDs")
		}
		for _, uid := range uniqueStrings(targets) {
			fareCandidates[uid] = append(fareCandidates[uid], fare)
		}
	}
	for _, uid := range sortedKeys(fareCandidates) {
		sub := snapshot.subroutes[uid]
		if sub == nil {
			// The subroute lost its stop lists above; nothing left to price.
			q.drop("routefare", "routefare_dangling", uid)
			continue
		}
		sub.Fare = mergeBusFares(fareCandidates[uid])
	}

	// Quarantining a tail keeps the city current; quarantining a third of it
	// ships a gutted city that looks fresh. Past the ratio the city fails
	// instead, keeping the previous load's rows — stale but whole.
	if err := q.exceeded(); err != nil {
		return nil, _oops.Join(errBusSnapshotInvalid, err)
	}
	if unsurveyedStops > 0 || unsurveyedStations > 0 {
		zap.S().Warnw("unsurveyed positions",
			"component", "load",
			"action", "bus",
			"event", "unsurveyed_positions",
			"city", city,
			"stop_count", unsurveyedStops,
			"station_count", unsurveyedStations,
		)
	}
	if err := snapshot.buildWriteRows(); err != nil {
		return nil, err
	}
	return snapshot, nil
}

func readBusRawDataset(ctx context.Context, src busLandingCycleSource, city, table string) ([]byte, string, error) {
	body, fetchedAt, landingCycle, err := src.datasetJSONWithLandingCycle(ctx, table, "city", city)
	if err != nil {
		return nil, "", _oops.With("table", table).With("city", city).Wrapf(err, "read raw partition")
	}
	if fetchedAt.IsZero() || isStale(fetchedAt) {
		return nil, "", _oops.With("table", table).With("city", city).With("fetched_at", fetchedAt.Format(time.RFC3339)).Wrapf(errBusSnapshotIncomplete, "landing state is missing or stale")
	}
	if strings.TrimSpace(landingCycle) == "" {
		return nil, "", _oops.With("table", table).With("city", city).Wrapf(errBusSnapshotIncomplete, "landing state has no cycle")
	}
	if len(bytes.TrimSpace(body)) == 0 {
		return nil, "", _oops.With("table", table).With("city", city).Wrapf(errBusSnapshotInvalid, "has empty JSON body")
	}
	return body, landingCycle, nil
}

func (s *busCitySnapshot) buildWriteRows() error {
	uids := make([]string, 0, len(s.subroutes))
	for uid := range s.subroutes {
		uids = append(uids, uid)
	}
	sort.Strings(uids)
	for _, uid := range uids {
		sub := s.subroutes[uid]
		pb, err := (proto.MarshalOptions{Deterministic: true}).Marshal(sub)
		if err != nil {
			return _oops.With("uid", uid).Wrapf(err, "marshal protobuf")
		}
		s.staticRows = append(s.staticRows, []any{sub.SubRouteName, sub.RouteName, sub.SubRouteUID, sub.RouteUID, sub.City, sub.DepartureStopName, sub.DestinationStopName, pb})
		dirs := make([]int, 0, len(sub.Directions))
		for dir := range sub.Directions {
			dirs = append(dirs, int(dir))
		}
		sort.Ints(dirs)
		for _, rawDir := range dirs {
			dir := int32(rawDir)
			direction := sub.Directions[dir]
			stops, err := json.Marshal(direction.Stops)
			if err != nil {
				return _oops.With("uid", uid).With("dir", dir).Wrapf(err, "marshal / stops")
			}
			schedules, err := json.Marshal(direction.Schedules)
			if err != nil {
				return _oops.With("uid", uid).With("dir", dir).Wrapf(err, "marshal / schedules")
			}
			ops := make([]busOperatorJSON, 0, len(sub.Operators))
			for _, op := range sub.Operators {
				ops = append(ops, busOperatorJSON{ID: op.OperatorId, Name: op.OperatorName, Phone: op.OperatorPhone, URL: op.OperatorUrl})
			}
			operators, err := json.Marshal(ops)
			if err != nil {
				return _oops.With("uid", uid).Wrapf(err, "marshal operators")
			}
			s.subrouteRows = append(s.subrouteRows, []any{
				sub.SubRouteUID, sub.RouteUID, dir, sub.RouteName, sub.SubRouteName, sub.City,
				direction.DepartureStopName, direction.DestinationStopName, direction.Geometry,
				stops, schedules, operators,
			})
			for _, stop := range direction.Stops {
				s.stopMapRows = append(s.stopMapRows, []any{
					prefixID(s.prefix, stop.StationID), stop.StopName, sub.SubRouteUID,
					sub.SubRouteName, dir, stop.StopUID, stop.StopSequence,
				})
			}
		}
	}
	return nil
}

// busStopAliasRows pairs a discarded operator's stop list against the kept one
// by stop sequence — the position in the run is what the two lists agree on,
// since the whole point is that their StopUIDs differ — and returns one alias
// row per position whose UID actually differs. Positions the kept list does not
// have are skipped: an alias may only point at a stop the ETA join can reach.
func busStopAliasRows(uid string, dir uint8, kept, discarded rawStopofroute) [][]any {
	keptBySequence := make(map[uint8]string, len(kept.Stops))
	for _, stop := range kept.Stops {
		keptBySequence[stop.StopSequence] = stop.StopUID
	}
	rows := make([][]any, 0, len(discarded.Stops))
	for _, stop := range discarded.Stops {
		canonical, ok := keptBySequence[stop.StopSequence]
		if !ok || canonical == stop.StopUID {
			continue
		}
		rows = append(rows, []any{uid, int16(dir), stop.StopUID, canonical})
	}
	return rows
}

func buildScheduleRows(uid string, dir uint8, schedule rawBusSchedule) ([][]any, []*models.Bus_Schedule, error) {
	var rows [][]any
	var modelRows []*models.Bus_Schedule
	for _, timetable := range schedule.Timetables {
		if timetable.TripID == "" {
			return nil, nil, errors.New("timetable has empty TripID")
		}
		service := mask2(timetable.ServiceDay.Monday, timetable.ServiceDay.Tuesday, timetable.ServiceDay.Wednesday, timetable.ServiceDay.Thursday, timetable.ServiceDay.Friday, timetable.ServiceDay.Saturday, timetable.ServiceDay.Sunday)
		// The DB keeps every stop of the trip (segment times and ETA prediction
		// read them); the proto payload carries only the origin, since the app's
		// timetable board lists departures. TDX does not promise StopTimes are
		// sorted, so the origin is the lowest StopSequence rather than the first
		// element.
		var origin *models.Bus_Schedule
		var originSeq int
		for _, stop := range timetable.StopTimes {
			// The upper bound is the bus_schedule.stop_sequence SMALLINT column: an
			// out-of-range sequence would wrap to a negative on the int16 cast below.
			seqInRange := stop.StopSequence > 0 && stop.StopSequence <= math.MaxInt16
			hasIdentity := stop.StopUID != "" && stop.StopName.Zhtw != ""
			hasClocks := validClock(stop.ArrivalTime) && validClock(stop.DepartureTime)
			if !seqInRange || !hasIdentity || !hasClocks {
				return nil, nil, _oops.With("trip_id", timetable.TripID).Errorf("trip has invalid stop identity/sequence/time")
			}
			rows = append(rows, []any{uid, int16(dir), false, timetable.TripID, timetable.IsLowFloor, int16(stop.StopSequence), stop.StopUID, stop.StopName.Zhtw, stop.ArrivalTime, stop.DepartureTime, int16(service)})
			if origin != nil && stop.StopSequence >= originSeq {
				continue
			}
			originSeq = stop.StopSequence
			origin = &models.Bus_Schedule{
				IsTimetable: true, Tripid: timetable.TripID, Islowfloor: timetable.IsLowFloor,
				MinHeadwayMinsArrivalTime: stop.ArrivalTime, MaxHeadwayMinsDepartureTime: stop.DepartureTime,
				ServiceDay: int32(service),
			}
		}
		if origin != nil {
			modelRows = append(modelRows, origin)
		}
	}
	for _, frequency := range schedule.Frequencys {
		hasClocks := validClock(frequency.StartTime) && validClock(frequency.EndTime)
		hasHeadway := frequency.MinHeadwayMins != 0 && frequency.MaxHeadwayMins >= frequency.MinHeadwayMins
		if !hasClocks || !hasHeadway {
			return nil, nil, errors.New("frequency has invalid time/headway")
		}
		service := mask2(frequency.ServiceDay.Monday, frequency.ServiceDay.Tuesday, frequency.ServiceDay.Wednesday, frequency.ServiceDay.Thursday, frequency.ServiceDay.Friday, frequency.ServiceDay.Saturday, frequency.ServiceDay.Sunday)
		rows = append(rows, []any{uid, int16(dir), true, "", false, int16(-1), fmt.Sprint(frequency.MinHeadwayMins), fmt.Sprint(frequency.MaxHeadwayMins), frequency.StartTime, frequency.EndTime, int16(service)})
		modelRows = append(modelRows, &models.Bus_Schedule{
			IsTimetable: false, Start_Time: frequency.StartTime, End_Time: frequency.EndTime,
			MinHeadwayMinsArrivalTime: fmt.Sprint(frequency.MinHeadwayMins), MaxHeadwayMinsDepartureTime: fmt.Sprint(frequency.MaxHeadwayMins),
			ServiceDay: int32(service),
		})
	}
	return rows, modelRows, nil
}

func decodeStrictJSONArray(body []byte, target any) error {
	trimmed := bytes.TrimSpace(body)
	if len(trimmed) < 2 || trimmed[0] != '[' || trimmed[len(trimmed)-1] != ']' {
		return errors.New("payload is not a JSON array")
	}
	dec := json.NewDecoder(bytes.NewReader(trimmed))
	if err := dec.Decode(target); err != nil {
		return err
	}
	var trailing json.RawMessage
	err := dec.Decode(&trailing)
	if errors.Is(err, io.EOF) {
		return nil
	}
	if err == nil {
		return errors.New("trailing JSON value")
	}
	return _oops.Wrapf(err, "malformed trailing JSON")
}

func validClock(value string) bool {
	_, err := time.Parse("15:04", value)
	return err == nil
}

// normalizeClock accepts the two wall-clock shapes TDX publishes for a bus
// first/last time — "HH:MM" and bare "HHMM" — and returns the canonical
// "HH:MM" form. Hours run to 29 because a transit service day extends past
// midnight, so "25:30" is a real last-bus time that time.Parse("15:04")
// rejects. Callers that re-parse the value with time.Parse (rail and bus
// timetable stop times) must keep using validClock instead.
func normalizeClock(value string) (string, bool) {
	v := strings.TrimSpace(value)
	if len(v) == 4 && v[2] != ':' {
		v = v[:2] + ":" + v[2:]
	}
	if len(v) != 5 || v[2] != ':' {
		return "", false
	}
	for _, i := range [...]int{0, 1, 3, 4} {
		if v[i] < '0' || v[i] > '9' {
			return "", false
		}
	}
	h := int(v[0]-'0')*10 + int(v[1]-'0')
	m := int(v[3]-'0')*10 + int(v[4]-'0')
	if h > 29 || m > 59 {
		return "", false
	}
	return v, true
}

func validPosition(lon, lat float64) bool {
	return !math.IsNaN(lon) && !math.IsNaN(lat) && !math.IsInf(lon, 0) && !math.IsInf(lat, 0) && lon >= -180 && lon <= 180 && lat >= -90 && lat <= 90 && (lon != 0 || lat != 0)
}

func prefixID(prefix, id string) string {
	if id == "" || strings.HasPrefix(id, prefix) {
		return id
	}
	return prefix + id
}

func uidBelongsToPrefix(uid, prefix string) bool {
	return uid != "" && prefix != "" && strings.HasPrefix(uid, prefix)
}

// applySubrouteEndpoints lifts the outbound direction's endpoints onto the
// subroute, falling back to inbound for a subroute published in one direction
// only. Called again whenever a direction is pruned, so the subroute-level names
// never outlive the direction they came from.
func applySubrouteEndpoints(sub *models.BusSubroute) {
	direction := sub.Directions[0]
	if direction == nil {
		direction = sub.Directions[1]
	}
	if direction == nil {
		return
	}
	sub.DepartureStopName = direction.DepartureStopName
	sub.DestinationStopName = direction.DestinationStopName
}

// normalizeStationName strips TDX's "(市區公車)" station-name suffix. Keelung
// tags its city-bus stations with it while the InterCity dataset names the same
// physical pole without it, which breaks the same-name fold in the group-member
// upsert (bus_writer.go) and surfaces one stop twice in the nearby list.
// one known-noise suffix, not a general parenthesis strip — "(往北)",
// "(捷運站)" and friends distinguish real stops.
func normalizeStationName(name string) string {
	return strings.TrimSuffix(name, "(市區公車)")
}

func manualGroupUID(city, name string) string {
	sum := md5.Sum([]byte(name))
	return city + ":manual:" + hex.EncodeToString(sum[:])
}

func directionFor(routes map[string]*models.BusSubroute, uid string, dir uint8) *models.Direction {
	if route := routes[uid]; route != nil {
		return route.Directions[int32(dir)]
	}
	return nil
}

func appendUniqueOperator(operators []*models.BusOperator, candidate *models.BusOperator) []*models.BusOperator {
	for _, operator := range operators {
		if operator.OperatorId == candidate.OperatorId {
			return operators
		}
	}
	return append(operators, candidate)
}

func jsonSemanticEqual(a, b any) bool {
	left, err := json.Marshal(a)
	if err != nil {
		return false
	}
	right, err := json.Marshal(b)
	return err == nil && bytes.Equal(left, right)
}

func uniqueStrings(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	out := make([]string, 0, len(values))
	for _, value := range values {
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
	}
	return out
}
