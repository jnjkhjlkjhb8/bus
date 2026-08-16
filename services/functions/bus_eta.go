package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"runtime/debug"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/functions/notify"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
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

func busPositionIdentity(subRouteUID string, direction uint8) string {
	return fmt.Sprintf("%s\x00%d", subRouteUID, direction)
}

// _busPlatePassedStop is the value TDX sends in an N1 PlateNumb to say the
// vehicle has already passed that stop. It names no vehicle, so it must not
// reach the wire, an arrival push, or a history row's vehicle identity.
const _busPlatePassedStop = "-1"

func normalizeArrivalPlate(plate string) string {
	normalized := strings.ToUpper(strings.TrimSpace(plate))
	if normalized == _busPlatePassedStop {
		return ""
	}
	return normalized
}

// How stale a vehicle's own GPS reading may be before it stops being published.
// TDX keeps the last A1 record per vehicle for two hours to cover on-board units
// that report minutes late, so without this an hour-old position is still drawn
// on the route and still competes for nearest-bus.
const _busPositionMaxAge = 10 * time.Minute

// positionFresh reports whether a vehicle's GPS reading is recent enough to
// publish. An unparseable GPSTime (gpsTimeUnix 0) is kept: it carries no age to
// judge, and the app already renders it as 無定位.
func positionFresh(gpsTimeUnix int64, now time.Time) bool {
	if gpsTimeUnix == 0 {
		return true
	}
	return now.Sub(time.Unix(gpsTimeUnix, 0)) <= _busPositionMaxAge
}

func buildDirectionAwareBusPositionMap(city string, positions []rawBusPosition, now time.Time) map[string][]*models.BusPosition {
	byIdentity := make(map[string][]*models.BusPosition)
	for _, position := range positions {
		gpsTimeUnix := parseGPSTimeUnix(position.GPSTime)
		if !positionFresh(gpsTimeUnix, now) {
			continue
		}
		uid, direction := shared.CanonicalSubroute(city, position.SubRouteUID, position.Direction)
		key := busPositionIdentity(uid, direction)
		byIdentity[key] = append(byIdentity[key], &models.BusPosition{
			PlateNumb:   position.PlateNumb,
			PositionLon: position.BusPosition.PositionLon,
			PositionLat: position.BusPosition.PositionLat,
			Speed:       int32(position.Speed),
			// Rounded, not truncated: the wire field is whole degrees, and a
			// fractional bearing is a real reading rather than a value with a
			// meaningful floor — 359.6° is north, not 359°.
			Azimuth:     int32(math.Round(position.Azimuth)),
			DutyStatus:  int32(position.DutyStatus),
			BusStatus:   int32(position.BusStatus),
			GpsTimeUnix: gpsTimeUnix,
			// Unset for every feed but Data.taipei's, which is what the wire enum's
			// zero value means (models/bus.proto).
			CrowdLevel: position.CrowdLevel,
		})
	}
	return byIdentity
}

type busArrivalNotifier interface {
	Arrivals(context.Context, []notify.ArrivalEvent) error
}

type busArrivalBatch struct {
	mu     sync.Mutex
	target busArrivalNotifier
	events []notify.ArrivalEvent
}

func (b *busArrivalBatch) Arrivals(_ context.Context, events []notify.ArrivalEvent) error {
	b.mu.Lock()
	b.events = append(b.events, events...)
	b.mu.Unlock()
	return nil
}

func (b *busArrivalBatch) flush(ctx context.Context) error {
	if b.target == nil {
		return nil
	}
	b.mu.Lock()
	events := append([]notify.ArrivalEvent(nil), b.events...)
	b.events = nil
	b.mu.Unlock()
	return b.target.Arrivals(ctx, events)
}

// _busEtaSkip lists the cities with no bus network to resolve live ETA against,
// so the tick does not spend a TDX request and a static-map lookup per city on
// them. It is deliberately narrower than removing the city from `cities`, which
// every ingestion loop also reads: Matsu's static datasets still land, there is
// just no stop map for a live estimate to attach to. Without this the tick logs
// skip_empty=no_stations twice a minute forever, which buries the same line
// arriving for a city that genuinely lost its stop map.
var _busEtaSkip = map[string]struct{}{
	"LienchiangCounty": {},
}

