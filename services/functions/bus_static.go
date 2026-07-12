package main

import (
	"bytes"
	"context"
	"encoding/json"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/protobuf/proto"
)

// loadBus rebuilds one city's bus static data from raw_tdx instead of live TDX.
// It reads the correlated route datasets (Route, StopOfRoute, Shape, Schedule)
// for the city from src — a single decoder cannot feed a multi-endpoint
// correlation, so the loadSpec hands loadBus the source rather than one decoder —
// drives the in-memory subroute assembly, then calls the shared upserts
// (changetodbformat, savestations, saveStationGroups, saveschedule,
// savestatictodb). savestations / saveStationGroups / saveschedule read
// raw_tdx.bus_station / bus_stationgroup / bus_schedule directly via SQL, so no
// staging table is involved.
//
// Operator and fare enrichment: operators are decoded in-memory from
// raw_tdx.bus_operator (loadBusOperatorMap, no SQL write — the standalone
// bus_operator loadSpec is the only bus_operators upserter) and used inside the
// Route closure; fares (raw_tdx.bus_routefare via loadBusFares) are applied
// before changetodbformat.
//
// Accepted intra-city torn-read risk: if a landing overruns the fixed 30-minute
// offset (03:00 land, 03:30 load) this run can read today's bus_route while
// bus_stopofroute still holds yesterday's landing for the same city. Each table
// is an internally consistent per-partition snapshot, so the result is degraded
// (a route may reference a stop set from the prior day) but never corrupt. We do
// not add per-stage staleness: the 27h gate on bus_route already blocks a whole
// stale landing, the offset is fixed, and the mixed-day window is rare and
// self-heals on the next successful run.
func loadBus(ctx context.Context, src loadSource, db *pgxpool.Pool, rc *redis.Client, city string) error {
	if city == "LienchiangCounty" {
		return nil
	}
	log.Infof("[LOAD] action=bus event=city_start city=%s", city)
	clearBusStaticCache(rc, city)
	opMap := loadBusOperatorMap(ctx, src, db, city)
	subRoutemap := make(map[string]*models.BusSubroute)
	routeMap := make(map[string][]string)
	// nameObs collects every distinct SubRouteName seen per canonical UID during
	// Route assembly. subRoutemap keeps only the first-seen name, so this is the
	// only place a name divergence between two TDX UIDs that canonicalize to the
	// same identity is observable (busConvergenceCheck).
	nameObs := make(map[string]map[string]struct{})
	syncStart := time.Now()

	// Route assembly. If no Route data landed, skip the city (matches
	// dailyRoute's no_route_data guard).
	routeFetched := loadBusDataset(ctx, src, city, "bus_route", "Route", func(raw []byte) {
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
					OperatorPhone: sanitizeOperatorPhone(detail.OperatorPhone),
					OperatorUrl:   detail.OperatorUrl,
				})
			}
		}
		for _, sub := range r.SubRoutes {
			uid, dir := shared.CanonicalSubroute(city, sub.SubRouteUID, sub.Direction)
			if name := sub.SubRouteName.Zhtw; name != "" {
				if nameObs[uid] == nil {
					nameObs[uid] = make(map[string]struct{})
				}
				nameObs[uid][name] = struct{}{}
			}
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

	loadBusDataset(ctx, src, city, "bus_stopofroute", "StopOfRoute", func(raw []byte) {
		var r rawStopofroute
		if err := json.Unmarshal(raw, &r); err != nil {
			log.Infof("[LOAD] action=bus city=%s api=StopOfRoute event=unmarshal_error error=%v", city, err)
		}
		uid, dir := shared.CanonicalSubroute(city, r.SubRouteUID, r.Direction)
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
	loadBusDataset(ctx, src, city, "bus_shape", "Shape", func(raw []byte) {
		var r rawBusShape
		if err := json.Unmarshal(raw, &r); err != nil {
			log.Infof("[LOAD] action=bus city=%s api=Shape event=unmarshal_error error=%v", city, err)
		}
		if r.SubRouteUID != "" {
			uid, dir := shared.CanonicalSubroute(city, r.SubRouteUID, r.Direction)
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
	loadBusDataset(ctx, src, city, "bus_schedule", "Schedule", func(raw []byte) {
		var r rawBusSchedule
		if err := json.Unmarshal(raw, &r); err != nil {
			log.Infof("[LOAD] action=bus city=%s api=Schedule event=unmarshal_error error=%v", city, err)
		}
		uid, dir := shared.CanonicalSubroute(city, r.SubRouteUID, r.Direction)
		if sr, ok := subRoutemap[uid]; ok {
			if d, ok := sr.Directions[int32(dir)]; ok {
				for _, t := range r.Timetables {
					m := mask2(t.ServiceDay.Monday, t.ServiceDay.Tuesday, t.ServiceDay.Wednesday, t.ServiceDay.Thursday, t.ServiceDay.Friday, t.ServiceDay.Saturday, t.ServiceDay.Sunday)
					for _, temp := range t.StopTimes {
						d.Schedules = append(d.Schedules, &models.Bus_Schedule{
							IsTimetable:                 true,
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
						IsTimetable:                 false,
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
	// Station and StationGroup are not accumulated in-memory here: savestations
	// and saveStationGroups read raw_tdx.bus_station / raw_tdx.bus_stationgroup
	// directly via SQL.
	fareBySub, fareByRoute := loadBusFareMaps(ctx, src, city)
	for uid, sub := range subRoutemap {
		if f, ok := fareBySub[uid]; ok {
			sub.Fare = cloneBusFare(f)
		} else if f, ok := fareByRoute[sub.RouteUID]; ok {
			sub.Fare = cloneBusFare(f)
		}
	}
	changetodbformat(ctx, db, &subRoutemap)
	savestations(ctx, db, city)
	saveStationGroups(ctx, db, city, syncStart)
	saveschedule(ctx, db, city)
	if prefix := citymap[city]; prefix == "" {
		// An unmapped city would make the partition pattern '%', deleting every
		// city's rows. The upsert below still refreshes this city's own rows; only
		// stale-row pruning is skipped, which is strictly safer than a full wipe.
		log.Infof("[LOAD] action=bus city=%s event=delete_stop_map_skipped reason=no_prefix", city)
	} else if _, delErr := db.Exec(ctx, `DELETE FROM bus_station_stop_map WHERE sub_route_uid LIKE $1`, prefix+"%"); delErr != nil {
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
	busConvergenceCheck(city, subRoutemap, nameObs)
	log.Infof("[LOAD] action=bus event=city_complete city=%s subroute_count=%d", city, len(subRoutemap))
	return nil
}

// convergenceViolation is one canonical UID that failed the ADR-0006 merge
// invariant: issue is "too_many_directions" or "name_mismatch", detail carries
// the offending value (direction count or the pipe-joined distinct names).
type convergenceViolation struct {
	canonical string
	issue     string
	detail    string
}

// busConvergenceCheck verifies the canonical-subroute merge (ADR-0006) over one
// city's loaded subroutes and logs a structured warning per violation. It
// delegates the decision to findConvergenceViolations so the rule is unit
// testable. Violations are logged, not corrected — the recorded fallback
// (ADR-0006) is the load-time mapping table.
func busConvergenceCheck(city string, subRoutemap map[string]*models.BusSubroute, nameObs map[string]map[string]struct{}) {
	for _, v := range findConvergenceViolations(subRoutemap, nameObs) {
		log.Infof("[LOAD] action=convergence_check event=convergence_invalid city=%s canonical=%s issue=%s detail=%q", city, v.canonical, v.issue, v.detail)
	}
}

// findConvergenceViolations returns every canonical UID that violates the
// ADR-0006 invariant: at most two directions, and a single SubRouteName across
// the TDX UIDs that canonicalized to it. subRoutemap supplies the direction
// count; nameObs supplies the distinct names seen during Route assembly (before
// subRoutemap collapsed them to the first-seen name). Results are ordered by
// canonical UID for deterministic logging and testing.
func findConvergenceViolations(subRoutemap map[string]*models.BusSubroute, nameObs map[string]map[string]struct{}) []convergenceViolation {
	var out []convergenceViolation
	for uid, sub := range subRoutemap {
		if n := len(sub.Directions); n > 2 {
			out = append(out, convergenceViolation{uid, "too_many_directions", strconv.Itoa(n)})
		}
	}
	for uid, names := range nameObs {
		if len(names) > 1 {
			distinct := make([]string, 0, len(names))
			for name := range names {
				distinct = append(distinct, name)
			}
			sort.Strings(distinct)
			out = append(out, convergenceViolation{uid, "name_mismatch", strings.Join(distinct, "|")})
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].canonical != out[j].canonical {
			return out[i].canonical < out[j].canonical
		}
		return out[i].issue < out[j].issue
	})
	return out
}

// loadBusOperatorMap returns a city's operators for the subroute assembly by
// decoding raw_tdx.bus_operator's payload in-memory, keyed by OperatorID. It
// performs NO SQL write: the standalone bus_operator loadSpec (which precedes the bus spec in
// the registry — see loaderRegistry's ordering invariant) is the only
// bus_operators upserter. A stale partition is logged but still used, the same
// policy as loadBusFareMaps: stale operator detail beats blanking Operators on
// every subroute.
//
// Only when the raw read or decode itself fails does it fall back to the
// stored bus_operators rows, mirroring legacy's TDX-failure fallback. That
// fallback is citymap-limited: busOperatorsFromDB filters on authority_code =
// citymap[city], and citymap lacks the County-suffixed city keys, so for those
// cities the fallback returns empty — pre-existing legacy behavior, and the
// reason the primary path here must not route through citymap or the DB.
func loadBusOperatorMap(ctx context.Context, src loadSource, db *pgxpool.Pool, city string) map[string]rawBusOperator {
	body, fetchedAt, err := src.datasetJSON(ctx, "bus_operator", "city", city)
	if err != nil {
		log.Infof("[LOAD] action=bus city=%s api=Operator event=read_error error=%v", city, err)
		return busOperatorsFromDB(ctx, db, city)
	}
	if isStale(fetchedAt) {
		log.Infof("[LOAD] action=bus_operators event=stale city=%s fetched_at=%s reason=%v", city, fetchedAt.Format(time.RFC3339), errLoadStale)
	}
	var ops []rawBusOperator
	if err := json.Unmarshal(body, &ops); err != nil {
		log.Infof("[LOAD] action=bus city=%s api=Operator event=decode_error error=%v", city, err)
		return busOperatorsFromDB(ctx, db, city)
	}
	result := make(map[string]rawBusOperator, len(ops))
	for _, op := range ops {
		result[op.OperatorID] = op
	}
	return result
}

// loadBusFareMaps reads a city's route fares from raw_tdx.bus_routefare and
// parses them with loadBusFares into two lookups: fares keyed by subroute UID,
// and route-wide fares keyed by route UID. On a read or decode failure it returns
// nil, nil, and subroutes then load without fares.
//
// Unlike the staleness-gated loadSpecs, a stale fare partition is logged but
// still used: fare data changes rarely and stale fares beat missing fares
// (blanking Fare on every subroute the moment a landing is skipped is a worse
// user-facing outcome than showing yesterday's price), so this reader keeps the
// last landed fares in place until a fresh landing replaces them.
func loadBusFareMaps(ctx context.Context, src loadSource, city string) (map[string]*models.Bus_Fare, map[string]*models.Bus_Fare) {
	body, fetchedAt, err := src.datasetJSON(ctx, "bus_routefare", "city", city)
	if err != nil {
		log.Infof("[LOAD] action=bus city=%s api=RouteFare event=read_error error=%v", city, err)
		return nil, nil
	}
	if isStale(fetchedAt) {
		log.Infof("[LOAD] action=bus_fares event=stale city=%s fetched_at=%s reason=%v", city, fetchedAt.Format(time.RFC3339), errLoadStale)
	}
	bySub, byRoute, loadErr := loadBusFares(json.NewDecoder(bytes.NewReader(body)), city)
	if loadErr != nil {
		return nil, nil
	}
	return bySub, byRoute
}

// loadBusDataset reads one bus dataset for a city from raw_tdx and invokes
// processer on each element for in-memory accumulation. It returns true when any
// element was processed (used as the Route no-data guard). Station and
// StationGroup are not routed through here: savestations / saveStationGroups read
// raw_tdx directly via SQL.
func loadBusDataset(ctx context.Context, src loadSource, city, table, api string, processer func([]byte)) bool {
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
	for _, raw := range elems {
		processer(raw)
	}
	return true
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
			if err != nil {
				log.Infof("[BUS] action=changetodbformat event=marshal_error field=stops error=%v", err)
				continue
			}
			schedules, err := json.Marshal(d.Schedules)
			if err != nil {
				log.Infof("[BUS] action=changetodbformat event=marshal_error field=schedules error=%v", err)
				continue
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

// savestations upserts individual bus stations into bus_stations from
// raw_tdx.bus_station for the city, deriving the geometry from the flattened
// stationposition column.
func savestations(ctx context.Context, db *pgxpool.Pool, city string) {
	c1 := `
			INSERT INTO bus_stations (
									  station_uid,
									  station_name,
									  city,
									  position,
									  updated_at
			)
			SELECT stationuid, stationname->>'Zh_tw', city,
				   ST_SetSRID(ST_MakePoint((stationposition->>'PositionLon')::float,(stationposition->>'PositionLat')::float), 4326),
				   NOW()
			FROM raw_tdx.bus_station WHERE city = $1
			ON CONFLICT (station_uid) DO UPDATE SET station_name = EXCLUDED.station_name, position = EXCLUDED.position, updated_at = NOW()
			`
	if _, err := db.Exec(ctx, c1, city); err != nil {
		log.Infof("[BUS] action=savestations city=%s event=insert_error error=%v", city, err)
	} else {
		log.Infof("[BUS] action=savestations city=%s event=complete", city)
	}
}

// saveStationGroups builds bus station groups for a city in three passes: TDX
// StationGroup records from raw_tdx.bus_stationgroup (c1), synthetic name-based
// groups for stations TDX left ungrouped (c2, group_uid derived from an md5 of
// the station name), and group membership from raw_tdx.bus_station (c3, which for
// InterCity also snaps a station onto a nearby same-named municipal group within
// 1km). It then prunes empty groups and rows older than syncStart. Errors are
// logged per step; the run continues.
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
			stationgroupuid,
			stationgroupid,
			stationgroupname->>'Zh_tw',
			$1,
			ST_SetSRID(ST_MakePoint(
				(stationgroupposition->>'PositionLon')::float,
				(stationgroupposition->>'PositionLat')::float
			), 4326),
			'tdx',
			NOW()
		FROM raw_tdx.bus_stationgroup
		WHERE city = $1
		  AND stationgroupuid <> ''
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
			$1 || ':manual:' || md5(stationname->>'Zh_tw'),
			$1 || ':manual:' || md5(stationname->>'Zh_tw'),
			stationname->>'Zh_tw',
			$1,
			ST_Centroid(ST_Collect(ST_SetSRID(ST_MakePoint(
				(stationposition->>'PositionLon')::float,
				(stationposition->>'PositionLat')::float
			), 4326))),
			'manual_name',
			NOW()
		FROM raw_tdx.bus_station s
		WHERE s.city = $1
		  AND NOT EXISTS (
		  	SELECT 1
		  	FROM bus_station_groups g
		  	WHERE g.city = $1
		  	  AND g.group_id = s.stationgroupid
		  )
		GROUP BY stationname->>'Zh_tw'
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
				s.stationuid,
				COALESCE(same_name.group_uid, g.group_uid, $1 || ':manual:' || md5(s.stationname->>'Zh_tw')),
				s.stationid,
				s.stationname->>'Zh_tw',
				$1,
			ST_SetSRID(ST_MakePoint(
				(s.stationposition->>'PositionLon')::float,
				(s.stationposition->>'PositionLat')::float
			), 4326),
			NOW()
			FROM raw_tdx.bus_station s
			LEFT JOIN bus_station_groups g
			  ON g.city = $1
			 AND g.group_id = s.stationgroupid
			LEFT JOIN LATERAL (
				SELECT sg.group_uid
				FROM bus_station_groups sg
				WHERE $1 = 'InterCity'
				  AND sg.city <> $1
				  AND sg.group_name = s.stationname->>'Zh_tw'
				  AND ST_DWithin(
				  	sg.position::geography,
				  	ST_SetSRID(ST_MakePoint(
				  		(s.stationposition->>'PositionLon')::float,
				  		(s.stationposition->>'PositionLat')::float
				  	), 4326)::geography,
				  	1000
				  )
				ORDER BY sg.position <-> ST_SetSRID(ST_MakePoint(
					(s.stationposition->>'PositionLon')::float,
					(s.stationposition->>'PositionLat')::float
				), 4326)
				LIMIT 1
			) same_name ON true
			WHERE s.city = $1
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

// saveschedule rebuilds bus_schedule for a city from raw_tdx.bus_schedule,
// expanding both frequency windows and per-stop timetables into rows. It is
// partition-replace: within ONE transaction it DELETEs the city's rows (matched
// by the citymap sub_route_uid prefix), COPYs the fresh rows into temp_bus, then
// plain-INSERTs them (busScheduleInsertSQL — no dedup, no upsert). Duplicate rows
// from circular routes revisiting a stop are intentionally kept. On no rows or
// any step error it logs and returns; the transaction rolls back, leaving the
// prior partition untouched.
func saveschedule(ctx context.Context, db *pgxpool.Pool, city string) {
	rows, err := db.Query(ctx, `SELECT subrouteuid, direction, timetables, frequencys FROM raw_tdx.bus_schedule WHERE city = $1`, city)
	if err != nil {
		log.Infof("[BUS] action=saveschedule city=%s event=query_error error=%v", city, err)
		return
	}
	defer rows.Close()
	row := [][]interface{}{}
	for rows.Next() {
		var subRouteUID string
		var direction uint8
		var timetablesJSON, frequencysJSON []byte
		if err := rows.Scan(&subRouteUID, &direction, &timetablesJSON, &frequencysJSON); err != nil {
			continue
		}
		var temp rawBusSchedule
		if len(timetablesJSON) > 0 {
			if err := json.Unmarshal(timetablesJSON, &temp.Timetables); err != nil {
				log.Infof("[BUS] action=saveschedule city=%s event=unmarshal_error field=timetables error=%v", city, err)
			}
		}
		if len(frequencysJSON) > 0 {
			if err := json.Unmarshal(frequencysJSON, &temp.Frequencys); err != nil {
				log.Infof("[BUS] action=saveschedule city=%s event=unmarshal_error field=frequencys error=%v", city, err)
			}
		}
		uid, dir := shared.CanonicalSubroute(city, subRouteUID, direction)
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
	if err := rows.Err(); err != nil {
		log.Infof("[BUS] action=saveschedule city=%s event=rows_error error=%v", city, err)
		return
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
	defer func(b pgx.Tx, ctx context.Context) {
		_ = b.Rollback(ctx)
	}(b, ctx)
	prefix := citymap[city]
	if prefix == "" {
		// Same guard as loadBus's stop-map partition: an empty prefix degrades the
		// pattern to '%' and would delete every city's schedule rows.
		log.Infof("[BUS] action=saveschedule city=%s event=delete_partition_skipped reason=no_prefix", city)
	} else if _, err := b.Exec(ctx, `DELETE FROM bus_schedule WHERE sub_route_uid LIKE $1`, prefix+"%"); err != nil {
		log.Infof("[BUS] action=saveschedule city=%s event=delete_partition_error error=%v", city, err)
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
	if _, err = b.Exec(ctx, busScheduleInsertSQL); err != nil {
		log.Infof("[BUS] action=saveschedule city=%s event=insert_error error=%v", city, err)
		return
	}
	if err = b.Commit(ctx); err != nil {
		log.Infof("[BUS] action=saveschedule city=%s event=commit_error error=%v", city, err)
		return
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
