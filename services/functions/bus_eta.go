package main

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strconv"
	"sync"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/protobuf/proto"
)

// busEta refreshes live bus arrivals for all cities on the 30s cron. Cities are
// processed concurrently, capped at 4 in flight (sem). Two cities with no usable
// TDX ETA feed are skipped inline. It blocks until every city finishes.
func busEta(
	ctx context.Context,
	client *resty.Client,
	rc *redis.Client,
	db *pgxpool.Pool,
	dispatcher *notificationDispatcher,
) {
	log.Infof("[BUS_ETA] action=Bus_eta event=start")
	sem := make(chan struct{}, 4)
	var wg sync.WaitGroup
	for _, city := range cities {
		if city == "ChanghuaCounty" || city == "NantouCounty" {
			continue
		}
		wg.Add(1)
		go func(city string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			processBusEtaCity(ctx, client, rc, db, city, dispatcher)
		}(city)
	}
	wg.Wait()
	log.Infof("[BUS_ETA] action=Bus_eta event=complete")
}

// processBusEtaCity builds and publishes one city's bus arrivals. It joins the
// static stop map (cached per prefix) with live TDX ETAs and vehicle positions,
// then: records history rows for stops with a bus en route (StopStatus 0); fills
// a predicted NextBusTime for stops flagged status 1 with no TDX NextBusTime,
// using the next scheduled departure plus travel averages and the XGBoost
// correction (predictNextBusTime); attaches the nearest live vehicle to each
// stop; and dispatches arrival notifications. Results are written to Redis both
// as SET snapshots (180s TTL) and PUBLISH events, keyed per station and per route.
func processBusEtaCity(
	ctx context.Context,
	client *resty.Client,
	rc *redis.Client,
	db *pgxpool.Pool,
	city string,
	dispatcher *notificationDispatcher,
) {
	log.Infof("[BUS_ETA] action=Bus_eta city=%s event=city_start", city)
	prefix := citymap[city]
	mp, cached := cachedBusStaticMap(prefix)
	if !cached {
		var err error
		mp, err = busstaticmp(ctx, db, prefix)
		if err != nil || len(mp) <= 0 {
			log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_empty reason=no_stations", city)
			return
		}
		storeBusStaticMap(prefix, mp)
	}
	if len(mp) <= 0 {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_empty reason=no_stations", city)
		return
	}
	var eat []rawBusEsimated
	var url string
	if city == "InterCity" {
		url = "/v2/Bus/EstimatedTimeOfArrival/InterCity"
	} else {
		url = fmt.Sprintf("/v2/Bus/EstimatedTimeOfArrival/City/%s", city)
	}
	dec, comp, err, flipopen := callApi(client, rc, url, "bus_EstimatedTimeOfArrival"+city)
	if err != nil || !comp {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_eta error=%v", city, err)
		return
	}
	if _, err := dec.Token(); err == nil {
		for dec.More() {
			var e rawBusEsimated
			if err := dec.Decode(&e); err == nil {
				eat = append(eat, e)
			}
		}
	}
	flipopen()
	var posit []rawBusPosition
	if city == "InterCity" {
		url = "/v2/Bus/RealTimeByFrequency/InterCity"
	} else {
		url = fmt.Sprintf("/v2/Bus/RealTimeByFrequency/City/%s", city)
	}
	dec, comp, err, flipopen = callApi(client, rc, url, "bus_RealTimeByFrequency"+city)
	if err != nil || !comp {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_position error=%v", city, err)
		return
	}
	if _, err := dec.Token(); err == nil {
		for dec.More() {
			var p rawBusPosition
			if err := dec.Decode(&p); err == nil {
				posit = append(posit, p)
			}
		}
	}
	flipopen()
	busmap := make(map[string][]*models.BusPosition)
	etamap := make(map[string]rawBusEsimated)
	stations := make(map[string]*models.Bus_StationArrival)
	routes := make(map[string]*models.Bus_RouteArrival)
	for _, eat := range eat {
		etamap[eat.StopUID] = eat
	}
	for _, b := range posit {
		uid, _ := shared.CanonicalSubroute(city, b.SubRouteUID, b.Direction)
		pb := &models.BusPosition{
			PlateNumb:   b.PlateNumb,
			PositionLon: b.BusPosition.PositionLon,
			PositionLat: b.BusPosition.PositionLat,
			Speed:       int32(b.Speed),
			Azimuth:     int32(b.Azimuth),
			DutyStatus:  int32(b.DutyStatus),
			BusStatus:   int32(b.BusStatus),
			GpsTime:     b.GPSTime,
		}
		busmap[uid] = append(busmap[uid], pb)
	}
	totalStops := make(map[string]int)
	for _, b := range mp {
		uid, _ := shared.CanonicalSubroute(city, b.SubRouteUID, b.Direction)
		totalStops[uid]++
	}
	var weather *weatherData
	if wjson, wErr := rc.Get("weather:" + city).Result(); wErr == nil {
		var w weatherData
		if json.Unmarshal([]byte(wjson), &w) == nil {
			weather = &w
		}
	}
	now := time.Now().In(taipei)
	holiday := isHoliday(now)
	var fillKeys []routeDirKey
	fillUIDs := make(map[string]bool)
	for _, b := range mp {
		if etaEnt, ok2 := etamap[b.StopUID]; ok2 && etaEnt.StopStatus == 1 && etaEnt.NextBusTime == "" {
			uid, dir := shared.CanonicalSubroute(city, b.SubRouteUID, b.Direction)
			fillKeys = append(fillKeys, routeDirKey{uid, int32(dir)})
			fillUIDs[uid] = true
		}
	}
	todTime := now.Format("15:04:05")
	depMap := batchNextDepartures(ctx, db, dedupRouteDirPairs(fillKeys), todTime)
	uidList := make([]string, 0, len(fillUIDs))
	for u := range fillUIDs {
		uidList = append(uidList, u)
	}
	travelAvgMap := batchTravelAvg(ctx, db, uidList, now.Hour(), int(now.Weekday()))
	maxAvgMap := make(map[routeDirKey]int)
	for k, v := range travelAvgMap {
		rk := routeDirKey{k.subRouteUID, k.direction}
		if v > maxAvgMap[rk] {
			maxAvgMap[rk] = v
		}
	}
	var historyRows [][]interface{}
	for _, b := range mp {
		eta, ok := etamap[b.StopUID]
		status := uint8(67)
		var est int32
		var stime string
		// Canonicalize before every downstream write: the Redis route key, the
		// bus_eta_history row, dispatched notifications, and the app-facing protos
		// all key on the canonical UID plus derived direction (ADR-0006), so the
		// router (which no longer normalizes) and the training data see one
		// identity space. For non-InterCity, this is identity.
		uid, dir := shared.CanonicalSubroute(city, b.SubRouteUID, b.Direction)
		if ok {
			if srcT, parseErr := time.Parse(time.RFC3339, eta.SrcUpdateTime); parseErr == nil {
				est = eta.EstimatedTime - int32(now.Sub(srcT).Seconds())
			} else {
				est = eta.EstimatedTime
			}
			status = eta.StopStatus
			stime = eta.SrcUpdateTime
		}
		if status == 0 {
			ts := totalStops[uid]
			var plateNumb *string
			var busSpeed *int16
			var busDist *int
			if buses := busmap[uid]; len(buses) > 0 && b.Lat != 0 {
				nearest := buses[0]
				nearestDist := haversine(b.Lat, b.Lon,
					float64(nearest.PositionLat), float64(nearest.PositionLon))
				for _, bus := range buses[1:] {
					d := haversine(b.Lat, b.Lon,
						float64(bus.PositionLat), float64(bus.PositionLon))
					if d < nearestDist {
						nearestDist = d
						nearest = bus
					}
				}
				pn := nearest.PlateNumb
				plateNumb = &pn
				spd := int16(nearest.Speed)
				busSpeed = &spd
				dist := int(nearestDist)
				busDist = &dist
			}
			var srcTime *time.Time
			if stime != "" {
				if t, err := time.Parse(time.RFC3339, stime); err == nil {
					srcTime = &t
				}
			}
			var nextBusTimePtr *string
			if eta.NextBusTime != "" {
				nbtp := eta.NextBusTime
				nextBusTimePtr = &nbtp
			}
			weatherTemp, weatherPrecip, weatherWind, weatherHumid := interface{}(nil), interface{}(nil), interface{}(nil), interface{}(nil)
			if weather != nil {
				weatherTemp = weather.Temperature
				weatherPrecip = weather.Precipitation
				weatherWind = weather.WindSpeed
				weatherHumid = weather.Humidity
			}
			historyRows = append(historyRows, []interface{}{
				uid, b.StopUID, int16(dir),
				int16(b.StopSequence), int16(ts), est, nextBusTimePtr, srcTime,
				city, int16(now.Hour()), int16(now.Weekday()), holiday,
				weatherTemp, weatherPrecip, weatherWind, weatherHumid,
				plateNumb, busSpeed, busDist,
			})
		}
		if status == 1 && eta.NextBusTime == "" {
			rk := routeDirKey{uid, int32(dir)}
			avgKey := travelAvgKey{uid, int32(dir), b.StopUID, now.Hour(), int(now.Weekday())}
			avgVal, hasAvg := travelAvgMap[avgKey]
			eta.NextBusTime = predictNextBusTime(rc,
				busStopCtx{
					subRouteUID:  uid,
					direction:    int32(dir),
					stopUID:      b.StopUID,
					city:         city,
					stopSequence: int(b.StopSequence),
					totalStops:   totalStops[uid],
				},
				predictionInputs{
					now:          now,
					nextDep:      depMap[rk],
					travelAvg:    avgVal,
					hasTravelAvg: hasAvg,
					maxTravelAvg: maxAvgMap[rk],
				},
			)
		}
		groupUID := b.GroupUID
		if groupUID == "" {
			groupUID = b.StationUID
		}
		groupName := b.GroupName
		if groupName == "" {
			groupName = b.StationName
		}
		if _, ok = stations[groupUID]; !ok {
			stations[groupUID] = &models.Bus_StationArrival{
				StationName: groupName,
				StationUid:  make([]string, 0),
				Routes:      make([]*models.Bus_StopEstimate, 0),
			}
		}
		station := stations[groupUID]
		if !slices.Contains(station.StationUid, b.StationUID) {
			station.StationUid = append(station.StationUid, b.StationUID)
		}
		station.Routes = append(station.Routes, &models.Bus_StopEstimate{
			StopUid:       b.StationUID,
			SubRouteUid:   uid,
			RouteName:     b.SubRouteName,
			Direction:     int32(dir),
			Estimate:      est,
			NextBusTime:   eta.NextBusTime,
			StopStatus:    int32(status),
			SrcUpdateTime: stime,
			Buses:         busmap[uid],
		})
		if shouldDispatchBusArrival(ok, status, est) {
			dispatcher.arrival(ctx, "bus", uid, b.StopUID, strconv.Itoa(int(dir)), est)
		}
		if _, ok = routes[uid]; !ok {
			routes[uid] = &models.Bus_RouteArrival{
				SubRouteUid: uid,
				Stops:       make([]*models.Bus_RouteEstimate, 0),
			}
		}
		routes[uid].Stops = append(routes[uid].Stops, &models.Bus_RouteEstimate{
			StopUid:       b.StopUID,
			Direction:     int32(dir),
			Estimate:      est,
			StopStatus:    int32(status),
			NextBusTime:   eta.NextBusTime,
			SrcUpdateTime: stime,
			Buses:         busmap[uid],
			StopSequence:  int32(b.StopSequence),
		})
	}
	pipe := rc.Pipeline()
	for groupUID, pb := range stations {
		data, _ := proto.Marshal(pb)
		key := fmt.Sprintf("bus_eta_station:%s:%s", city, groupUID)
		pipe.Set(key, data, 180*time.Second)
		pipe.Publish(key, data)
	}
	for uid, pb := range routes {
		data, _ := proto.Marshal(pb)
		key := busRouteEtaKey(uid)
		pipe.Set(key, data, 180*time.Second)
		pipe.Publish(key, data)
	}
	_, err = pipe.Exec()
	if err != nil {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=redis_error error=%v station_count=%d route_count=%d eat_count=%d posit_count=%d", city, err, len(stations), len(routes), len(eat), len(posit))
	} else {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=redis_success station_count=%d route_count=%d eat_count=%d posit_count=%d", city, len(stations), len(routes), len(eat), len(posit))
	}
	saveBusEtaHistory(ctx, db, historyRows)
}

// shouldDispatchBusArrival reports whether a live ETA warrants an arrival
// notification: a matched TDX ETA (found), a bus en route (StopStatus 0), and a
// positive remaining time. A non-positive estimate means the bus has effectively
// arrived or passed, so no reminder is sent.
func shouldDispatchBusArrival(found bool, status uint8, etaSeconds int32) bool {
	return found && status == 0 && etaSeconds > 0
}