// vehicleSource is a live vehicle feed richer than TDX's, layered over the TDX
// positions for the cities it covers. A nil map, or a city missing from it,
// leaves that city on TDX alone — which is what the tests run with, so none
// of them reach the network for it.
type vehicleSource interface {
	positions(context.Context) ([]rawBusPosition, error)
}

type busLiveJob struct {
	fetch    boundFetch
	sink     liveSink
	store    busEtaStore
	notifier busArrivalNotifier
	vehicles map[string]vehicleSource
	eta      map[string]etaSource
	now      func() time.Time
	// snapshot is fixed for the whole run so every city lands on the same side
	// of the history sampling clock (see snapshotTick).
	snapshot bool
	// demandDataset is the liveDemandGate dataset name, or "" to fetch every
	// city every tick. Only the TDX-backed job sets it: busEtaFast reads
	// Data.taipei, which costs no TDX quota, so gating it would slow down the
	// two busiest cities to save nothing (FDPL-90).
	demandDataset string
}

const _busFeedCacheTTL = 10 * time.Minute

var errBusFeedCacheMiss = errors.New("bus raw feed cache missing")

func readBusFeedCache[T any](ctx context.Context, sink liveSink, key string) ([]T, error) {
	raw, err := sink.getString(ctx, key)
	if errors.Is(err, redis.Nil) || (err == nil && raw == "") {
		return nil, _oops.With("key", key).Wrapf(errBusFeedCacheMiss, "bus feed cache lookup")
	}
	if err != nil {
		return nil, _oops.With("key", key).Wrapf(err, "read")
	}
	var values []T
	if err := json.Unmarshal([]byte(raw), &values); err != nil {
		return nil, _oops.With("key", key).Wrapf(err, "decode")
	}
	if values == nil {
		return nil, _oops.With("key", key).Wrapf(errBusFeedCacheMiss, "contains JSON null")
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
	if err := dec.Decode(&trailing); !errors.Is(err, io.EOF) {
		return eat, false
	}
	return eat, true
}

// _busEtaFastCities are Taipei and New Taipei: the cities runCity gets its ETA
// for from Data.taipei rather than TDX (FDPL-66 Phase 4), so they are not
// bound to the shared TDX cadence and run on their own faster cron instead
// (busEtaFast, live.go "@every 20s" — see busEtaFastTickInterval for why 20s
// rather than mrt's 15s).
var _busEtaFastCities = func() []string {
	fast := make([]string, 0, len(_dataTaipeiDynamicCities))
	for city := range _dataTaipeiDynamicCities {
		fast = append(fast, city)
	}
	sort.Strings(fast)
	return fast
}()

// _busEtaSlowCities is cities minus busEtaFastCities: every city still polled
// for ETA on the shared "@every 30s" TDX cadence.
var _busEtaSlowCities = func() []string {
	fast := make(map[string]struct{}, len(_dataTaipeiDynamicCities))
	for _, city := range _busEtaFastCities {
		fast[city] = struct{}{}
	}
	slow := make([]string, 0, len(_cities))
	for _, city := range _cities {
		if _, isFast := fast[city]; !isFast {
			slow = append(slow, city)
		}
	}
	return slow
}()

// busEta refreshes live bus arrivals for busEtaSlowCities on the 30s cron.
// Cities are processed concurrently, capped at 4 in flight (sem). It blocks
// until every city finishes.
func busEta(
	ctx context.Context,
	fetch boundFetch,
	sink liveSink,
	db *pgxpool.Pool,
	dispatcher *notify.Dispatcher,
) error {
	return runBusEtaTick(ctx, "bus_eta", _busEtaSlowCities, _busEtaTickInterval,
		nil, nil, fetch, sink, db, dispatcher, "bus_eta")
}

// busEtaFast refreshes busEtaFastCities' live bus arrivals on their own 15s
// cron, independent of TDX (FDPL-66 Phase 4).
func busEtaFast(
	ctx context.Context,
	fetch boundFetch,
	sink liveSink,
	db *pgxpool.Pool,
	dispatcher *notify.Dispatcher,
) error {
	// One feed per Data.taipei city, shared between the vehicle overlay and the
	// ETA override: both read the same blob container.
	vehicles := make(map[string]vehicleSource, len(_busEtaFastCities))
	etaFeeds := make(map[string]etaSource, len(_busEtaFastCities))
	for _, city := range _busEtaFastCities {
		feed := newDataTaipeiFeed(city)
		vehicles[city] = feed
		etaFeeds[city] = feed
	}
	return runBusEtaTick(ctx, "bus_eta_fast", _busEtaFastCities, _busEtaFastTickInterval,
		vehicles, etaFeeds, fetch, sink, db, dispatcher, "")
}

// runBusEtaTick is the shared body of busEta and busEtaFast: build the job,
// run cityList, log start/complete under component so the two crons are
// distinguishable in the logs.
func runBusEtaTick(
	ctx context.Context,
	component string,
	cityList []string,
	tickInterval time.Duration,
	vehicles map[string]vehicleSource,
	eta map[string]etaSource,
	fetch boundFetch,
	sink liveSink,
	db *pgxpool.Pool,
	dispatcher *notify.Dispatcher,
	demandDataset string,
) error {
	zap.S().Infow("start", "component", component, "action", "Bus_eta", "event", "start")
	job := busLiveJob{
		fetch:    fetch,
		sink:     sink,
		store:    pgBusEtaStore{db: db},
		vehicles: vehicles,
		eta:      eta,
		now:      time.Now,
		snapshot: snapshotTick(time.Now(), tickInterval),

		demandDataset: demandDataset,
	}
	jobErr := runBusEtaCities(ctx, cityList, &job, dispatcher)
	zap.S().Infow("complete", "component", component, "action", "Bus_eta", "event", "complete")
	return jobErr
}

// runCityGuarded runs one city and turns a panic into that city's error.
//
// Every city runs in its own goroutine, and a panic in a goroutine takes the
// whole process down: without this guard, one city's bad data costs every other
// city the observations it has gathered but not yet written, since saveHistory is
// the last step of runCity. That is a plausible reading of the history table,
// where each city's rows arrive in scattered bursts rather than continuously.
//
// Recovering does not repair the city that failed; its tick is still lost. What
// it buys is that the failure stays local, and that the panic is named in the log
// with its stack instead of being visible only as a container restart.
func (j busLiveJob) runCityGuarded(ctx context.Context, city string) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = _oops.With("rows", r).Errorf("panic")
			zap.S().Errorw("panic",
				"component", "bus_eta",
				"action", "Bus_eta",
				"city", city,
				"event", "panic",
				"value", r,
				"stack", debug.Stack(),
			)
		}
	}()
	return j.runCity(ctx, city)
}

