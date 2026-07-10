package main

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strconv"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/functions/notify"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/protobuf/proto"
)

// etaKey identifies one TDX ETA entry by its canonical subroute, derived
// direction, and stop. TDX emits one entry per (stop x subroute x direction),
// so keying on all three keeps multi-route stops from overwriting each other.
type etaKey struct {
	subRouteUID string
	direction   uint8
	stopUID     string
}

type busArrivalNotifier interface {
	Arrival(context.Context, string, string, string, string, int32)
}

type busLiveJob struct {
	fetch    boundFetch
	sink     liveSink
	store    busEtaStore
	notifier busArrivalNotifier
	now      func() time.Time
}

// pickBusEstimate resolves two ETA entries sharing an etaKey (multiple buses on
// the same route toward the same stop): prefer a bus en route (StopStatus 0),
// and among those keep the soonest (smallest EstimatedTime). If neither is
// status 0, keep the first seen.
func pickBusEstimate(prev, next rawBusEsimated) rawBusEsimated {
	if prev.StopStatus == 0 && next.StopStatus == 0 {
		if next.EstimatedTime < prev.EstimatedTime {
			return next
		}
		return prev
	}
	if next.StopStatus == 0 {
		return next
	}
	return prev
}

// decodeBusEtaArray streams a TDX ETA array into rawBusEsimated entries. It
// reports complete=false when the opening array token is missing, any element
// fails to decode, or the closing token never arrives — all signs of a
// truncated or malformed body. Callers use this to avoid overwriting the live
// snapshot with a partial (blank-heavy) result: a bad body is treated like a
// 304, keeping the last good ETAs alive rather than blanking the route for a
// tick until the next good fetch.
func decodeBusEtaArray(dec *json.Decoder) (eat []rawBusEsimated, complete bool) {
	if _, err := dec.Token(); err != nil { // opening '['
		return nil, false
	}
	for dec.More() {
		var e rawBusEsimated
		if err := dec.Decode(&e); err != nil {
			return eat, false
		}
		eat = append(eat, e)
	}
	if _, err := dec.Token(); err != nil { // closing ']'
		return eat, false
	}
	return eat, true
}

// busEta refreshes live bus arrivals for all cities on the 30s cron. Cities are
// processed concurrently, capped at 4 in flight (sem). Two cities with no usable
// TDX ETA feed are skipped inline. It blocks until every city finishes.
func busEta(
	ctx context.Context,
	fetch boundFetch,
	sink liveSink,
	db *pgxpool.Pool,
	dispatcher *notify.Dispatcher,
) {
	log.Infof("[BUS_ETA] action=Bus_eta event=start")
	job := busLiveJob{
		fetch:    fetch,
		sink:     sink,
		store:    pgBusEtaStore{db: db},
		notifier: dispatcher,
		now:      time.Now,
	}
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
			job.runCity(ctx, city)
		}(city)
	}
	wg.Wait()
	log.Infof("[BUS_ETA] action=Bus_eta event=complete")
}

// busEtaTTLPatterns returns the station-group and route ETA key patterns for one
// city, paired with the 180s window to re-arm. It is the per-city input to the
// sink's 304→TTL refresh (CONTEXT.md): the cached arrival instants stay valid
// across a 304, so their snapshots must outlive the polling gap.
func busEtaTTLPatterns(city string) []ttlPattern {
	return []ttlPattern{
		{pattern: shared.BusStationEtaPattern(city), ttl: busLiveTTL},
		{pattern: shared.BusRouteEtaPattern(citymap[city]), ttl: busLiveTTL},
	}
}

