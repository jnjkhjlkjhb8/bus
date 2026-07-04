package main

import (
	"bytes"
	"context"
	"encoding/json"
	"strconv"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"google.golang.org/protobuf/proto"
)

// busStatic is the daily static-ingestion entry point for buses: it rebuilds
// subroutes/stops/schedules in PostgreSQL (dailyRoute) and refreshes the Redis
// daily-timetable cache (busDailyroute). It always returns nil; per-city and
// per-step failures are logged inside those calls, not surfaced here.
func busStatic(ctx context.Context, client *resty.Client, rc *redis.Client, db *pgxpool.Pool) error {
	dailyRoute(ctx, rc, client, db)
	busDailyroute(client, rc)
	return nil
}

// loadBus reproduces dailyRoute for one city from raw_tdx instead of live TDX.
// It reads the six correlated bus datasets (Route, StopOfRoute, Shape, Schedule,
// Station, StationGroup) for the city from src — a single decoder cannot feed a
// multi-endpoint correlation, so the loadSpec hands loadBus the source rather
// than one decoder. It stages raw_bus_route (the temp_bus->raw_bus_route
// COPY/upsert byte-identical to processStatic) and drives the identical in-memory
// assembly, then calls the dailyRoute-family upserts (changetodbformat,
// savestations, saveStationGroups, saveschedule, savestatictodb) unchanged.
//
// Operator and fare enrichment mirrors dailyRoute exactly: operators are read
// before the Route assembly (from raw_tdx.bus_operator via loadBusOperators,
// falling back to the stored bus_operators rows like the legacy TDX-failure
// path) and used inside the Route closure; fares (raw_tdx.bus_routefare via
// loadBusFares) are applied after the StationGroup stage, before
// changetodbformat.
func loadBus(ctx context.Context, src loadSource, db *pgxpool.Pool, rc *redis.Client, city string) error {
	if city == "LienchiangCounty" {
		return nil
	}
	log.Infof("[LOAD] action=bus event=city_start city=%s", city)
	clearBusStaticCache(rc, city)
	opMap := loadBusOperatorMap(ctx, src, db, city)
	subRoutemap := make(map[string]*models.BusSubroute)
	routeMap := make(map[string][]string)
	syncStart := time.Now()
	if _, err := db.Exec(ctx, "DELETE FROM raw_bus_route WHERE destin = $1 OR depart = $1", city); err != nil {
		log.Infof("[LOAD] action=bus city=%s event=cleanup_error error=%v", city, err)
	}

	// Route assembly + staging. If no Route data landed, skip the city (matches
	// dailyRoute's no_route_data guard).
	routeFetched := loadBusStage(ctx, src, db, city, "bus_route", "Route", func(raw []byte) {
		var r rawBusRoute
		if err := json.Unmarshal(raw, &r); err != nil {
			log.Infof("[LOAD] action=bus city=%s api=Route event=unmarshal_error error=%v", city, err)
		}
		var ops []*models.BusOperator
		for _, op := range r.Operators {
			if detail, ok := opMap[op.OperatorID]; ok {
				ops = append(ops, &models.BusOperator{
					OperatorId:    detail.OperatorID,
					OperatorName:  detail.OperatorName.Zhtw,
					OperatorPhone: detail.OperatorPhone,
					OperatorUrl:   detail.OperatorUrl,
				})
			}
		}
		for _, sub := range r.SubRoutes {
			uid, dir := makethatsame(city, sub.SubRouteUID, sub.Direction)
			dep, dest := sub.DepartureStopNameZh, sub.DestinationStopNameZh
			if dep == "" {
				dep = r.DepartureStopNameZh
			}
			if dest == "" {
				dest = r.DestinationStopNameZh
			}
			if sub.Direction == 1 {
				dep, dest = dest, dep
			}
			if _, ok := subRoutemap[uid]; !ok {
				subRoutemap[uid] = &models.BusSubroute{
					RouteUID:            r.RouteUID,
					RouteName:           r.RouteName.Zhtw,
					SubRouteUID:         uid,
					SubRouteName:        sub.SubRouteName.Zhtw,
					City:                city,
					DepartureStopName:   dep,
					DestinationStopName: dest,
					Directions:          make(map[int32]*models.Direction),
					Operators:           ops,
				}
			}
			subRoutemap[uid].Directions[int32(dir)] = &models.Direction{
				DepartureStopName:   dep,
				DestinationStopName: dest,
				FirstBusTime:        sub.FirstBusTime,
				LastBusTime:         sub.LastBusTime,
				HolidayFirstBusTime: sub.HolidayFirstBusTime,
				HolidayLastBusTime:  sub.HolidayLastBusTime,
			}
			routeMap[r.RouteUID] = append(routeMap[r.RouteUID], uid)
		}
	})
	if !routeFetched {
		log.Infof("[LOAD] action=bus city=%s event=city_skip reason=no_route_data", city)
		return nil
	}

	loadBusStage(ctx, src, db, city, "bus_stopofroute", "StopOfRoute", func(raw []byte) {
		var r rawStopofroute
		if err := json.Unmarshal(raw, &r); err != nil {
			log.Infof("[LOAD] action=bus city=%s api=StopOfRoute event=unmarshal_error error=%v", city, err)
		}
		uid, dir := makethatsame(city, r.SubRouteUID, r.Direction)
		if sr, ok := subRoutemap[uid]; ok {
			if d, ok := sr.Directions[int32(dir)]; ok {
				for _, stop := range r.Stops {
					d.Stops = append(d.Stops, &models.BusStop{
						StopName:     stop.StopName.Zhtw,
						StopSequence: int32(stop.StopSequence),
						PositionLat:  stop.StopPosition.PositionLat,
						PositionLon:  stop.StopPosition.PositionLon,
						StationID:    stop.StationID,
						StopUID:      stop.StopUID,
					})
				}
			}
		}
	})
	loadBusStage(ctx, src, db, city, "bus_shape", "Shape", func(raw []byte) {
		var r rawBusShape
		if err := json.Unmarshal(raw, &r); err != nil {
			log.Infof("[LOAD] action=bus city=%s api=Shape event=unmarshal_error error=%v", city, err)
		}
		if r.SubRouteUID != "" {
			uid, dir := makethatsame(city, r.SubRouteUID, r.Direction)
			if sr, ok := subRoutemap[uid]; ok {
				if d, ok := sr.Directions[int32(dir)]; ok {
					d.Geometry = r.Geometry
				}
			}
		} else if subUIDs, exists := routeMap[r.RouteUID]; exists {
			for _, uid := range subUIDs {
				if sr, ok := subRoutemap[uid]; ok {
					if d, ok := sr.Directions[int32(r.Direction)]; ok {
						d.Geometry = r.Geometry
					}
				}
			}
		}
	})
	loadBusStage(ctx, src, db, city, "bus_schedule", "Schedule", func(raw []byte) {
		var r rawBusSchedule
		if err := json.Unmarshal(raw, &r); err != nil {
			log.Infof("[LOAD] action=bus city=%s api=Schedule event=unmarshal_error error=%v", city, err)
		}
		uid, dir := makethatsame(city, r.SubRouteUID, r.Direction)
		if sr, ok := subRoutemap[uid]; ok {
			if d, ok := sr.Directions[int32(dir)]; ok {
				for _, t := range r.Timetables {
					m := mask2(t.ServiceDay.Monday, t.ServiceDay.Tuesday, t.ServiceDay.Wednesday, t.ServiceDay.Thursday, t.ServiceDay.Friday, t.ServiceDay.Saturday, t.ServiceDay.Sunday)
					for _, temp := range t.StopTimes {
						d.Schedules = append(d.Schedules, &models.Bus_Schedule{
							Type:                        true,
							Tripid:                      t.TripID,
							Islowfloor:                  t.IsLowFloor,
							MinHeadwayMinsArrivalTime:   temp.ArrivalTime,
							MaxHeadwayMinsDepartureTime: temp.DepartureTime,
							ServiceDay:                  int32(m),
						})
					}
				}
				for _, t := range r.Frequencys {
					m := mask2(t.ServiceDay.Monday, t.ServiceDay.Tuesday, t.ServiceDay.Wednesday, t.ServiceDay.Thursday, t.ServiceDay.Friday, t.ServiceDay.Saturday, t.ServiceDay.Sunday)
					d.Schedules = append(d.Schedules, &models.Bus_Schedule{
						Type:                        false,
						Start_Time:                  t.StartTime,
						End_Time:                    t.EndTime,
						MinHeadwayMinsArrivalTime:   strconv.Itoa(int(t.MinHeadwayMins)),
						MaxHeadwayMinsDepartureTime: strconv.Itoa(int(t.MaxHeadwayMins)),
						ServiceDay:                  int32(m),
					})
				}
			}
		}
	})
	loadBusStage(ctx, src, db, city, "bus_station", "Station", func(raw []byte) {})
	loadBusStage(ctx, src, db, city, "bus_stationgroup", "StationGroup", func(raw []byte) {})
	fareBySub, fareByRoute := loadBusFareMaps(ctx, src, city)
	for uid, sub := range subRoutemap {
		if f, ok := fareBySub[uid]; ok {
			sub.Fare = cloneBusFare(f, uid)
		} else if f, ok := fareByRoute[sub.RouteUID]; ok {
			sub.Fare = cloneBusFare(f, uid)
		}
	}
	changetodbformat(ctx, db, &subRoutemap)
	savestations(ctx, db, city)
	saveStationGroups(ctx, db, city, syncStart)
	saveschedule(ctx, db, city)
	if _, delErr := db.Exec(ctx, `DELETE FROM bus_station_stop_map WHERE sub_route_uid LIKE $1`, citymap[city]+"%"); delErr != nil {
		log.Infof("[LOAD] action=bus city=%s event=delete_stop_map_error error=%v", city, delErr)
	}
	savestatictodb(ctx, db, &subRoutemap)
	if _, delErr := db.Exec(ctx, `DELETE FROM bus_subroutes WHERE city = $1 AND updated_at < $2`, city, syncStart); delErr != nil {
		log.Infof("[LOAD] action=bus city=%s event=delete_stale_subroutes_error error=%v", city, delErr)
	}
	if _, delErr := db.Exec(ctx, `DELETE FROM bus_static WHERE city = $1 AND updated_at < $2`, city, syncStart); delErr != nil {
		log.Infof("[LOAD] action=bus city=%s event=delete_stale_static_error error=%v", city, delErr)
	}
	invalidateBusStaticMap()
	log.Infof("[LOAD] action=bus event=city_complete city=%s subroute_count=%d", city, len(subRoutemap))
	return nil
}