// shouldRunCity reports whether this tick fetches city.
//
// A job with no demandDataset always does. Otherwise the demand gate decides,
// with one exception: a snapshot tick is never skipped, whoever is or is not
// watching. snapshotTick is a fixed 30s window per 10 minutes of wall clock, so
// a reduced-cadence fetch lands inside it only about one time in twenty —
// gating it would cost an unwatched city roughly nine tenths of its
// bus_eta_history, and those rows are the only input segmentsByEstimate reduces
// into bus_segment_time. Rural cities are both the least watched and the ones
// whose ETAs lean hardest on those predictions, so this is the one place the
// gate must not save a request. It costs six extra fetches per city per hour.
func (j busLiveJob) shouldRunCity(ctx context.Context, city string) bool {
	if j.demandDataset == "" || j.snapshot {
		return true
	}
	return liveDemandGate(ctx, j.sink, j.demandDataset, city)
}

func runBusEtaCities(ctx context.Context, cityNames []string, job *busLiveJob, target busArrivalNotifier) error {
	arrivalBatch := &busArrivalBatch{target: target}
	job.notifier = arrivalBatch
	sem := make(chan struct{}, 4)
	errCh := make(chan error, len(cityNames))
	var wg sync.WaitGroup
	for _, city := range cityNames {
		if city == "ChanghuaCounty" || city == "NantouCounty" {
			continue
		}
		wg.Add(1)
		go func(city string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			if !job.shouldRunCity(ctx, city) {
				// Nobody is watching this city and it was fetched within the
				// reduced cadence. Its published ETAs are still the best answer
				// available, and the reduced cadence outlives busLiveTTL, so the
				// skip re-arms them exactly as a 304 would rather than letting
				// the city go blank between fetches (CONTEXT.md 304→TTL rule).
				if err := job.sink.refreshTTL(ctx, busEtaTTLPatterns(city)); err != nil {
					errCh <- _oops.With("city", city).Wrapf(err, "refresh unwatched bus ETA TTLs")
				}
				return
			}
			if err := job.runCityGuarded(ctx, city); err != nil {
				errCh <- _oops.With("city", city).Wrapf(err, "bus ETA city run")
			}
		}(city)
	}
	wg.Wait()
	close(errCh)
	var jobErr error
	for err := range errCh {
		jobErr = errors.Join(jobErr, err)
	}
	if err := arrivalBatch.flush(ctx); err != nil {
		jobErr = errors.Join(jobErr, _oops.Wrapf(err, "dispatch bus arrival reminders"))
	}
	return jobErr
}

