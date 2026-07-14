package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"slices"
	"strconv"
	"sync"
	"time"

	"github.com/go-redis/redis"
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
	Arrival(ctx context.Context, routeType, routeKey, stopKey, direction string, etaSeconds int32, arrivingPlate string)
}

type busLiveJob struct {
	fetch    boundFetch
	sink     liveSink
	store    busEtaStore
	notifier busArrivalNotifier
	now      func() time.Time
}

const busFeedCacheTTL = 10 * time.Minute

var errBusFeedCacheMiss = errors.New("bus raw feed cache missing")

func readBusFeedCache[T any](sink liveSink, key string) ([]T, error) {
	raw, err := sink.getString(key)
	if errors.Is(err, redis.Nil) || (err == nil && raw == "") {
		return nil, fmt.Errorf("%w: %s", errBusFeedCacheMiss, key)
	}
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", key, err)
	}
	var values []T
	if err := json.Unmarshal([]byte(raw), &values); err != nil {
		return nil, fmt.Errorf("decode %s: %w", key, err)
	}
	if values == nil {
		return nil, fmt.Errorf("%w: %s contains JSON null", errBusFeedCacheMiss, key)
	}
	return values, nil
}

func invalidateTDXFetch(fetch *shared.TDXFetch) error {
	if fetch == nil || fetch.Invalidate == nil {
		return errors.New("TDX fetch has no marker invalidation callback")
	}
	return fetch.Invalidate()
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
	eat = make([]rawBusEsimated, 0)
	opening, err := dec.Token()
	if err != nil || opening != json.Delim('[') {
		return nil, false
	}
	for dec.More() {
		var e rawBusEsimated
		if err := dec.Decode(&e); err != nil {
			return eat, false
		}
		eat = append(eat, e)
	}
	closing, err := dec.Token()
	if err != nil || closing != json.Delim(']') {
		return eat, false
	}
	var trailing any
	if err := dec.Decode(&trailing); err != io.EOF {
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
) error {
	log.Infof("[BUS_ETA] action=Bus_eta event=start")
	job := busLiveJob{
		fetch:    fetch,
		sink:     sink,
		store:    pgBusEtaStore{db: db},
		notifier: dispatcher,
		now:      time.Now,
	}
	sem := make(chan struct{}, 4)
	errCh := make(chan error, len(cities))
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
			if err := job.runCity(ctx, city); err != nil {
				errCh <- fmt.Errorf("bus %s: %w", city, err)
			}
		}(city)
	}
	wg.Wait()
	close(errCh)
	var jobErr error
	for err := range errCh {
		jobErr = errors.Join(jobErr, err)
	}
	log.Infof("[BUS_ETA] action=Bus_eta event=complete")
	return jobErr
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
func (j busLiveJob) runCity(ctx context.Context, city string) error {
	log.Infof("[BUS_ETA] action=Bus_eta city=%s event=city_start", city)
	prefix := citymap[city]
	if prefix == "" {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_empty reason=no_prefix", city)
		return nil
	}
	generation, generationErr := j.sink.getString(shared.BusStaticGenerationKey(city))
	if generationErr != nil {
		// Redis is the cross-process signal, but an outage must not stop realtime
		// service. The local cache falls back to its bounded TTL in this case.
		generation = ""
	}
	mp, cached := cachedBusStaticMapFrom(&busStaticMapCache, prefix, generation, j.now())
	if !cached {
		var err error
		mp, err = j.store.staticStops(ctx, prefix)
		if err != nil || len(mp) <= 0 {
			log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_empty reason=no_stations", city)
			return err
		}
		storeBusStaticMapIn(&busStaticMapCache, prefix, mp, generation, j.now())
	}
	if len(mp) <= 0 {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_empty reason=no_stations", city)
		return nil
	}
	var etaURL string
	if city == "InterCity" {
		etaURL = "/v2/Bus/EstimatedTimeOfArrival/InterCity"
	} else {
		etaURL = fmt.Sprintf("/v2/Bus/EstimatedTimeOfArrival/City/%s", city)
	}
	etaFetch, err := j.fetch(ctx, etaURL, "bus_EstimatedTimeOfArrival"+city)
	if err != nil {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_eta error=%v", city, err)
		return err
	}
	var eat []rawBusEsimated
	var etaRaw []byte
	if etaFetch.Modified {
		var complete bool
		eat, complete = decodeBusEtaArray(etaFetch.Decoder)
		closeErr := etaFetch.Close()
		var decodeErr error
		if !complete {
			decodeErr = errors.New("decode bus ETA response: incomplete JSON array")
		}
		if decodeErr != nil || closeErr != nil {
			j.sink.refreshTTL(busEtaTTLPatterns(city))
			return errors.Join(decodeErr, closeErr)
		}
		etaRaw, err = json.Marshal(eat)
		if err != nil {
			return err
		}
	}

	posit := make([]rawBusPosition, 0)
	var positionURL string
	if city == "InterCity" {
		positionURL = "/v2/Bus/RealTimeByFrequency/InterCity"
	} else {
		positionURL = fmt.Sprintf("/v2/Bus/RealTimeByFrequency/City/%s", city)
	}
	positionFetch, err := j.fetch(ctx, positionURL, "bus_RealTimeByFrequency"+city)
	if err != nil {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=skip_position error=%v", city, err)
		return err
	}
	var positionRaw []byte
	if positionFetch.Modified {
		decodeErr := decodeLiveItems(positionFetch.Decoder, func(p rawBusPosition) error {
			posit = append(posit, p)
			return nil
		})
		closeErr := positionFetch.Close()
		if decodeErr != nil || closeErr != nil {
			return errors.Join(decodeErr, closeErr)
		}
		positionRaw, err = json.Marshal(posit)
		if err != nil {
			return err
		}
	}

	etaCacheKey := shared.BusETARawKey(city)
	positionCacheKey := shared.BusPositionRawKey(city)
	pipe := j.sink.pipeline()
	var cacheErr error
	if etaFetch.Modified {
		pipe.Set(etaCacheKey, etaRaw, busFeedCacheTTL)
	} else {
		eat, err = readBusFeedCache[rawBusEsimated](j.sink, etaCacheKey)
		if err != nil {
			cacheErr = errors.Join(cacheErr, err)
		} else {
			pipe.Expire(etaCacheKey, busFeedCacheTTL)
		}
	}
	if positionFetch.Modified {
		pipe.Set(positionCacheKey, positionRaw, busFeedCacheTTL)
	} else {
		posit, err = readBusFeedCache[rawBusPosition](j.sink, positionCacheKey)
		if err != nil {
			cacheErr = errors.Join(cacheErr, err)
		} else {
			pipe.Expire(positionCacheKey, busFeedCacheTTL)
		}
	}

	if cacheErr != nil {
		if !etaFetch.Modified && !positionFetch.Modified {
			j.sink.refreshTTL(busEtaTTLPatterns(city))
		}
		execErr := pipe.Exec()
		var ackErr error
		if execErr == nil {
			if etaFetch.Modified {
				ackErr = errors.Join(ackErr, acknowledgeTDXFetch(etaFetch))
			}
			if positionFetch.Modified {
				ackErr = errors.Join(ackErr, acknowledgeTDXFetch(positionFetch))
			}
		}
		var invalidateErr error
		if !etaFetch.Modified {
			invalidateErr = errors.Join(invalidateErr, invalidateTDXFetch(etaFetch))
		}
		if !positionFetch.Modified {
			invalidateErr = errors.Join(invalidateErr, invalidateTDXFetch(positionFetch))
		}
		return errors.Join(cacheErr, execErr, ackErr, invalidateErr)
	}

	if !etaFetch.Modified && !positionFetch.Modified {
		if err := pipe.Exec(); err != nil {
			return err
		}
		j.sink.refreshTTL(busEtaTTLPatterns(city))
		return nil
	}
	stations := make(map[string]*models.Bus_StationArrival)
	routes := make(map[string]*models.Bus_RouteArrival)
	// Assemble-inputs stage: collapse the raw TDX ETA array, group live positions,
	// and count route lengths, all keyed on canonical subroute/direction (ADR-0006).
	etamap := buildBusEtaMap(city, eat, mp)
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
		// Resolved in the status==0 branch below (a live bus is only matched
		// to the stop when one is en route); reused at the dispatch site so
		// the arrival reminder can pin to this plate.
		var plateNumb *string
		if status == 0 {
			ts := totalStops[uid]
			var busSpeed *int16
			var busDist *int
			plateNumb, busSpeed, busDist = nearestBus(b.Lat, b.Lon, busmap[uid])
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
			Destination:   b.Destination,
			Direction:     int32(dir),
			Estimate:      est,
			NextBusTime:   eta.NextBusTime,
			StopStatus:    int32(status),
			SrcUpdateTime: stime,
			Buses:         busmap[uid],
			ArrivalUnix:   arrivalUnix,
		})
		if shouldDispatchBusArrival(ok, status, est) {
			plate := ""
			if plateNumb != nil {
				plate = *plateNumb
			}
			j.notifier.Arrival(ctx, "bus", uid, b.StopUID, strconv.Itoa(int(dir)), est, plate)
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
	for groupUID, pb := range stations {
		data, err := proto.Marshal(pb)
		if err != nil {
			return err
		}
		key := shared.BusStationEtaKey(city, groupUID)
		pipe.Set(key, data, busLiveTTL)
		pipe.Publish(key, data)
	}
	for uid, pb := range routes {
		data, err := proto.Marshal(pb)
		if err != nil {
			return err
		}
		key := shared.BusRouteEtaKey(uid)
		pipe.Set(key, data, busLiveTTL)
		pipe.Publish(key, data)
	}
	err = pipe.Exec()
	if err != nil {
		log.Infof("[BUS_ETA] action=Bus_eta city=%s event=redis_error error=%v station_count=%d route_count=%d eat_count=%d posit_count=%d", city, err, len(stations), len(routes), len(eat), len(posit))
		return err
	}
	log.Infof("[BUS_ETA] action=Bus_eta city=%s event=redis_success station_count=%d route_count=%d eat_count=%d posit_count=%d", city, len(stations), len(routes), len(eat), len(posit))
	var ackErr error
	if etaFetch.Modified {
		ackErr = errors.Join(ackErr, acknowledgeTDXFetch(etaFetch))
	}
	if positionFetch.Modified {
		ackErr = errors.Join(ackErr, acknowledgeTDXFetch(positionFetch))
	}
	if ackErr != nil {
		return ackErr
	}
	j.store.saveHistory(ctx, historyRows)
	j.store.recordPredictions(ctx, predictionRows)
	return nil
}

// shouldDispatchBusArrival reports whether a live ETA warrants an arrival
// notification: a matched TDX ETA (found), a bus en route (StopStatus 0), and a
// positive remaining time. A non-positive estimate means the bus has effectively
// arrived or passed, so no reminder is sent.
func shouldDispatchBusArrival(found bool, status uint8, etaSeconds int32) bool {
	return found && status == 0 && etaSeconds > 0
}