// loadBusOperatorMap reads a city's operators from raw_tdx.bus_operator and
// hands them to loadBusOperators (which also upserts bus_operators, SQL
// byte-identical to the legacy body). When the raw read fails it falls back to
// the previously stored bus_operators rows — the same degradation dailyRoute
// gets when the TDX operator fetch fails.
func loadBusOperatorMap(ctx context.Context, src loadSource, db *pgxpool.Pool, city string) map[string]rawBusOperator {
	body, _, err := src.datasetJSON(ctx, "bus_operator", "city", city)
	if err != nil {
		log.Infof("[LOAD] action=bus city=%s api=Operator event=read_error error=%v", city, err)
		return busOperatorsFromDB(ctx, db, city)
	}
	result, loadErr := loadBusOperators(ctx, json.NewDecoder(bytes.NewReader(body)), db, city)
	if loadErr != nil && len(result) == 0 {
		return busOperatorsFromDB(ctx, db, city)
	}
	return result
}

// loadBusFareMaps reads a city's route fares from raw_tdx.bus_routefare and
// parses them with loadBusFares into the same two lookups cityFares returns.
// On a read or decode failure it returns nil, nil — the same shape the legacy
// cityFares yields on a fetch failure (subroutes then load without fares).
func loadBusFareMaps(ctx context.Context, src loadSource, city string) (map[string]*models.Bus_Fare, map[string]*models.Bus_Fare) {
	body, _, err := src.datasetJSON(ctx, "bus_routefare", "city", city)
	if err != nil {
		log.Infof("[LOAD] action=bus city=%s api=RouteFare event=read_error error=%v", city, err)
		return nil, nil
	}
	bySub, byRoute, loadErr := loadBusFares(json.NewDecoder(bytes.NewReader(body)), city)
	if loadErr != nil {
		return nil, nil
	}
	return bySub, byRoute
}