// busEtaTTLPatterns returns the station-group and route ETA key patterns for one
// city, paired with the 180s window to re-arm. It is the per-city input to the
// sink's 304→TTL refresh (CONTEXT.md): the cached arrival instants stay valid
// across a 304, so their snapshots must outlive the polling gap.
func busEtaTTLPatterns(city string) []ttlPattern {
	return []ttlPattern{
		{pattern: shared.BusStationEtaPattern(city), ttl: _busLiveTTL},
		{pattern: shared.BusRouteEtaPattern(_citymap[city]), ttl: _busLiveTTL},
	}
}

// busLiveJob.runCity builds and publishes one city's bus arrivals. It joins the
// static stop map (cached per prefix) with live TDX ETAs and vehicle positions,
// then: records history rows for stops with a bus en route (StopStatus 0); fills
// a predicted NextBusTime for stops flagged status 1 with no TDX NextBusTime,
// using the next scheduled departure plus accumulated segment times and the XGBoost
// correction (predictNextBusTime); attaches the nearest live vehicle to each
// stop; and dispatches arrival notifications. Results are written to Redis both
// as SET snapshots (180s TTL) and PUBLISH events, keyed per station and per route.
func (j busLiveJob) runCity(ctx context.Context, city string) (err error) {
	// A city run that aborts before it republishes leaves the previous snapshot
	// in Redis with its original TTL still counting down, so a run of failures
	// can let still-valid arrival instants expire (CONTEXT.md 304→TTL rule).
	// Re-arming happens here rather than at each abort because runCity has
	// thirteen error returns and only two used to do it — the ETA feed's decode
	// error did, its marshal error and the whole position-feed half did not.
	// Nothing to re-arm once the snapshot is published: that write sets a fresh
	// TTL itself. A dead context cannot refresh anything, so it is left alone
	// rather than joining a second error onto the first.
	published := false
	defer func() {
		if err == nil || published || ctx.Err() != nil {
			return
		}
		if refreshErr := j.sink.refreshTTL(ctx, busEtaTTLPatterns(city)); refreshErr != nil {
			err = errors.Join(err, refreshErr)
		}
	}()
	if _, skip := _busEtaSkip[city]; skip {
		return nil
	}
	zap.S().Infow("city start", "component", "bus_eta", "action", "Bus_eta", "city", city, "event", "city_start")
	prefix := _citymap[city]
	if prefix == "" {
		zap.S().Warnw("skip empty",
			"component", "bus_eta",
			"action", "Bus_eta",
			"city", city,
			"event", "skip_empty",
			"reason", "no_prefix",
		)
		return nil
	}
	generation, generationErr := j.sink.getString(ctx, shared.BusStaticGenerationKey(city))
	if generationErr != nil {
		// Redis is the cross-process signal, but an outage must not stop realtime
		// service. The local cache falls back to its bounded TTL in this case.
		generation = ""
	}
	mp, cached := cachedBusStaticMapFrom(&_busStaticMapCache, prefix, generation, j.now())
	if !cached {
		var err error
		mp, err = j.store.staticStops(ctx, prefix)
		if err != nil {
			return _oops.With("city", city).Wrapf(err, "load static stops")
		}
		if len(mp) == 0 {
			// No static stops yet (a city the loader has not landed): nothing to
			// resolve live ETA against, so skip the tick rather than fail it.
			zap.S().Warnw("skip empty",
				"component", "bus_eta",
				"action", "Bus_eta",
				"city", city,
				"event", "skip_empty",
				"reason", "no_stations",
			)
			return nil
		}
		storeBusStaticMapIn(&_busStaticMapCache, prefix, mp, generation, j.now())
	}
	if len(mp) == 0 {
		zap.S().Warnw("skip empty",
			"component", "bus_eta",
			"action", "Bus_eta",
			"city", city,
			"event", "skip_empty",
			"reason", "no_stations",
		)
		return nil
	}
	var (
		eat      []rawBusEsimated
		etaRaw   []byte
		etaFetch *shared.TDXFetch
	)
	// etaModified drives the same cache-write/observed logic a TDX 304 would:
	// a Data.taipei city has no such signal (source is checked in a moment)
	// and its blob is treated as always fresh, since the whole job — and so
	// this feed's own etag cache — is rebuilt every tick anyway.
	etaModified := true
	if source, ok := j.eta[city]; ok {
		eat, err = source.estimates(ctx)
		if err != nil {
			return _oops.With("city", city).Wrapf(err, "fetch bus ETA")
		}
		etaRaw, err = json.Marshal(eat)
		if err != nil {
			return err
		}
	} else {
		etaURL := fmt.Sprintf("/v2/Bus/EstimatedTimeOfArrival/City/%s", city)
		if city == "InterCity" {
			etaURL = "/v2/Bus/EstimatedTimeOfArrival/InterCity"
		}
		etaFetch, err = j.fetch(ctx, etaURL, "bus_EstimatedTimeOfArrival"+city)
		if err != nil {
			return _oops.With("city", city).Wrapf(err, "fetch bus ETA")
		}
		etaModified = etaFetch.Modified
		if etaFetch.Modified {
			var complete bool
			eat, complete = decodeBusEtaArray(etaFetch.Decoder)
			closeErr := etaFetch.Close()
			var decodeErr error
			if !complete {
				decodeErr = errors.New("decode bus ETA response: incomplete JSON array")
			}
			if decodeErr != nil || closeErr != nil {
				return errors.Join(decodeErr, closeErr)
			}
			etaRaw, err = json.Marshal(eat)
			if err != nil {
				return err
			}
		}
	}

	posit := make([]rawBusPosition, 0)
	positionURL := fmt.Sprintf("/v2/Bus/RealTimeByFrequency/City/%s", city)
	if city == "InterCity" {
		positionURL = "/v2/Bus/RealTimeByFrequency/InterCity"
	}
	positionFetch, err := j.fetch(ctx, positionURL, "bus_RealTimeByFrequency"+city)
	if err != nil {
		return _oops.With("city", city).Wrapf(err, "fetch bus positions")
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
	if etaModified {
		pipe.Set(etaCacheKey, etaRaw, _busFeedCacheTTL)
	} else {
		eat, err = readBusFeedCache[rawBusEsimated](ctx, j.sink, etaCacheKey)
		if err != nil {
			cacheErr = errors.Join(cacheErr, err)
		} else {
			pipe.Expire(etaCacheKey, _busFeedCacheTTL)
		}
	}
	if positionFetch.Modified {
		pipe.Set(positionCacheKey, positionRaw, _busFeedCacheTTL)
	} else {
		posit, err = readBusFeedCache[rawBusPosition](ctx, j.sink, positionCacheKey)
		if err != nil {
			cacheErr = errors.Join(cacheErr, err)
		} else {
			pipe.Expire(positionCacheKey, _busFeedCacheTTL)
		}
	}

	if cacheErr != nil {
		execErr := pipe.Exec(ctx)
		var ackErr error
		if execErr == nil {
			// etaFetch is nil for a Data.taipei city (no TDX ETA fetch to
			// acknowledge or invalidate); etaModified is always true for one,
			// so neither branch below would otherwise skip it.
			if etaModified && etaFetch != nil {
				ackErr = errors.Join(ackErr, acknowledgeTDXFetch(etaFetch))
			}
			if positionFetch.Modified {
				ackErr = errors.Join(ackErr, acknowledgeTDXFetch(positionFetch))
			}
		}
		var invalidateErr error
		if etaFetch != nil && !etaModified {
			invalidateErr = errors.Join(invalidateErr, invalidateTDXFetch(etaFetch))
		}
		if !positionFetch.Modified {
			invalidateErr = errors.Join(invalidateErr, invalidateTDXFetch(positionFetch))
		}
		return errors.Join(cacheErr, execErr, ackErr, invalidateErr)
	}

	// An unchanged raw feed still produces a changed snapshot: every estimate is
	// aged against now (adjustedEstimate), so a city whose TDX endpoints answer
	// 304 for both feeds — Taoyuan does, indefinitely — must be rebuilt and
	// republished anyway. Returning here instead left subscribed clients on the
	// one frame they were seeded with, decaying it locally until every stop on
	// the route read 進站中. What is genuinely new information, and so gated on a
	// modified feed below, is the history and prediction rows: re-recording the
	// same TDX entry under a fresh timestamp would invent observations.
	observed := etaModified || positionFetch.Modified

	stations := make(map[string]*models.Bus_StationArrival)
	routes := make(map[string]*models.Bus_RouteArrival)
	// Assemble-inputs stage: collapse the raw TDX ETA array, group live positions,
	// and count route lengths, all keyed on canonical subroute/direction (ADR-0006).
	etamap := buildBusEtaMap(city, eat, mp)
	// Taipei's vehicles come from Data.taipei instead, which unlike TDX names the
	// subroute and the plate of each one (datataipei.go). Applied after the cache
	// branch above so the TDX rows it layers over are still the ones a 304 tick
	// restored, and a no-op for every other city.
	posit = j.overlayVehicles(ctx, city, posit)
	now := j.now().In(_taipei)
	busmap := buildDirectionAwareBusPositionMap(city, posit, now)
	atStopMap := buildBusAtStopMap(city, posit)
	// A2 names the stop a vehicle just entered or left, so where it is served it
	// replaces the proximity guess outright. The two feeds never cover the same
	// city — Data.taipei fills StopUID for Taipei, A2 for 公總 and the counties
	// it manages — so the merge order settles nothing in practice.
	for key, presence := range j.nearStops(ctx, city, now) {
		atStopMap[key] = presence
	}
	totalStops := buildTotalStops(mp)
	var weather *weatherData
	if wjson, wErr := j.sink.getString(ctx, shared.WeatherKey(city)); wErr == nil {
		var w weatherData
		if json.Unmarshal([]byte(wjson), &w) == nil {
			weather = &w
		}
	}
	holiday := isHoliday(now)
	fillKeys, fillUIDs := collectFillKeys(mp, etamap)
	todTime := now.Format("15:04:05")
	// Day-of-week mask only; holiday-aware schedules would need TDX SpecialDays
	// landing, as schedule rows carry no holiday flag from TDX's Mon-Sun fields.
	dayBit := 1 << ((int(now.Weekday()) + 6) % 7) // mask2 bit order: Monday=bit0..Sunday=bit6
	depMap := j.store.nextDepartures(ctx, dedupRouteDirPairs(fillKeys), todTime, dayBit)
	uidList := make([]string, 0, len(fillUIDs))
	for u := range fillUIDs {
		uidList = append(uidList, u)
	}
	offsetMap := j.store.stopOffsets(ctx, uidList)
	// baselineFor returns the schedule+running-time arrival for a stop, shared by
	// the delay-propagation observation pass and the downstream fill.
	baselineFor := func(b busStationmap, uid string, dir int32) time.Time {
		offsetSec, hasOffset := offsetMap[stopOffsetKey{uid, dir, b.StopUID}]
		return baselineArrival(predictionInputs{
			now:       now,
			nextDep:   depMap[routeDirKey{uid, dir}],
			offsetSec: offsetSec,
			hasOffset: hasOffset,
		})
	}
	// Delay-propagation observation stage: record each en-route vehicle's delay
	// against the schedule+running-time baseline, keyed per route/direction, for
	// the downstream fill to inherit.
	upstreamByRoute := buildUpstreamObs(mp, etamap, now, baselineFor)
	var (
		predictionRows        []predictionRecord
		historyRows           [][]any
		arrivalEvents         []notify.ArrivalEvent
		fillsWithoutDeparture int
	)
	for _, b := range mp {
		// mp is already canonical: the loader canonicalizes on the ingestion
		// boundary and nothing downstream re-derives it (ADR-0006). Re-running
		// CanonicalSubroute here would strip an InterCity UID a second time
		// (THB0968 -> THB096), missing the ETA feed's own canonical key and
		// aliasing the lettered variants onto their base route.
		uid, dir := b.SubRouteUID, b.Direction
		positionKey := busPositionIdentity(uid, dir)
		eta, ok := etaForStop(etamap, b)
		status := _busEtaNoReading
		var est int32
		var stime string
		if ok {
			est = adjustedEstimate(eta, now)
			status = eta.StopStatus
			stime = eta.SrcUpdateTime
			// A stale en-route entry is no reading, not an arrival: leaving it
			// at status 0 with a clamped 0 estimate would render 進站中 on every
			// stop the feed stopped updating, and dispatch an arrival push for
			// each one.
			if status == 0 && arrivingExpired(eta, now) {
				status = _busEtaNoReading
			}
		}
		// Resolved in the status==0 branch below (a live bus is only matched to the
		// stop when one is en route).
		var plateNumb *string
		if status == 0 {
			ts := totalStops[uid]
			var busSpeed *int16
			var busDist *int
			plateNumb, busSpeed, busDist = nearestBus(b.Lat, b.Lon, busmap[positionKey])
			// A feed that says which stop a vehicle entered names the bus outright,
			// so it displaces the proximity guess wherever it speaks (FDPL-66
			// Phase 2, and TDX's A2 events since FDPL-77). Neither covers more
			// than the stop each bus is standing at right now — every stop further
			// down the route still has nothing better than nearest-GPS. A2 names
			// the vehicle without measuring its speed, so the GPS reading stands
			// where the naming feed has none of its own.
			if plate, speed, dist, ok := busAtStop(atStopMap, busAtStopKey{uid, dir, b.StopUID}); ok {
				plateNumb, busDist = plate, dist
				if speed != nil {
					busSpeed = speed
				}
			}
			// The plate is the vehicle identity segment derivation groups a run by,
			// so it has to name the bus this estimate describes. Take TDX's own
			// PlateNumb from the selected ETA row, the same one dispatch uses; the
			// nearest-GPS plate is a proximity guess that can name a different bus at
			// each stop, splitting one run or stitching two together. Taipei and
			// NewTaipei publish no plate at all, so they keep the GPS fallback —
			// speed and distance stay GPS-derived either way.
			if p := normalizeArrivalPlate(eta.PlateNumb); p != "" {
				plateNumb = &p
			}
			// Only the history row is sampled. plateNumb above belongs to the live
			// path as well, so the test sits here rather than on the branch — and
			// it stays an if rather than a continue, because the loop still has
			// this stop's Redis payload to build below.
			if recordsHistory(est, j.snapshot) {
				var srcTime *time.Time
				if t, ok := parseSrcUpdateTime(stime); ok {
					srcTime = &t
				}
				var nextBusTimePtr *string
				if eta.NextBusTime != "" {
					nbtp := eta.NextBusTime
					nextBusTimePtr = &nbtp
				}
				// nil stays nil when the city has no weather reading: the history
				// columns are nullable and a zero would read as a real measurement.
				var weatherTemp, weatherPrecip, weatherWind, weatherHumid any
				if weather != nil {
					weatherTemp = weather.Temperature
					weatherPrecip = weather.Precipitation
					weatherWind = weather.WindSpeed
					weatherHumid = weather.Humidity
				}
				historyRows = append(historyRows, []any{
					uid, b.StopUID, int16(dir),
					int16(b.StopSequence), int16(ts), est, nextBusTimePtr, srcTime,
					city, int16(now.Hour()), int16(now.Weekday()), holiday,
					weatherTemp, weatherPrecip, weatherWind, weatherHumid,
					plateNumb, busSpeed, busDist, now,
				})
			}
		}
		if status == 1 && eta.NextBusTime == "" {
			rk := routeDirKey{uid, int32(dir)}
			// A fill with no scheduled departure to stand on has nothing but the
			// model left. TDX publishes some routes as headway (Frequencys) rather
			// than a timetable, and 公總-managed counties often publish times for
			// the first stop only, so this counts the population a headway-derived
			// baseline would serve (FDPL-85). Telling the two apart needs
			// Frequencys landed, which they are not.
			if depMap[rk].IsZero() {
				fillsWithoutDeparture++
			}
			// Priority: delay propagation (a fresh upstream vehicle's decayed delay
			// on the schedule+running-time baseline) sits above the XGBoost model.
			// It applies only when the same route has a live bus upstream of this
			// stop; otherwise fall through to predictNextBusTime.
			var predictedArrival time.Time
			var predSource string
			if propArrival, propOK := propagateDelay(
				baselineFor(b, uid, int32(dir)), int(b.StopSequence), upstreamByRoute[rk], now,
			); propOK {
				predictedArrival = propArrival
				predSource = _sourcePropagation
				eta.NextBusTime = propArrival.Format(time.RFC3339)
			} else {
				offsetSec, hasOffset := offsetMap[stopOffsetKey{uid, int32(dir), b.StopUID}]
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
						now:       now,
						nextDep:   depMap[rk],
						offsetSec: offsetSec,
						hasOffset: hasOffset,
					},
				)
				if eta.NextBusTime != "" {
					if t, err := time.Parse(time.RFC3339, eta.NextBusTime); err == nil {
						predictedArrival = t
						// Without an offset the model tier returns the bare departure
						// uncorrected, which is a schedule prediction rather than a
						// model one; label it as such so the two are measured apart.
						predSource = _sourceSchedule
						if hasOffset {
							predSource = _sourceModel
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
			Buses:         busmap[positionKey],
			ArrivalUnix:   arrivalUnix,
			CrowdLevel:    crowdForPlate(busmap[positionKey], plateNumb),
			IsLastBus:     eta.IsLastBus == 1,
		})
		if shouldDispatchBusArrival(ok, status, est) {
			arrivalEvents = append(arrivalEvents, notify.ArrivalEvent{
				RouteType: "bus", RouteKey: uid, StopKey: b.StopUID,
				Direction: strconv.Itoa(int(dir)), ETASeconds: est,
				ArrivingPlate: normalizeArrivalPlate(eta.PlateNumb),
			})
		}
		if _, ok = routes[uid]; !ok {
			routes[uid] = &models.Bus_RouteArrival{
				SubRouteUid: uid,
			}
		}
		routes[uid].Stops = append(routes[uid].Stops, &models.Bus_RouteEstimate{
			StopUid:       b.StopUID,
			Direction:     int32(dir),
			Estimate:      est,
			StopStatus:    int32(status),
			NextBusTime:   eta.NextBusTime,
			SrcUpdateTime: stime,
			Buses:         busmap[positionKey],
			StopSequence:  int32(b.StopSequence),
			ArrivalUnix:   arrivalUnix,
			PlateNumb:     normalizeArrivalPlate(eta.PlateNumb),
			CrowdLevel:    crowdForPlate(busmap[positionKey], plateNumb),
			IsLastBus:     eta.IsLastBus == 1,
		})
	}
	for groupUID, pb := range stations {
		data, err := proto.Marshal(pb)
		if err != nil {
			return err
		}
		key := shared.BusStationEtaKey(city, groupUID)
		pipe.Set(key, data, _busLiveTTL)
		pipe.Publish(key, data)
	}
	for uid, pb := range routes {
		data, err := proto.Marshal(pb)
		if err != nil {
			return err
		}
		key := shared.BusRouteEtaKey(uid)
		pipe.Set(key, data, _busLiveTTL)
		pipe.Publish(key, data)
	}
	err = pipe.Exec(ctx)
	if err != nil {
		return _oops.With("city", city).With("stations", len(stations)).With("routes", len(routes)).With("eat", len(eat)).With("posit", len(posit)).Wrapf(err, "publish bus realtime snapshot for (stations= routes= eta= positions=)")
	}
	published = true
	zap.S().Infow("redis success",
		"component", "bus_eta",
		"action", "Bus_eta",
		"city", city,
		"event", "redis_success",
		"station_count", len(stations),
		"route_count", len(routes),
		"eat_count", len(eat),
		"posit_count", len(posit),
		"frozen_eta_count", countFrozenEstimates(eat),
		"fill_without_departure_count", fillsWithoutDeparture,
	)
	var ackErr error
	if etaModified && etaFetch != nil {
		ackErr = errors.Join(ackErr, acknowledgeTDXFetch(etaFetch))
	}
	if positionFetch.Modified {
		ackErr = errors.Join(ackErr, acknowledgeTDXFetch(positionFetch))
	}
	if ackErr != nil {
		return ackErr
	}
	if j.notifier != nil {
		if err := j.notifier.Arrivals(ctx, arrivalEvents); err != nil {
			return _oops.With("city", city).Wrapf(err, "dispatch bus arrival reminders")
		}
	}
	if observed {
		j.store.saveHistory(ctx, historyRows)
		j.store.recordPredictions(ctx, predictionRows)
	}
	return nil
}

// shouldDispatchBusArrival reports whether a live ETA warrants an arrival
// notification: a matched TDX ETA (found), a bus en route (StopStatus 0), and a
// positive remaining time. A non-positive estimate means the bus has effectively
// arrived or passed, so no reminder is sent.
func shouldDispatchBusArrival(found bool, status uint8, etaSeconds int32) bool {
	return found && status == 0 && etaSeconds > 0
}
