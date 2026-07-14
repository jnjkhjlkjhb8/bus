package main

import (
	"bytes"
	"context"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
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
	subroutes    map[string]*models.BusSubroute
	subrouteRows [][]any
	stationRows  [][]any
	groupRows    [][]any
	memberRows   [][]any
	scheduleRows [][]any
	staticRows   [][]any
	stopMapRows  [][]any
}

func readBusCitySnapshot(ctx context.Context, src loadSource, city string) (*busCitySnapshot, error) {
	if src == nil {
		return nil, fmt.Errorf("%w: nil source", errBusSnapshotIncomplete)
	}
	prefix := citymap[city]
	if prefix == "" {
		return nil, fmt.Errorf("%w: city %q has no UID prefix", errBusSnapshotInvalid, city)
	}
	var operators []rawBusOperator
	operatorBody, err := readBusRawDataset(ctx, src, city, "bus_operator")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(operatorBody, &operators); err != nil {
		return nil, fmt.Errorf("%w: Operator: %v", errBusSnapshotInvalid, err)
	}
	opByID := make(map[string]rawBusOperator, len(operators))
	for i, op := range operators {
		if strings.TrimSpace(op.OperatorID) == "" {
			return nil, fmt.Errorf("%w: Operator[%d] has empty OperatorID", errBusSnapshotInvalid, i)
		}
		if old, ok := opByID[op.OperatorID]; ok && !jsonSemanticEqual(old, op) {
			return nil, fmt.Errorf("%w: OperatorID %s has divergent variants", errBusSnapshotConflict, op.OperatorID)
		}
		opByID[op.OperatorID] = op
	}

	var routes []rawBusRoute
	routeBody, err := readBusRawDataset(ctx, src, city, "bus_route")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(routeBody, &routes); err != nil {
		return nil, fmt.Errorf("%w: Route: %v", errBusSnapshotInvalid, err)
	}
	snapshot := &busCitySnapshot{city: city, prefix: prefix, subroutes: make(map[string]*models.BusSubroute)}
	routeToCanonical := make(map[string]map[string]struct{})
	nativeToCanonical := make(map[string]string)
	for ri, route := range routes {
		if strings.TrimSpace(route.RouteUID) == "" || strings.TrimSpace(route.RouteName.Zhtw) == "" || len(route.SubRoutes) == 0 {
			return nil, fmt.Errorf("%w: Route[%d] missing route identity or subroutes", errBusSnapshotInvalid, ri)
		}
		var ops []*models.BusOperator
		for _, ref := range route.Operators {
			op, ok := opByID[ref.OperatorID]
			if !ok {
				return nil, fmt.Errorf("%w: Route %s references unknown operator %s", errBusSnapshotInvalid, route.RouteUID, ref.OperatorID)
			}
			ops = appendUniqueOperator(ops, &models.BusOperator{
				OperatorId: ref.OperatorID, OperatorName: op.OperatorName.Zhtw,
				OperatorPhone: sanitizeOperatorPhone(op.OperatorPhone), OperatorUrl: op.OperatorUrl,
			})
		}
		for si, sub := range route.SubRoutes {
			uid, dir := shared.CanonicalSubroute(city, sub.SubRouteUID, sub.Direction)
			if strings.TrimSpace(uid) == "" || strings.TrimSpace(sub.SubRouteUID) == "" || strings.TrimSpace(sub.SubRouteName.Zhtw) == "" || dir > 1 {
				return nil, fmt.Errorf("%w: Route[%d].SubRoutes[%d] has invalid identity/direction", errBusSnapshotInvalid, ri, si)
			}
			for label, value := range map[string]string{
				"FirstBusTime": sub.FirstBusTime, "LastBusTime": sub.LastBusTime,
				"HolidayFirstBusTime": sub.HolidayFirstBusTime, "HolidayLastBusTime": sub.HolidayLastBusTime,
			} {
				if value != "" && !validClock(value) {
					return nil, fmt.Errorf("%w: %s/%d %s=%q", errBusSnapshotInvalid, uid, dir, label, value)
				}
			}
			dep, dest := sub.DepartureStopNameZh, sub.DestinationStopNameZh
			if dep == "" {
				dep = route.DepartureStopNameZh
			}
			if dest == "" {
				dest = route.DestinationStopNameZh
			}
			if sub.Direction == 1 {
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
				if existing.RouteUID != route.RouteUID || existing.RouteName != route.RouteName.Zhtw || existing.SubRouteName != sub.SubRouteName.Zhtw {
					return nil, fmt.Errorf("%w: canonical route %s has divergent route/name variants", errBusSnapshotConflict, uid)
				}
				for _, op := range ops {
					existing.Operators = appendUniqueOperator(existing.Operators, op)
				}
			}
			if prior := existing.Directions[int32(dir)]; prior != nil && !proto.Equal(prior, candidate) {
				return nil, fmt.Errorf("%w: canonical route %s direction %d has divergent route variants", errBusSnapshotConflict, uid, dir)
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
						return nil, fmt.Errorf("%w: native subroute %s maps to both %s and %s", errBusSnapshotConflict, native, mapped, uid)
					}
					nativeToCanonical[native] = uid
				}
			}
		}
	}
	if len(snapshot.subroutes) == 0 {
		return nil, fmt.Errorf("%w: Route produced zero canonical subroutes", errBusSnapshotInvalid)
	}
	for _, sub := range snapshot.subroutes {
		sort.Slice(sub.Operators, func(i, j int) bool {
			return sub.Operators[i].OperatorId < sub.Operators[j].OperatorId
		})
		if outbound := sub.Directions[0]; outbound != nil {
			sub.DepartureStopName = outbound.DepartureStopName
			sub.DestinationStopName = outbound.DestinationStopName
		} else if inbound := sub.Directions[1]; inbound != nil {
			sub.DepartureStopName = inbound.DepartureStopName
			sub.DestinationStopName = inbound.DestinationStopName
		}
	}

	var stopVariants []rawStopofroute
	stopBody, err := readBusRawDataset(ctx, src, city, "bus_stopofroute")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(stopBody, &stopVariants); err != nil {
		return nil, fmt.Errorf("%w: StopOfRoute: %v", errBusSnapshotInvalid, err)
	}
	seenStops := make(map[string]rawStopofroute)
	for i, variant := range stopVariants {
		uid, dir := shared.CanonicalSubroute(city, variant.SubRouteUID, variant.Direction)
		direction := directionFor(snapshot.subroutes, uid, dir)
		if direction == nil {
			return nil, fmt.Errorf("%w: StopOfRoute[%d] references unknown %s/%d", errBusSnapshotInvalid, i, uid, dir)
		}
		if len(variant.Stops) == 0 {
			return nil, fmt.Errorf("%w: StopOfRoute[%d] has no stops", errBusSnapshotInvalid, i)
		}
		lastSequence := uint8(0)
		for j, stop := range variant.Stops {
			if strings.TrimSpace(stop.StopUID) == "" || strings.TrimSpace(stop.StopName.Zhtw) == "" || strings.TrimSpace(stop.StationID) == "" || stop.StopSequence == 0 || !validPosition(stop.StopPosition.PositionLon, stop.StopPosition.PositionLat) {
				return nil, fmt.Errorf("%w: StopOfRoute[%d].Stops[%d] has invalid identity/sequence/position", errBusSnapshotInvalid, i, j)
			}
			if stop.StopSequence <= lastSequence {
				return nil, fmt.Errorf("%w: StopOfRoute[%d] stop sequence %d is not strictly increasing", errBusSnapshotInvalid, i, stop.StopSequence)
			}
			lastSequence = stop.StopSequence
		}
		key := fmt.Sprintf("%s/%d", uid, dir)
		if prior, ok := seenStops[key]; ok {
			if !jsonSemanticEqual(prior.Stops, variant.Stops) {
				return nil, fmt.Errorf("%w: %s has divergent StopOfRoute variants", errBusSnapshotConflict, key)
			}
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
	for uid, sub := range snapshot.subroutes {
		for dir, direction := range sub.Directions {
			if len(direction.Stops) == 0 {
				return nil, fmt.Errorf("%w: canonical route %s/%d has no StopOfRoute", errBusSnapshotInvalid, uid, dir)
			}
		}
	}

	var shapes []rawBusShape
	shapeBody, err := readBusRawDataset(ctx, src, city, "bus_shape")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(shapeBody, &shapes); err != nil {
		return nil, fmt.Errorf("%w: Shape: %v", errBusSnapshotInvalid, err)
	}
	seenShapes := make(map[string]string)
	for i, shape := range shapes {
		if strings.TrimSpace(shape.Geometry) == "" {
			return nil, fmt.Errorf("%w: Shape[%d] has empty Geometry", errBusSnapshotInvalid, i)
		}
		var targets []string
		if shape.SubRouteUID != "" {
			uid, _ := shared.CanonicalSubroute(city, shape.SubRouteUID, shape.Direction)
			targets = []string{uid}
		} else {
			for uid := range routeToCanonical[shape.RouteUID] {
				targets = append(targets, uid)
			}
		}
		if len(targets) == 0 {
			return nil, fmt.Errorf("%w: Shape[%d] references unknown route", errBusSnapshotInvalid, i)
		}
		for _, uid := range targets {
			_, dir := shared.CanonicalSubroute(city, shape.SubRouteUID, shape.Direction)
			direction := directionFor(snapshot.subroutes, uid, dir)
			if direction == nil {
				return nil, fmt.Errorf("%w: Shape[%d] references unknown %s/%d", errBusSnapshotInvalid, i, uid, dir)
			}
			key := fmt.Sprintf("%s/%d", uid, dir)
			if prior, ok := seenShapes[key]; ok && prior != shape.Geometry {
				return nil, fmt.Errorf("%w: %s has divergent Shape variants", errBusSnapshotConflict, key)
			}
			seenShapes[key] = shape.Geometry
			direction.Geometry = shape.Geometry
		}
	}

	var schedules []rawBusSchedule
	scheduleBody, err := readBusRawDataset(ctx, src, city, "bus_schedule")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(scheduleBody, &schedules); err != nil {
		return nil, fmt.Errorf("%w: Schedule: %v", errBusSnapshotInvalid, err)
	}
	seenSchedules := make(map[string]rawBusSchedule)
	for i, schedule := range schedules {
		uid, dir := shared.CanonicalSubroute(city, schedule.SubRouteUID, schedule.Direction)
		direction := directionFor(snapshot.subroutes, uid, dir)
		if direction == nil {
			return nil, fmt.Errorf("%w: Schedule[%d] references unknown %s/%d", errBusSnapshotInvalid, i, uid, dir)
		}
		key := fmt.Sprintf("%s/%d", uid, dir)
		if prior, ok := seenSchedules[key]; ok {
			if !jsonSemanticEqual(prior, schedule) {
				return nil, fmt.Errorf("%w: %s has divergent Schedule variants", errBusSnapshotConflict, key)
			}
			continue
		}
		seenSchedules[key] = schedule
		rows, modelRows, err := buildScheduleRows(uid, dir, schedule)
		if err != nil {
			return nil, fmt.Errorf("%w: Schedule[%d]: %v", errBusSnapshotInvalid, i, err)
		}
		snapshot.scheduleRows = append(snapshot.scheduleRows, rows...)
		direction.Schedules = append(direction.Schedules, modelRows...)
	}

	var stations []rawBusStation
	stationBody, err := readBusRawDataset(ctx, src, city, "bus_station")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(stationBody, &stations); err != nil {
		return nil, fmt.Errorf("%w: Station: %v", errBusSnapshotInvalid, err)
	}
	stationUIDs := make(map[string]struct{}, len(stations))
	stationIDs := make(map[string]string, len(stations))
	stationsByUID := make(map[string]rawBusStation, len(stations))
	for i, station := range stations {
		if station.StationUID == "" || station.StationID == "" || station.StationName.Zhtw == "" || !validPosition(station.StationPosition.PositionLon, station.StationPosition.PositionLat) {
			return nil, fmt.Errorf("%w: Station[%d] has invalid identity/position", errBusSnapshotInvalid, i)
		}
		if prior, exists := stationsByUID[station.StationUID]; exists {
			if !jsonSemanticEqual(prior, station) {
				return nil, fmt.Errorf("%w: StationUID %s has divergent variants", errBusSnapshotConflict, station.StationUID)
			}
			continue
		}
		if priorUID := stationIDs[station.StationID]; priorUID != "" && priorUID != station.StationUID {
			return nil, fmt.Errorf("%w: StationID %s maps to both %s and %s", errBusSnapshotConflict, station.StationID, priorUID, station.StationUID)
		}
		stationsByUID[station.StationUID] = station
		stationUIDs[station.StationUID] = struct{}{}
		stationIDs[station.StationID] = station.StationUID
		snapshot.stationRows = append(snapshot.stationRows, []any{
			station.StationUID, station.StationID, station.StationName.Zhtw,
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
						return nil, fmt.Errorf("%w: route %s stop %s references missing station %s", errBusSnapshotInvalid, uid, stop.StopUID, stop.StationID)
					}
				}
			}
		}
	}

	var groups []rawBusStationGroup
	groupBody, err := readBusRawDataset(ctx, src, city, "bus_stationgroup")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(groupBody, &groups); err != nil {
		return nil, fmt.Errorf("%w: StationGroup: %v", errBusSnapshotInvalid, err)
	}
	groupsByID := make(map[string]rawBusStationGroup)
	groupsByUID := make(map[string]rawBusStationGroup)
	for i, group := range groups {
		if group.StationGroupUID == "" || group.StationGroupID == "" || group.StationGroupName.Zhtw == "" || !validPosition(group.StationGroupPosition.PositionLon, group.StationGroupPosition.PositionLat) {
			return nil, fmt.Errorf("%w: StationGroup[%d] has invalid identity/position", errBusSnapshotInvalid, i)
		}
		if prior, ok := groupsByID[group.StationGroupID]; ok && !jsonSemanticEqual(prior, group) {
			return nil, fmt.Errorf("%w: StationGroupID %s has divergent UID/payload", errBusSnapshotConflict, group.StationGroupID)
		}
		if prior, ok := groupsByUID[group.StationGroupUID]; ok {
			if !jsonSemanticEqual(prior, group) {
				return nil, fmt.Errorf("%w: StationGroupUID %s has divergent variants", errBusSnapshotConflict, group.StationGroupUID)
			}
			continue
		}
		groupsByID[group.StationGroupID] = group
		groupsByUID[group.StationGroupUID] = group
		snapshot.groupRows = append(snapshot.groupRows, []any{
			group.StationGroupUID, group.StationGroupID, group.StationGroupName.Zhtw,
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
		groupUID := ""
		if group, ok := groupsByID[station.StationGroupID]; ok {
			groupUID = group.StationGroupUID
		} else {
			groupUID = manualGroupUID(city, station.StationName.Zhtw)
			aggregate := manualGroups[groupUID]
			if aggregate == nil {
				aggregate = &manualGroupAggregate{name: station.StationName.Zhtw}
				manualGroups[groupUID] = aggregate
			}
			aggregate.lonSum += station.StationPosition.PositionLon
			aggregate.latSum += station.StationPosition.PositionLat
			aggregate.stationCnt++
		}
		snapshot.memberRows = append(snapshot.memberRows, []any{
			station.StationUID, groupUID, station.StationID, station.StationName.Zhtw,
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
	fareBody, err := readBusRawDataset(ctx, src, city, "bus_routefare")
	if err != nil {
		return nil, err
	}
	if err := decodeStrictJSONArray(fareBody, &fares); err != nil {
		return nil, fmt.Errorf("%w: RouteFare: %v", errBusSnapshotInvalid, err)
	}
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
			return nil, fmt.Errorf("%w: RouteFare[%d] cannot map native route/subroute IDs", errBusSnapshotInvalid, i)
		}
		for _, uid := range uniqueStrings(targets) {
			fareCandidates[uid] = append(fareCandidates[uid], fare)
		}
	}
	for uid, candidates := range fareCandidates {
		for _, candidate := range candidates[1:] {
			if !proto.Equal(candidates[0], candidate) {
				return nil, fmt.Errorf("%w: canonical route %s has divergent fare offers; current wire model stores one fare", errBusSnapshotConflict, uid)
			}
		}
		snapshot.subroutes[uid].Fare = cloneBusFare(candidates[0])
	}

	if err := snapshot.buildWriteRows(); err != nil {
		return nil, err
	}
	return snapshot, nil
}

func readBusRawDataset(ctx context.Context, src loadSource, city, table string) ([]byte, error) {
	body, fetchedAt, err := src.datasetJSON(ctx, table, "city", city)
	if err != nil {
		return nil, fmt.Errorf("%w: %s/%s read: %w", errBusSnapshotIncomplete, table, city, err)
	}
	if fetchedAt.IsZero() || isStale(fetchedAt) {
		return nil, fmt.Errorf("%w: %s/%s landing state fetched_at=%s", errBusSnapshotIncomplete, table, city, fetchedAt.Format(time.RFC3339))
	}
	if len(bytes.TrimSpace(body)) == 0 {
		return nil, fmt.Errorf("%w: %s/%s has empty JSON body", errBusSnapshotInvalid, table, city)
	}
	return body, nil
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
			return fmt.Errorf("%w: marshal %s protobuf: %v", errBusSnapshotInvalid, uid, err)
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
				return fmt.Errorf("%w: marshal %s/%d stops: %v", errBusSnapshotInvalid, uid, dir, err)
			}
			schedules, err := json.Marshal(direction.Schedules)
			if err != nil {
				return fmt.Errorf("%w: marshal %s/%d schedules: %v", errBusSnapshotInvalid, uid, dir, err)
			}
			ops := make([]busOperatorJSON, 0, len(sub.Operators))
			for _, op := range sub.Operators {
				ops = append(ops, busOperatorJSON{ID: op.OperatorId, Name: op.OperatorName, Phone: op.OperatorPhone, URL: op.OperatorUrl})
			}
			operators, err := json.Marshal(ops)
			if err != nil {
				return fmt.Errorf("%w: marshal %s operators: %v", errBusSnapshotInvalid, uid, err)
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

func buildScheduleRows(uid string, dir uint8, schedule rawBusSchedule) ([][]any, []*models.Bus_Schedule, error) {
	var rows [][]any
	var modelRows []*models.Bus_Schedule
	for _, timetable := range schedule.Timetables {
		if timetable.TripID == "" {
			return nil, nil, errors.New("timetable has empty TripID")
		}
		service := mask2(timetable.ServiceDay.Monday, timetable.ServiceDay.Tuesday, timetable.ServiceDay.Wednesday, timetable.ServiceDay.Thursday, timetable.ServiceDay.Friday, timetable.ServiceDay.Saturday, timetable.ServiceDay.Sunday)
		for _, stop := range timetable.StopTimes {
			if stop.StopSequence <= 0 || stop.StopUID == "" || stop.StopName.Zhtw == "" || !validClock(stop.ArrivalTime) || !validClock(stop.DepartureTime) {
				return nil, nil, fmt.Errorf("trip %s has invalid stop identity/sequence/time", timetable.TripID)
			}
			rows = append(rows, []any{uid, int16(dir), false, timetable.TripID, timetable.IsLowFloor, int16(stop.StopSequence), stop.StopUID, stop.StopName.Zhtw, stop.ArrivalTime, stop.DepartureTime, int16(service)})
			modelRows = append(modelRows, &models.Bus_Schedule{
				IsTimetable: true, Tripid: timetable.TripID, Islowfloor: timetable.IsLowFloor,
				MinHeadwayMinsArrivalTime: stop.ArrivalTime, MaxHeadwayMinsDepartureTime: stop.DepartureTime,
				ServiceDay: int32(service),
			})
		}
	}
	for _, frequency := range schedule.Frequencys {
		if !validClock(frequency.StartTime) || !validClock(frequency.EndTime) || frequency.MinHeadwayMins == 0 || frequency.MaxHeadwayMins < frequency.MinHeadwayMins {
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
	if err := dec.Decode(&trailing); err == nil {
		return errors.New("trailing JSON value")
	}
	return nil
}

func validClock(value string) bool {
	_, err := time.Parse("15:04", value)
	return err == nil
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