// loadBusStage reads one bus dataset for a city from raw_tdx, invokes processer
// on each element for in-memory accumulation, and stages the route-shaped rows
// into raw_bus_route. It mirrors processStatic's per-api row layout and the
// temp_bus->raw_bus_route COPY/upsert byte-identical, but reads from src instead
// of TDX. It returns true when any element was processed.
func loadBusStage(ctx context.Context, src loadSource, db *pgxpool.Pool, city, table, api string, processer func([]byte)) bool {
	body, _, err := src.datasetJSON(ctx, table, "city", city)
	if err != nil {
		log.Infof("[LOAD] action=bus city=%s api=%s event=read_error error=%v", city, api, err)
		return false
	}
	var elems []json.RawMessage
	if err := json.Unmarshal(body, &elems); err != nil {
		log.Infof("[LOAD] action=bus city=%s api=%s event=decode_error error=%v", city, api, err)
		return false
	}
	if len(elems) == 0 {
		return false
	}
	var rawRows [][]interface{}
	for _, raw := range elems {
		processer(raw)
		switch api {
		case "Route":
			var r rawBusRoute
			if err := json.Unmarshal(raw, &r); err != nil {
				log.Infof("[LOAD] action=bus city=%s api=%s event=unmarshal_error error=%v", city, api, err)
			}
			for _, sub := range r.SubRoutes {
				dep, dest := sub.DepartureStopNameZh, sub.DestinationStopNameZh
				if dep == "" {
					dep = r.DepartureStopNameZh
				}
				if dest == "" {
					dest = r.DestinationStopNameZh
				}
				uid, dir := makethatsame(city, sub.SubRouteUID, sub.Direction)
				rawRows = append(rawRows, []interface{}{
					uid, dir, r.RouteUID, r.RouteName.Zhtw, sub.SubRouteName.Zhtw, dep, dest, api, raw,
				})
			}
		case "StopOfRoute":
			var s rawStopofroute
			if err := json.Unmarshal(raw, &s); err != nil {
				log.Infof("[LOAD] action=bus city=%s api=%s event=unmarshal_error error=%v", city, api, err)
			}
			uid, dir := makethatsame(city, s.SubRouteUID, s.Direction)
			rawRows = append(rawRows, []interface{}{
				uid, dir, s.RouteUID, "", "", "", city, api, raw,
			})
		case "Shape":
			var s rawBusShape
			if err := json.Unmarshal(raw, &s); err != nil {
				log.Infof("[LOAD] action=bus city=%s api=%s event=unmarshal_error error=%v", city, api, err)
			}
			var uid string
			var dir uint8
			if s.SubRouteUID == "" {
				uid, dir = makethatsame(city, s.RouteUID, s.Direction)
			} else {
				uid, dir = makethatsame(city, s.SubRouteUID, s.Direction)
			}
			rawRows = append(rawRows, []interface{}{
				uid, dir, s.RouteUID, "", "", "", city, api, raw,
			})
		case "Schedule":
			var t rawBusSchedule
			if err := json.Unmarshal(raw, &t); err != nil {
				log.Infof("[LOAD] action=bus city=%s api=%s event=unmarshal_error error=%v", city, api, err)
			}
			uid, dir := makethatsame(city, t.SubRouteUID, t.Direction)
			rawRows = append(rawRows, []interface{}{
				uid, dir, t.RouteUID, "", "", "", city, api, raw,
			})
		case "Station":
			var t rawBusStation
			if err := json.Unmarshal(raw, &t); err != nil {
				log.Infof("[LOAD] action=bus city=%s api=%s event=unmarshal_error error=%v", city, api, err)
			}
			rawRows = append(rawRows, []interface{}{
				t.StationUID, -1, t.StationID, t.StationName.Zhtw, "", city, "", api, raw,
			})
		case "StationGroup":
			var t rawBusStationGroup
			if err := json.Unmarshal(raw, &t); err != nil {
				log.Infof("[LOAD] action=bus city=%s api=%s event=unmarshal_error error=%v", city, api, err)
			}
			rawRows = append(rawRows, []interface{}{
				t.StationGroupUID, -1, t.StationGroupID, t.StationGroupName.Zhtw, "", city, "", api, raw,
			})
		}
	}
	if len(rawRows) > 0 {
		c1 := `CREATE TEMP TABLE temp_bus (
							sub_route_uid  text  not null,
							direction      smallint not null,
							route_uid      text  not null,
							route_name     text,
							sub_route_name text,
							depart         text,
							destin         text,
							type           text  not null,
							content        jsonb not null
				) ON COMMIT DROP;`
		c2 := `INSERT INTO raw_bus_route (
							sub_route_uid,
							direction,
							route_uid,
							route_name,
							sub_route_name,
							depart,
							destin,
							type,
							content,
							created_at
						)
						SELECT DISTINCT ON (sub_route_uid,direction,type) sub_route_uid, direction, route_uid, route_name,sub_route_name, depart,destin,type,content,NOW() FROM temp_bus
						ON CONFLICT (sub_route_uid,direction,type) DO UPDATE SET route_uid = EXCLUDED.route_uid,route_name = excluded.route_name,sub_route_name = EXCLUDED.sub_route_name,depart = excluded.depart,destin = excluded.destin,type = excluded.type,content = excluded.content,created_at = NOW();`
		b, err := db.Begin(ctx)
		if err != nil {
			log.Infof("[LOAD] action=bus city=%s api=%s event=begin_error error=%v", city, api, err)
			return false
		}
		defer func(b pgx.Tx, ctx context.Context) {
			_ = b.Rollback(ctx)
		}(b, ctx)
		if _, err := b.Exec(ctx, c1); err != nil {
			log.Infof("[LOAD] action=bus city=%s api=%s event=create_temp_error error=%v", city, api, err)
			return false
		}
		from, err := b.CopyFrom(ctx, pgx.Identifier{"temp_bus"}, []string{"sub_route_uid", "direction", "route_uid", "route_name", "sub_route_name", "depart", "destin", "type", "content"}, pgx.CopyFromRows(rawRows))
		if err == nil {
			if _, execErr := b.Exec(ctx, c2); execErr != nil {
				log.Infof("[LOAD] action=bus city=%s api=%s event=exec_error error=%v", city, api, execErr)
			}
			if commitErr := b.Commit(ctx); commitErr != nil {
				log.Infof("[LOAD] action=bus city=%s api=%s event=commit_error error=%v", city, api, commitErr)
			} else {
				log.Infof("[LOAD] action=bus city=%s api=%s event=success station_count=%d", city, api, from)
			}
		} else {
			log.Infof("[LOAD] action=bus city=%s api=%s event=copyfrom_error error=%v", city, api, err)
			_ = b.Rollback(ctx)
		}
	}
	return true
}