// busLiveJob.runCity builds and publishes one city's bus arrivals. It joins the
// static stop map (cached per prefix) with live TDX ETAs and vehicle positions,
// then: records history rows for stops with a bus en route (StopStatus 0); fills
// a predicted NextBusTime for stops flagged status 1 with no TDX NextBusTime,
// using the next scheduled departure plus travel averages and the XGBoost
// correction (predictNextBusTime); attaches the nearest live vehicle to each
// stop; and dispatches arrival notifications. Results are written to Redis both
// as SET snapshots (180s TTL) and PUBLISH events, keyed per station and per route.
func (j busLiveJob) runCity(ctx context.Context, city string) {
	log.Infof("[BUS_ETA] action=Bus_eta city=%s event=city_start", city)
	prefix := citymap[city]
	if prefix == "" {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_empty reason=no_prefix", city)
		return
	}
	mp, cached := cachedBusStaticMap(prefix)
	if !cached {
		var err error
		mp, err = j.store.staticStops(ctx, prefix)
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
	var url string
	if city == "InterCity" {
		url = "/v2/Bus/EstimatedTimeOfArrival/InterCity"
	} else {
		url = fmt.Sprintf("/v2/Bus/EstimatedTimeOfArrival/City/%s", city)
	}
	dec, comp, flipopen, err := j.fetch(ctx, url, "bus_EstimatedTimeOfArrival"+city)
	if err != nil || !comp {
		if err == nil {
			// 304 Not-Modified: the cached arrival instants are still valid, so
			// re-arm their TTL instead of letting the snapshots expire mid-validity.
			j.sink.refreshTTL(busEtaTTLPatterns(city))
		}
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_eta error=%v", city, err)
		return
	}
	eat, complete := decodeBusEtaArray(dec)
	flipopen()
	if !complete {
		// Truncated or malformed body: committing it would overwrite the live
		// snapshot with mostly status-67 blanks (the abrupt-blank-then-recover
		// flicker). Treat it like a 304 — re-arm the last good snapshot's TTL.
		j.sink.refreshTTL(busEtaTTLPatterns(city))
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_partial_eta eat_count=%d", city, len(eat))
		return
	}
	var posit []rawBusPosition
	if city == "InterCity" {
		url = "/v2/Bus/RealTimeByFrequency/InterCity"
	} else {
		url = fmt.Sprintf("/v2/Bus/RealTimeByFrequency/City/%s", city)
	}
	dec, comp, flipopen, err = j.fetch(ctx, url, "bus_RealTimeByFrequency"+city)
	if err != nil || !comp {
		if err == nil {
			// 304 Not-Modified on positions: the cached snapshot is still
			// valid, so re-arm its TTL instead of letting it expire mid-validity.
			j.sink.refreshTTL(busEtaTTLPatterns(city))
		}
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_position error=%v", city, err)
		return
	}
	var droppedPosition int
	if _, err := dec.Token(); err == nil {
		for dec.More() {
			var p rawBusPosition
			if err := dec.Decode(&p); err == nil {
				posit = append(posit, p)
			} else {
				droppedPosition++
			}
		}
	}
	if droppedPosition > 0 {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=decode_dropped kind=position count=%d kept=%d", city, droppedPosition, len(posit))
	}
	flipopen()
	stations := make(map[string]*models.Bus_StationArrival)
	routes := make(map[string]*models.Bus_RouteArrival)
	// Assemble-inputs stage: collapse the raw TDX ETA array, group live positions,
	// and count route lengths, all keyed on canonical subroute/direction (ADR-0006).
	etamap := buildBusEtaMap(city, eat)
	busmap := buildBusPositionMap(city, posit)
	totalStops := buildTotalStops(city, mp)
	var weather *weatherData
	if wjson, wErr := j.sink.getString(shared.WeatherKey(city)); wErr == nil {
		var w weatherData
		if json.Unmarshal([]byte(wjson), &w) == nil {
			weather = &w
		}
	}
	now := j.now().In(taipei)
	holiday := isHoliday(now)
	fillKeys, fillUIDs := collectFillKeys(city, mp, etamap)
	todTime := now.Format("15:04:05")
	// Day-of-week mask only; holiday-aware schedules would need TDX SpecialDays
	// landing, as schedule rows carry no holiday flag from TDX's Mon-Sun fields.
	dayBit := 1 << ((int(now.Weekday()) + 6) % 7) // mask2 bit order: Monday=bit0..Sunday=bit6
	depMap := j.store.nextDepartures(ctx, dedupRouteDirPairs(fillKeys), todTime, dayBit)
	uidList := make([]string, 0, len(fillUIDs))
	for u := range fillUIDs {
		uidList = append(uidList, u)
	}
	travelAvgMap := j.store.travelAverages(ctx, uidList, now.Hour(), int(now.Weekday()))
	maxAvgMap := maxTravelAvgByRoute(travelAvgMap)
	// baselineFor returns the schedule+travel-average arrival for a stop, shared by
	// the delay-propagation observation pass and the downstream fill.
	baselineFor := func(b busStationmap, uid string, dir int32) time.Time {
		rk := routeDirKey{uid, dir}
		avgKey := travelAvgKey{uid, dir, b.StopUID, now.Hour(), int(now.Weekday())}
		avgVal, hasAvg := travelAvgMap[avgKey]
		return baselineArrival(
			busStopCtx{
				subRouteUID:  uid,
				direction:    dir,
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
	// Delay-propagation observation stage: record each en-route vehicle's delay
	// against the schedule+travel-average baseline, keyed per route/direction, for
	// the downstream fill to inherit.
	upstreamByRoute := buildUpstreamObs(city, mp, etamap, now, baselineFor)
	var predictionRows []predictionRecord
	var historyRows [][]interface{}
	for _, b := range mp {
		// Canonicalize before every downstream write: the Redis route key, the
		// bus_eta_history row, dispatched notifications, and the app-facing protos
		// all key on the canonical UID plus derived direction (ADR-0006), so the
		// router (which no longer normalizes) and the training data see one
		// identity space. For non-InterCity, this is identity.
		uid, dir := shared.CanonicalSubroute(city, b.SubRouteUID, b.Direction)
		eta, ok := etamap[etaKey{uid, dir, b.StopUID}]
		status := uint8(67)
		var est int32
		var stime string
		if ok {
			est = adjustedEstimate(eta, now)
			status = eta.StopStatus
			stime = eta.SrcUpdateTime
		}
		if status == 0 {
			ts := totalStops[uid]
			plateNumb, busSpeed, busDist := nearestBus(b.Lat, b.Lon, busmap[uid])
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
			// Priority: delay propagation (a fresh upstream vehicle's decayed delay
			// on the schedule+travel-average baseline) sits above the XGBoost model.
			// It applies only when the same route has a live bus upstream of this
			// stop; otherwise fall through to predictNextBusTime.
			var predictedArrival time.Time
			var predSource string
			if propArrival, propOK := propagateDelay(
				baselineFor(b, uid, int32(dir)), int(b.StopSequence), upstreamByRoute[rk], now,
			); propOK {
				predictedArrival = propArrival
				predSource = sourcePropagation
				eta.NextBusTime = propArrival.Format(time.RFC3339)
			} else {
				avgKey := travelAvgKey{uid, int32(dir), b.StopUID, now.Hour(), int(now.Weekday())}
				avgVal, hasAvg := travelAvgMap[avgKey]
				eta.NextBusTime = predictNextBusTime(weather,
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
				if eta.NextBusTime != "" {
					if t, err := time.Parse(time.RFC3339, eta.NextBusTime); err == nil {
						predictedArrival = t
						// The model tier interpolates from travel averages when a
						// per-stop average is missing; label by whether that average
						// existed so accuracy can be compared model vs travel_avg.
						if hasAvg {
							predSource = sourceModel
						} else {
							predSource = sourceTravelAvg
						}
					}
				}
			}
			// Record the prediction (actual pending) for daily MAE measurement.
			if predSource != "" && !predictedArrival.IsZero() {
				predictionRows = append(predictionRows, predictionRecord{
					subRouteUID:   uid,
					direction:     int16(dir),
					stopUID:       b.StopUID,
					source:        predSource,
					predictedAt:   now,
					predictedSecs: int(predictedArrival.Sub(now).Round(time.Second).Seconds()),
				})
			}
		}
		groupUID := b.GroupUID
		if groupUID == "" {
			groupUID = b.StationUID
		}
		groupName := b.GroupName
		if groupName == "" {
			groupName = b.StationName
		}
		if _, exists := stations[groupUID]; !exists {
			stations[groupUID] = &models.Bus_StationArrival{
				StationName: groupName,
				StationUid:  make([]string, 0),
				Routes:      make([]*models.Bus_StopEstimate, 0),
			}
		}
		arrivalUnix := computeArrivalUnix(status, est, eta.NextBusTime, now)
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
			ArrivalUnix:   arrivalUnix,
		})
		if shouldDispatchBusArrival(ok, status, est) {
			j.notifier.Arrival(ctx, "bus", uid, b.StopUID, strconv.Itoa(int(dir)), est)
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
			ArrivalUnix:   arrivalUnix,
		})
	}
	pipe := j.sink.pipeline()
	for groupUID, pb := range stations {
		data, _ := proto.Marshal(pb)
		key := shared.BusStationEtaKey(city, groupUID)
		pipe.Set(key, data, busLiveTTL)
		pipe.Publish(key, data)
	}
	for uid, pb := range routes {
		data, _ := proto.Marshal(pb)
		key := shared.BusRouteEtaKey(uid)
		pipe.Set(key, data, busLiveTTL)
		pipe.Publish(key, data)
	}
	err = pipe.Exec()
	if err != nil {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=redis_error error=%v station_count=%d route_count=%d eat_count=%d posit_count=%d", city, err, len(stations), len(routes), len(eat), len(posit))
	} else {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=redis_success station_count=%d route_count=%d eat_count=%d posit_count=%d", city, len(stations), len(routes), len(eat), len(posit))
	}
	j.store.saveHistory(ctx, historyRows)
	j.store.recordPredictions(ctx, predictionRows)
}

// shouldDispatchBusArrival reports whether a live ETA warrants an arrival
// notification: a matched TDX ETA (found), a bus en route (StopStatus 0), and a
// positive remaining time. A non-positive estimate means the bus has effectively
// arrived or passed, so no reminder is sent.
func shouldDispatchBusArrival(found bool, status uint8, etaSeconds int32) bool {
	return found && status == 0 && etaSeconds > 0
}