// dailyRoute rebuilds all bus static data city by city: routes, stops, shapes,
// schedules, stations, station groups, and fares are fetched, assembled into
// per-subroute protobufs, and written to bus_subroutes / bus_static and the
// station/group/schedule tables. A city is force-refetched when busCityComplete
// reports gaps. syncStart timestamps the run so rows not touched this pass are
// deleted as stale. The in-memory static-map cache is invalidated at the end.
func dailyRoute(ctx context.Context, rc *redis.Client, c *resty.Client, db *pgxpool.Pool) {
	log.Infof("[BUS] action=dailyRoute event=start")
	for _, city := range cities {
		if city == "LienchiangCounty" {
			continue
		}
		log.Infof("[BUS] action=dailyRoute city=%s event=city_start", city)
		forceAll := !busCityComplete(ctx, db, city)
		if forceAll {
			clearBusStaticCache(rc, city)
		}
		opMap := busOperators(ctx, c, rc, db, city)
		subRoutemap := make(map[string]*models.BusSubroute)
		routeMap := make(map[string][]string)
		syncStart := time.Now()
		_, err := db.Exec(ctx, "DELETE FROM raw_bus_route WHERE destin = $1 OR depart = $1", city)
		if err != nil {
			log.Infof("[BUS] action=dailyRoute city=%s event=cleanup_error error=%v", city, err)
		}
		routeFetched := processStatic(ctx, c, rc, db, city, "Route", forceAll, func(raw []byte) {
			var r rawBusRoute
			err := json.Unmarshal(raw, &r)
			if err != nil {
				log.Infof("[BUS] action=dailyRoute city=%s api=Route event=unmarshal_error error=%v", city, err)
			}
			var ops []*models.BusOperator
			for _, op := range r.Operators {
				if detail, ok := opMap[op.OperatorID]; ok {
					ops = append(ops, &models.BusOperator{
						OperatorId:    detail.OperatorID,
						OperatorName:  detail.OperatorName.Zhtw,
						OperatorPhone: detail.OperatorPhone,
						OperatorUrl:   detail.OperatorUrl,
					})
				}
			}
			for _, sub := range r.SubRoutes {
				uid, dir := makethatsame(city, sub.SubRouteUID, sub.Direction)
				dep, dest := sub.DepartureStopNameZh, sub.DestinationStopNameZh
				if dep == "" {
					dep = r.DepartureStopNameZh
				}
				if dest == "" {
					dest = r.DestinationStopNameZh
				}
				if sub.Direction == 1 {
					dep, dest = dest, dep
				}
				if _, ok := subRoutemap[uid]; !ok {
					subRoutemap[uid] = &models.BusSubroute{
						RouteUID:            r.RouteUID,
						RouteName:           r.RouteName.Zhtw,
						SubRouteUID:         uid,
						SubRouteName:        sub.SubRouteName.Zhtw,
						City:                city,
						DepartureStopName:   dep,
						DestinationStopName: dest,
						Directions:          make(map[int32]*models.Direction),
						Operators:           ops,
					}
				}
				subRoutemap[uid].Directions[int32(dir)] = &models.Direction{
					DepartureStopName:   dep,
					DestinationStopName: dest,
					FirstBusTime:        sub.FirstBusTime,
					LastBusTime:         sub.LastBusTime,
					HolidayFirstBusTime: sub.HolidayFirstBusTime,
					HolidayLastBusTime:  sub.HolidayLastBusTime,
				}
				routeMap[r.RouteUID] = append(routeMap[r.RouteUID], uid)
			}
		})
		if !routeFetched {
			log.Infof("[BUS] action=dailyRoute city=%s event=city_skip reason=no_route_data force=%t", city, forceAll)
			continue
		}
		clearBusStaticCache(rc, city)
		processStatic(ctx, c, rc, db, city, "StopOfRoute", true, func(raw []byte) {
			var r rawStopofroute
			err := json.Unmarshal(raw, &r)
			if err != nil {
				log.Infof("[BUS] action=dailyRoute city=%s api=StopOfRoute event=unmarshal_error error=%v", city, err)
			}
			uid, dir := makethatsame(city, r.SubRouteUID, r.Direction)
			if sr, ok := subRoutemap[uid]; ok {
				if d, ok := sr.Directions[int32(dir)]; ok {
					for _, stop := range r.Stops {
						d.Stops = append(d.Stops, &models.BusStop{
							StopName:     stop.StopName.Zhtw,
							StopSequence: int32(stop.StopSequence),
							PositionLat:  stop.StopPosition.PositionLat,
							PositionLon:  stop.StopPosition.PositionLon,
							StationID:    stop.StationID,
							StopUID:      stop.StopUID,
						})
					}
				}
			}
		})
		processStatic(ctx, c, rc, db, city, "Shape", true, func(raw []byte) {
			var r rawBusShape
			err := json.Unmarshal(raw, &r)
			if err != nil {
				log.Infof("[BUS] action=dailyRoute event=marshal_error error=%v\n", err)
			}
			if r.SubRouteUID != "" {
				uid, dir := makethatsame(city, r.SubRouteUID, r.Direction)
				if sr, ok := subRoutemap[uid]; ok {
					if d, ok := sr.Directions[int32(dir)]; ok {
						d.Geometry = r.Geometry
					}
				}
			} else if subUIDs, exists := routeMap[r.RouteUID]; exists {
				for _, uid := range subUIDs {
					if sr, ok := subRoutemap[uid]; ok {
						if d, ok := sr.Directions[int32(r.Direction)]; ok {
							d.Geometry = r.Geometry
						}
					}
				}
			}
		})
		processStatic(ctx, c, rc, db, city, "Schedule", true, func(raw []byte) {
			var r rawBusSchedule
			err := json.Unmarshal(raw, &r)
			if err != nil {
				log.Infof("[BUS] action=dailyRoute city=%s api=Schedule event=unmarshal_error error=%v", city, err)
			}
			uid, dir := makethatsame(city, r.SubRouteUID, r.Direction)
			if sr, ok := subRoutemap[uid]; ok {
				if d, ok := sr.Directions[int32(dir)]; ok {
					for _, t := range r.Timetables {
						m := mask2(t.ServiceDay.Monday, t.ServiceDay.Tuesday, t.ServiceDay.Wednesday, t.ServiceDay.Thursday, t.ServiceDay.Friday, t.ServiceDay.Saturday, t.ServiceDay.Sunday)
						for _, temp := range t.StopTimes {
							d.Schedules = append(d.Schedules, &models.Bus_Schedule{
								Type:                        true,
								Tripid:                      t.TripID,
								Islowfloor:                  t.IsLowFloor,
								MinHeadwayMinsArrivalTime:   temp.ArrivalTime,
								MaxHeadwayMinsDepartureTime: temp.DepartureTime,
								ServiceDay:                  int32(m),
							})
						}
					}
					for _, t := range r.Frequencys {
						m := mask2(t.ServiceDay.Monday, t.ServiceDay.Tuesday, t.ServiceDay.Wednesday, t.ServiceDay.Thursday, t.ServiceDay.Friday, t.ServiceDay.Saturday, t.ServiceDay.Sunday)
						d.Schedules = append(d.Schedules, &models.Bus_Schedule{
							Type:                        false,
							Start_Time:                  t.StartTime,
							End_Time:                    t.EndTime,
							MinHeadwayMinsArrivalTime:   strconv.Itoa(int(t.MinHeadwayMins)),
							MaxHeadwayMinsDepartureTime: strconv.Itoa(int(t.MaxHeadwayMins)),
							ServiceDay:                  int32(m),
						})
					}
				}
			}
		})
		processStatic(ctx, c, rc, db, city, "Station", true, func(raw []byte) {})
		processStatic(ctx, c, rc, db, city, "StationGroup", true, func(raw []byte) {})
		fareBySub, fareByRoute := cityFares(ctx, c, rc, city)
		for uid, sub := range subRoutemap {
			if f, ok := fareBySub[uid]; ok {
				sub.Fare = cloneBusFare(f, uid)
			} else if f, ok := fareByRoute[sub.RouteUID]; ok {
				sub.Fare = cloneBusFare(f, uid)
			}
		}
		changetodbformat(ctx, db, &subRoutemap)
		savestations(ctx, db, city)
		saveStationGroups(ctx, db, city, syncStart)
		saveschedule(ctx, db, city)
		if _, delErr := db.Exec(ctx, `DELETE FROM bus_station_stop_map WHERE sub_route_uid LIKE $1`, citymap[city]+"%"); delErr != nil {
			log.Infof("[BUS] action=dailyRoute city=%s event=delete_stop_map_error error=%v", city, delErr)
		}
		savestatictodb(ctx, db, &subRoutemap)
		if _, delErr := db.Exec(ctx, `DELETE FROM bus_subroutes WHERE city = $1 AND updated_at < $2`, city, syncStart); delErr != nil {
			log.Infof("[BUS] action=dailyRoute city=%s event=delete_stale_subroutes_error error=%v", city, delErr)
		}
		if _, delErr := db.Exec(ctx, `DELETE FROM bus_static WHERE city = $1 AND updated_at < $2`, city, syncStart); delErr != nil {
			log.Infof("[BUS] action=dailyRoute city=%s event=delete_stale_static_error error=%v", city, delErr)
		}
		if err != nil {
			log.Infof("[BUS] action=dailyRoute city=%s event=cleanup_raw_error error=%v", city, err)
		}
		log.Infof("[BUS] action=dailyRoute city=%s event=city_complete subroute_count=%d", city, len(subRoutemap))
	}
	invalidateBusStaticMap()
	log.Infof("[BUS] action=dailyRoute event=complete")
}

// changetodbformat flattens the assembled subroute map into rows (stops,
// schedules, and operators marshaled to jsonb) and upserts them into
// bus_subroutes via a temp-table COPY (busSubroutesUpsertSQL). Errors are logged;
// a failed transaction is rolled back and the function returns.
func changetodbformat(ctx context.Context, db *pgxpool.Pool, raw *map[string]*models.BusSubroute) {
	row := [][]interface{}{}
	for _, sub := range *raw {
		for dir, d := range sub.Directions {
			stops, err := json.Marshal(d.Stops)
			schedules, err := json.Marshal(d.Schedules)
			if err != nil {
				log.Infof("[BUS] action=changetodbformat event=marshal_error error=%v", err)
			}
			var opJSON []busOperatorJSON
			for _, op := range sub.Operators {
				opJSON = append(opJSON, busOperatorJSON{
					ID:    op.OperatorId,
					Name:  op.OperatorName,
					Phone: op.OperatorPhone,
					URL:   op.OperatorUrl,
				})
			}
			operators, _ := json.Marshal(opJSON)
			row = append(row, []interface{}{
				sub.SubRouteUID,
				sub.RouteUID,
				dir,
				sub.RouteName,
				sub.SubRouteName,
				sub.City,
				d.DepartureStopName,
				d.DestinationStopName,
				d.Geometry,
				stops,
				schedules,
				operators,
			})
		}
	}
	b, err := db.Begin(ctx)
	if err != nil {
		log.Infof("[BUS] action=changetodbformat event=begin_error error=%v", err)
		return
	}
	defer func() {
		_ = b.Rollback(ctx)
	}()
	c1 := `
			CREATE TEMP TABLE temp_bus (
    		uid text,
    		rid text,
			d int,
			name1 text,
			name2 text,
			city text,
			depart text,
			destin text,
			geom text,
    		rawstop jsonb,
			schedule jsonb,
			operators jsonb
                          ) ON COMMIT DROP
		    `
	c2 := busSubroutesUpsertSQL
	if _, err := b.Exec(ctx, c1); err != nil {
		log.Infof("[BUS] action=changetodbformat event=create_temp_error error=%v", err)
	}
	if _, err := b.CopyFrom(ctx, pgx.Identifier{"temp_bus"}, []string{"uid", "rid", "d", "name1", "name2", "city", "depart", "destin", "geom", "rawstop", "schedule", "operators"}, pgx.CopyFromRows(row)); err != nil {
		log.Infof("[BUS] action=changetodbformat event=copyfrom_error error=%v row_count=%d", err, len(row))
	}
	if _, err := b.Exec(ctx, c2); err != nil {
		log.Infof("[BUS] action=changetodbformat event=insert_error error=%v", err)
	}
	if err := b.Commit(ctx); err != nil {
		log.Infof("[BUS] action=changetodbformat event=commit_error error=%v", err)
	}
}

// savestations upserts individual bus stations into bus_stations from the
// city's staged raw_bus_route rows of type 'Station', deriving the geometry from
// the raw StationPosition. Note it filters on depart = city (the staging column
// that holds the city for Station rows).
func savestations(ctx context.Context, db *pgxpool.Pool, city string) {
	c1 := `
			INSERT INTO bus_stations (
									  station_uid,
									  station_name,
									  city,
									  position,
									  updated_at
			)
			SELECT sub_route_uid,route_name,depart,
				   ST_SetSRID(ST_MakePoint((content->'StationPosition'->>'PositionLon')::float,(content->'StationPosition'->>'PositionLat')::float), 4326),
				   NOW()
			FROM raw_bus_route WHERE type = 'Station' AND depart = $1
			ON CONFLICT (station_uid) DO UPDATE SET station_name = EXCLUDED.station_name, position = EXCLUDED.position, updated_at = NOW()
			`
	if _, err := db.Exec(ctx, c1, city); err != nil {
		log.Infof("[BUS] action=savestations city=%s event=insert_error error=%v", city, err)
	} else {
		log.Infof("[BUS] action=savestations city=%s event=complete", city)
	}
}

// saveStationGroups builds bus station groups for a city in three passes: TDX
// StationGroup records (c1), synthetic name-based groups for stations TDX left
// ungrouped (c2, group_uid derived from an md5 of the station name), and group
// membership (c3, which for InterCity also snaps a station onto a nearby
// same-named municipal group within 1km). It then prunes empty groups and rows
// older than syncStart. Errors are logged per step; the run continues.
func saveStationGroups(ctx context.Context, db *pgxpool.Pool, city string, syncStart time.Time) {
	c1 := `
		INSERT INTO bus_station_groups (
			group_uid,
			group_id,
			group_name,
			city,
			position,
			source,
			updated_at
		)
		SELECT
			content->>'StationGroupUID',
			content->>'StationGroupID',
			content->'StationGroupName'->>'Zh_tw',
			$1,
			ST_SetSRID(ST_MakePoint(
				(content->'StationGroupPosition'->>'PositionLon')::float,
				(content->'StationGroupPosition'->>'PositionLat')::float
			), 4326),
			'tdx',
			NOW()
		FROM raw_bus_route
		WHERE type = 'StationGroup'
		  AND depart = $1
		  AND content->>'StationGroupUID' <> ''
		ON CONFLICT (group_uid) DO UPDATE SET
			group_id = EXCLUDED.group_id,
			group_name = EXCLUDED.group_name,
			city = EXCLUDED.city,
			position = EXCLUDED.position,
			source = EXCLUDED.source,
			updated_at = NOW();`
	c2 := `
		INSERT INTO bus_station_groups (
			group_uid,
			group_id,
			group_name,
			city,
			position,
			source,
			updated_at
		)
		SELECT
			$1 || ':manual:' || md5(content->'StationName'->>'Zh_tw'),
			$1 || ':manual:' || md5(content->'StationName'->>'Zh_tw'),
			content->'StationName'->>'Zh_tw',
			$1,
			ST_Centroid(ST_Collect(ST_SetSRID(ST_MakePoint(
				(content->'StationPosition'->>'PositionLon')::float,
				(content->'StationPosition'->>'PositionLat')::float
			), 4326))),
			'manual_name',
			NOW()
		FROM raw_bus_route s
		WHERE s.type = 'Station'
		  AND s.depart = $1
		  AND NOT EXISTS (
		  	SELECT 1
		  	FROM bus_station_groups g
		  	WHERE g.city = $1
		  	  AND g.group_id = s.content->>'StationGroupID'
		  )
		GROUP BY content->'StationName'->>'Zh_tw'
		ON CONFLICT (group_uid) DO UPDATE SET
			group_name = EXCLUDED.group_name,
			city = EXCLUDED.city,
			position = EXCLUDED.position,
			source = EXCLUDED.source,
			updated_at = NOW();`
	c3 := `
		INSERT INTO bus_station_group_members (
			station_uid,
			group_uid,
			station_id,
			station_name,
			city,
			position,
			updated_at
		)
			SELECT
				s.content->>'StationUID',
				COALESCE(same_name.group_uid, g.group_uid, $1 || ':manual:' || md5(s.content->'StationName'->>'Zh_tw')),
				s.content->>'StationID',
				s.content->'StationName'->>'Zh_tw',
				$1,
			ST_SetSRID(ST_MakePoint(
				(s.content->'StationPosition'->>'PositionLon')::float,
				(s.content->'StationPosition'->>'PositionLat')::float
			), 4326),
			NOW()
			FROM raw_bus_route s
			LEFT JOIN bus_station_groups g
			  ON g.city = $1
			 AND g.group_id = s.content->>'StationGroupID'
			LEFT JOIN LATERAL (
				SELECT sg.group_uid
				FROM bus_station_groups sg
				WHERE $1 = 'InterCity'
				  AND sg.city <> $1
				  AND sg.group_name = s.content->'StationName'->>'Zh_tw'
				  AND ST_DWithin(
				  	sg.position::geography,
				  	ST_SetSRID(ST_MakePoint(
				  		(s.content->'StationPosition'->>'PositionLon')::float,
				  		(s.content->'StationPosition'->>'PositionLat')::float
				  	), 4326)::geography,
				  	1000
				  )
				ORDER BY sg.position <-> ST_SetSRID(ST_MakePoint(
					(s.content->'StationPosition'->>'PositionLon')::float,
					(s.content->'StationPosition'->>'PositionLat')::float
				), 4326)
				LIMIT 1
			) same_name ON true
			WHERE s.type = 'Station'
			  AND s.depart = $1
			ON CONFLICT (station_uid) DO UPDATE SET
			group_uid = EXCLUDED.group_uid,
			station_id = EXCLUDED.station_id,
			station_name = EXCLUDED.station_name,
			city = EXCLUDED.city,
			position = EXCLUDED.position,
			updated_at = NOW();`
	if _, err := db.Exec(ctx, c1, city); err != nil {
		log.Infof("[BUS] action=saveStationGroups city=%s event=insert_tdx_groups_error error=%v", city, err)
	}
	if _, err := db.Exec(ctx, c2, city); err != nil {
		log.Infof("[BUS] action=saveStationGroups city=%s event=insert_manual_groups_error error=%v", city, err)
	}
	if _, err := db.Exec(ctx, c3, city); err != nil {
		log.Infof("[BUS] action=saveStationGroups city=%s event=insert_members_error error=%v", city, err)
	}
	if _, err := db.Exec(ctx, `DELETE FROM bus_station_groups g WHERE g.city = $1 AND NOT EXISTS (SELECT 1 FROM bus_station_group_members m WHERE m.group_uid = g.group_uid)`, city); err != nil {
		log.Infof("[BUS] action=saveStationGroups city=%s event=delete_empty_groups_error error=%v", city, err)
	}
	if _, err := db.Exec(ctx, `DELETE FROM bus_station_group_members WHERE city = $1 AND updated_at < $2`, city, syncStart); err != nil {
		log.Infof("[BUS] action=saveStationGroups city=%s event=delete_stale_members_error error=%v", city, err)
	}
	if _, err := db.Exec(ctx, `DELETE FROM bus_station_groups WHERE city = $1 AND updated_at < $2`, city, syncStart); err != nil {
		log.Infof("[BUS] action=saveStationGroups city=%s event=delete_stale_groups_error error=%v", city, err)
	}
}

// saveschedule rebuilds bus_schedule for a city from the staged raw_bus_route
// rows of type 'Schedule', expanding both frequency windows and per-stop
// timetables into rows and upserting them via a temp-table COPY. Rows older than
// this run's start are pruned as stale. On no rows or any step error it logs and
// returns without deleting.
func saveschedule(ctx context.Context, db *pgxpool.Pool, city string) {
	syncStart := time.Now()
	rows, err := db.Query(ctx, `SELECT content FROM raw_bus_route WHERE type = 'Schedule' AND destin = $1`, city)
	if err != nil {
		log.Infof("[BUS] action=saveschedule city=%s event=query_error error=%v", city, err)
		return
	}
	defer rows.Close()
	row := [][]interface{}{}
	for rows.Next() {
		var raw []byte
		if err := rows.Scan(&raw); err != nil {
			continue
		}
		var temp rawBusSchedule
		if err := json.Unmarshal(raw, &temp); err != nil {
			log.Infof("[BUS] action=saveschedule city=%s event=unmarshal_error error=%v", city, err)
			continue
		}
		uid, dir := makethatsame(city, temp.SubRouteUID, temp.Direction)
		for _, t := range temp.Frequencys {
			row = append(row, []interface{}{
				uid, int16(dir), true, "", false, int16(-1), strconv.Itoa(int(t.MinHeadwayMins)), strconv.Itoa(int(t.MaxHeadwayMins)), t.StartTime, t.EndTime, int16(mask2(t.ServiceDay.Monday, t.ServiceDay.Tuesday, t.ServiceDay.Wednesday, t.ServiceDay.Thursday, t.ServiceDay.Friday, t.ServiceDay.Saturday, t.ServiceDay.Sunday)),
			})
		}
		for _, t := range temp.Timetables {
			for _, st := range t.StopTimes {
				row = append(row, []interface{}{
					uid, dir, false, t.TripID, t.IsLowFloor, st.StopSequence, st.StopUID, st.StopName.Zhtw, st.ArrivalTime, st.ArrivalTime, mask2(t.ServiceDay.Monday, t.ServiceDay.Tuesday, t.ServiceDay.Wednesday, t.ServiceDay.Thursday, t.ServiceDay.Friday, t.ServiceDay.Saturday, t.ServiceDay.Sunday),
				})
			}
		}
	}
	if len(row) == 0 {
		log.Infof("[BUS] action=saveschedule city=%s event=skip reason=no_rows", city)
		return
	}
	b, err := db.Begin(ctx)
	if err != nil {
		log.Infof("[BUS] action=saveschedule city=%s event=begin_error error=%v", city, err)
		return
	}
	c1 := `CREATE TEMP TABLE temp_bus (
					uid text,
					dir smallint,
					type bool,
					id text,
					floor bool,
					seq smallint,
					stopuid text,
					stopname text,
					arrival text,
					departure text,
					sdays smallint
				) ON COMMIT DROP`
	c2 := busScheduleUpsertSQL
	defer func(b pgx.Tx, ctx context.Context) {
		_ = b.Rollback(ctx)
	}(b, ctx)
	if _, err := b.Exec(ctx, c1); err != nil {
		log.Infof("[BUS] action=saveschedule city=%s event=create_temp_error error=%v", city, err)
		return
	}
	if _, err = b.CopyFrom(ctx, pgx.Identifier{"temp_bus"},
		[]string{"uid", "dir", "type", "id", "floor", "seq", "stopuid", "stopname", "arrival", "departure", "sdays"},
		pgx.CopyFromRows(row)); err != nil {
		log.Infof("[BUS] action=saveschedule city=%s event=copyfrom_error error=%v", city, err)
		return
	}
	if _, err = b.Exec(ctx, c2); err != nil {
		log.Infof("[BUS] action=saveschedule city=%s event=insert_error error=%v", city, err)
		return
	}
	if err = b.Commit(ctx); err != nil {
		log.Infof("[BUS] action=saveschedule city=%s event=commit_error error=%v", city, err)
		return
	}
	if _, delErr := db.Exec(ctx, `DELETE FROM bus_schedule WHERE sub_route_uid LIKE $1 AND updated_at < $2`, citymap[city]+"%", syncStart); delErr != nil {
		log.Infof("[BUS] action=saveschedule city=%s event=cleanup_error error=%v", city, delErr)
	}
	log.Infof("[BUS] action=saveschedule city=%s event=complete row_count=%d", city, len(row))
}

// savestatictodb writes two things in one transaction: the serialized subroute
// protobuf into bus_static (the router's static query blob) and the
// stop-to-station mapping into bus_station_stop_map. Both use temp-table COPY
// then ON CONFLICT upsert. Steps that fail are logged; the transaction still
// commits whatever succeeded.
func savestatictodb(ctx context.Context, db *pgxpool.Pool, raw *map[string]*models.BusSubroute) {
	row := [][]interface{}{}
	mp := [][]interface{}{}
	for _, sub := range *raw {
		pb, err := proto.Marshal(sub)
		if err != nil {
			log.Infof("[BUS] action=savestatictodb event=marshal_error subroute=%s error=%v", sub.SubRouteUID, err)
			continue
		}
		row = append(row, []interface{}{
			sub.SubRouteName, sub.RouteName, sub.SubRouteUID, sub.RouteUID, sub.City, sub.DepartureStopName, sub.DestinationStopName, pb,
		})
		for dir, d := range sub.Directions {
			for _, stop := range d.Stops {
				var temp string
				if len(sub.SubRouteUID) >= 3 {
					temp = sub.SubRouteUID[:3]
				}
				mp = append(mp, []interface{}{
					temp + stop.StationID, stop.StopName, sub.SubRouteUID, sub.SubRouteName, dir, stop.StopUID, stop.StopSequence,
				})
			}
		}
	}
	b, err := db.Begin(ctx)
	if err != nil {
		log.Infof("[BUS] action=savestatictodb event=begin_error error=%v", err)
		return
	}
	defer func(b pgx.Tx, ctx context.Context) {
		_ = b.Rollback(ctx)
	}(b, ctx)
	if len(row) > 0 {
		if _, err := b.Exec(ctx, `CREATE TEMP TABLE temp_pb (sname text,rname text,uid text,rid text,city text,depart text,destin text,pb bytea) ON COMMIT DROP`); err != nil {
			log.Infof("[BUS] action=savestatictodb event=create_temp_pb_error error=%v", err)
		}
		if _, err := b.CopyFrom(ctx, pgx.Identifier{"temp_pb"}, []string{"sname", "rname", "uid", "rid", "city", "depart", "destin", "pb"}, pgx.CopyFromRows(row)); err != nil {
			log.Infof("[BUS] action=savestatictodb event=copyfrom_pb_error error=%v row_count=%d", err, len(row))
		}
		if _, err := b.Exec(ctx, `INSERT INTO bus_static (
										sub_route_name,
										route_name,
										sub_route_uid,
										route_uid,
										city,
										depart,
										destin,
										pb
									)
									SELECT sname,rname,uid,rid,city,depart,destin,pb FROM temp_pb
									ON CONFLICT (sub_route_uid) DO UPDATE SET sub_route_name = excluded.sub_route_name,route_name = excluded.route_name, pb = excluded.pb,route_uid = excluded.route_uid,city = excluded.city,depart = excluded.depart,destin = excluded.destin,updated_at = NOW();`); err != nil {
			log.Infof("[BUS] action=savestatictodb event=insert_pb_error error=%v", err)
		} else {
			log.Infof("[BUS] action=savestatictodb event=insert_pb_success row_count=%d", len(row))
		}
	}
	if len(mp) > 0 {
		if _, err := b.Exec(ctx, `CREATE TEMP TABLE temp_map(sid text, sname text, sruid text, rname text, dir int, suid text, seq int) ON COMMIT DROP`); err != nil {
			log.Infof("[BUS] action=savestatictodb event=create_temp_map_error error=%v", err)
		}
		if _, err := b.CopyFrom(ctx, pgx.Identifier{"temp_map"}, []string{"sid", "sname", "sruid", "rname", "dir", "suid", "seq"}, pgx.CopyFromRows(mp)); err != nil {
			log.Infof("[BUS] action=savestatictodb event=copyfrom_map_error error=%v row_count=%d", err, len(mp))
		}
		if _, err := b.Exec(ctx, `INSERT INTO bus_station_stop_map (
                                  station_id,
                                  station_name,
                                  sub_route_uid,
                                  route_name,
                                  direction,
                                  stop_uid,
                                  stop_sequence,
                                  updated_at
									)
									SELECT DISTINCT ON (sruid, suid, dir) sid, sname, sruid, rname, dir, suid, seq, NOW() FROM temp_map
									ON CONFLICT (sub_route_uid, stop_uid, direction) DO UPDATE
									SET station_name = EXCLUDED.station_name, route_name = EXCLUDED.route_name, stop_sequence = EXCLUDED.stop_sequence, updated_at = NOW();`); err != nil {
			log.Infof("[BUS] action=savestatictodb event=insert_map_error error=%v", err)
		} else {
			log.Infof("[BUS] action=savestatictodb event=insert_map_success row_count=%d", len(mp))
		}
	}
	if err := b.Commit(ctx); err != nil {
		log.Infof("[BUS] action=savestatictodb event=commit_error error=%v", err)
	} else {
		log.Infof("[BUS] action=savestatictodb event=complete pb_rows=%d map_rows=%d", len(row), len(mp))
	}
}
