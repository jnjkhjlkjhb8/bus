package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/functions/notify"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"google.golang.org/protobuf/proto"
)

type fakeBusEtaStore struct {
	stops             []busStationmap
	staticStopCalls   int
	nextDepartureKeys []routeDirKey
	nextDepartureTOD  string
	nextDepartureBit  int
	travelAverageUIDs []string
	travelAverageHour int
	travelAverageDay  int
	historyRows       [][]interface{}
	predictions       []predictionRecord
	predictionCalls   int
	nextDepartureMap  map[routeDirKey]time.Time
}

func (s *fakeBusEtaStore) staticStops(context.Context, string) ([]busStationmap, error) {
	s.staticStopCalls++
	return s.stops, nil
}

func (s *fakeBusEtaStore) nextDepartures(_ context.Context, keys []routeDirKey, tod string, dayBit int) map[routeDirKey]time.Time {
	s.nextDepartureKeys = append([]routeDirKey(nil), keys...)
	s.nextDepartureTOD = tod
	s.nextDepartureBit = dayBit
	return s.nextDepartureMap
}

func (s *fakeBusEtaStore) travelAverages(_ context.Context, uids []string, hour, day int) map[travelAvgKey]int {
	s.travelAverageUIDs = append([]string(nil), uids...)
	s.travelAverageHour = hour
	s.travelAverageDay = day
	return map[travelAvgKey]int{}
}

func (s *fakeBusEtaStore) saveHistory(_ context.Context, rows [][]interface{}) {
	s.historyRows = rows
}

func (s *fakeBusEtaStore) recordPredictions(_ context.Context, rows []predictionRecord) {
	s.predictionCalls++
	s.predictions = rows
}

type busArrivalCall struct {
	routeKey  string
	stopKey   string
	direction string
	seconds   int32
	plate     string
}

type captureBusArrivalNotifier struct {
	calls   []busArrivalCall
	batches int
}

func (n *captureBusArrivalNotifier) Arrivals(_ context.Context, events []notify.ArrivalEvent) error {
	n.batches++
	for _, event := range events {
		n.calls = append(n.calls, busArrivalCall{
			routeKey: event.RouteKey, stopKey: event.StopKey, direction: event.Direction,
			seconds: event.ETASeconds, plate: event.ArrivingPlate,
		})
	}
	return nil
}

func TestBusArrivalBatchFlushesOncePerTick(t *testing.T) {
	target := &captureBusArrivalNotifier{}
	batch := busArrivalBatch{target: target}
	first := notify.ArrivalEvent{RouteType: "bus", RouteKey: "R1", StopKey: "S1", Direction: "0", ETASeconds: 60}
	second := notify.ArrivalEvent{RouteType: "bus", RouteKey: "R2", StopKey: "S2", Direction: "1", ETASeconds: 120}
	if err := batch.Arrivals(context.Background(), []notify.ArrivalEvent{first}); err != nil {
		t.Fatal(err)
	}
	if err := batch.Arrivals(context.Background(), []notify.ArrivalEvent{second}); err != nil {
		t.Fatal(err)
	}
	if target.batches != 0 {
		t.Fatalf("target called before tick flush: batches = %d", target.batches)
	}
	if err := batch.flush(context.Background()); err != nil {
		t.Fatal(err)
	}
	if target.batches != 1 || len(target.calls) != 2 {
		t.Fatalf("target batches/calls = %d/%+v, want one batch with two arrivals", target.batches, target.calls)
	}
}

func TestRunBusEtaCitiesFlushesOnlySuccessfulCityArrivalsOnce(t *testing.T) {
	now := time.Date(2026, time.July, 10, 9, 0, 0, 0, taipei)
	for _, city := range []string{"Taipei", "NewTaipei"} {
		prefix := citymap[city]
		busStaticMapCache.Delete(prefix)
		storeBusStaticMapIn(&busStaticMapCache, prefix, []busStationmap{{
			StationUID: "STATION1", StationName: "站牌一", GroupUID: "GROUP1", GroupName: "群組一",
			SubRouteUID: prefix + "1", SubRouteName: "一路", Direction: 0, StopUID: "STOP1", StopSequence: 1,
		}}, "", now)
		t.Cleanup(func() { busStaticMapCache.Delete(prefix) })
	}

	cityErr := errors.New("new taipei ETA unavailable")
	fetch := func(_ context.Context, _ string, name string) (*shared.TDXFetch, error) {
		if name == "bus_EstimatedTimeOfArrivalNewTaipei" {
			return nil, cityErr
		}
		body := []byte(`[]`)
		if name == "bus_EstimatedTimeOfArrivalTaipei" {
			body = []byte(`[{"PlateNumb":"ETA-A","StopUID":"STOP1","SubRouteUID":"TPE1","Direction":0,"EstimateTime":60,"StopStatus":0}]`)
		}
		return &shared.TDXFetch{
			Decoder: json.NewDecoder(bytes.NewReader(body)), Modified: true,
			Ack: func() error { return nil }, Close: func() error { return nil },
			Invalidate: func() error { return nil },
		}, nil
	}
	target := &captureBusArrivalNotifier{}
	job := busLiveJob{
		fetch: fetch, sink: &captureLiveSink{}, store: &fakeBusEtaStore{},
		now: func() time.Time { return now },
	}

	err := runBusEtaCities(context.Background(), []string{"Taipei", "NewTaipei"}, &job, target)
	if !errors.Is(err, cityErr) {
		t.Fatalf("runBusEtaCities() error = %v, want %v", err, cityErr)
	}
	if target.batches != 1 || len(target.calls) != 1 {
		t.Fatalf("notification batches/calls = %d/%+v, want one successful-city batch", target.batches, target.calls)
	}
	want := busArrivalCall{routeKey: "TPE1", stopKey: "STOP1", direction: "0", seconds: 60, plate: "ETA-A"}
	if target.calls[0] != want {
		t.Fatalf("notification call = %+v, want %+v", target.calls[0], want)
	}
}

func TestBusLiveJobModifiedFeedPublishesCanonicalArrivals(t *testing.T) {
	prefix := citymap["InterCity"]
	busStaticMapCache.Delete(prefix)
	t.Cleanup(func() { busStaticMapCache.Delete(prefix) })

	now := time.Date(2026, time.July, 10, 9, 0, 0, 0, taipei)
	src := &fakeLiveSource{fixtures: map[string][]byte{
		"bus_EstimatedTimeOfArrivalInterCity": []byte(`[{"PlateNumb":"KKA-1234","StopUID":"STOP1","SubRouteUID":"THB902301","Direction":9,"EstimateTime":120,"StopStatus":0,"SrcUpdateTime":"2026-07-10T09:00:00+08:00"}]`),
		"bus_RealTimeByFrequencyInterCity":    []byte(`[{"PlateNumb":"GPS-9999","StopUID":"STOP1","SubRouteUID":"THB902301","Direction":9,"BusPosition":{"PositionLon":121.5,"PositionLat":25.05},"Azimuth":90,"Speed":30}]`),
	}}
	sink := &captureLiveSink{}
	store := &fakeBusEtaStore{stops: []busStationmap{{
		StationUID: "STATION1", StationName: "站牌一", GroupUID: "GROUP1", GroupName: "群組一",
		SubRouteUID: "THB902301", SubRouteName: "9023", Direction: 9, StopUID: "STOP1",
		StopSequence: 1, Lat: 25.05, Lon: 121.5,
	}}}
	notifier := &captureBusArrivalNotifier{}
	job := busLiveJob{
		fetch:    bindFetch(src, sink, specByKey(t, "bus")),
		sink:     sink,
		store:    store,
		notifier: notifier,
		now:      func() time.Time { return now },
	}

	job.runCity(context.Background(), "InterCity")

	stationKey := shared.BusStationEtaKey("InterCity", "GROUP1")
	stationWrite := sink.setFor(stationKey)
	if stationWrite == nil || stationWrite.ttl != busLiveTTL {
		t.Fatalf("station SET = %+v, want key %s with ttl %v", stationWrite, stationKey, busLiveTTL)
	}
	var station models.Bus_StationArrival
	if err := proto.Unmarshal(stationWrite.value, &station); err != nil {
		t.Fatalf("unmarshal station arrival: %v", err)
	}
	if station.StationName != "群組一" || len(station.Routes) != 1 {
		t.Fatalf("station arrival = %+v", &station)
	}
	stop := station.Routes[0]
	if stop.SubRouteUid != "THB9023" || stop.Direction != 0 || stop.Estimate != 120 || stop.ArrivalUnix != now.Add(120*time.Second).Unix() {
		t.Fatalf("canonical station estimate = %+v", stop)
	}
	if len(stop.Buses) != 1 || stop.Buses[0].PlateNumb != "GPS-9999" {
		t.Fatalf("station buses = %+v", stop.Buses)
	}

	routeKey := shared.BusRouteEtaKey("THB9023")
	routeWrite := sink.setFor(routeKey)
	if routeWrite == nil || routeWrite.ttl != busLiveTTL {
		t.Fatalf("route SET = %+v, want key %s with ttl %v", routeWrite, routeKey, busLiveTTL)
	}
	var route models.Bus_RouteArrival
	if err := proto.Unmarshal(routeWrite.value, &route); err != nil {
		t.Fatalf("unmarshal route arrival: %v", err)
	}
	if route.SubRouteUid != "THB9023" || len(route.Stops) != 1 || route.Stops[0].Direction != 0 {
		t.Fatalf("canonical route arrival = %+v", &route)
	}
	if len(sink.publishs) != 2 {
		t.Fatalf("publish count = %d, want 2", len(sink.publishs))
	}
	if len(store.historyRows) != 1 || store.historyRows[0][0] != "THB9023" || store.historyRows[0][2] != int16(0) {
		t.Fatalf("canonical history rows = %+v", store.historyRows)
	}
	if notifier.batches != 1 || len(notifier.calls) != 1 || notifier.calls[0] != (busArrivalCall{routeKey: "THB9023", stopKey: "STOP1", direction: "0", seconds: 120, plate: "KKA-1234"}) {
		t.Fatalf("canonical notification batches/calls = %d/%+v", notifier.batches, notifier.calls)
	}
}

func TestBusLiveJobBatchesPredictionInputs(t *testing.T) {
	prefix := citymap["Taipei"]
	busStaticMapCache.Delete(prefix)
	t.Cleanup(func() { busStaticMapCache.Delete(prefix) })

	now := time.Date(2026, time.July, 6, 9, 15, 0, 0, taipei)
	src := &fakeLiveSource{fixtures: map[string][]byte{
		"bus_EstimatedTimeOfArrivalTaipei": []byte(`[{"PlateNumb":"BUS-1","StopUID":"STOP1","SubRouteUID":"TPE1","Direction":1,"EstimatedTime":120,"StopStatus":0},{"StopUID":"STOP2","SubRouteUID":"TPE1","Direction":1,"StopStatus":1}]`),
		"bus_RealTimeByFrequencyTaipei":    []byte(`[]`),
	}}
	sink := &captureLiveSink{}
	wantKey := routeDirKey{subRouteUID: "TPE1", direction: 1}
	store := &fakeBusEtaStore{
		stops: []busStationmap{
			{StationUID: "STATION1", StationName: "站牌一", SubRouteUID: "TPE1", SubRouteName: "一路", Direction: 1, StopUID: "STOP1", StopSequence: 1},
			{StationUID: "STATION2", StationName: "站牌二", SubRouteUID: "TPE1", SubRouteName: "一路", Direction: 1, StopUID: "STOP2", StopSequence: 2},
		},
		nextDepartureMap: map[routeDirKey]time.Time{wantKey: now.Add(5 * time.Minute)},
	}
	job := busLiveJob{
		fetch: bindFetch(src, sink, specByKey(t, "bus")), sink: sink, store: store,
		notifier: &captureBusArrivalNotifier{}, now: func() time.Time { return now },
	}

	job.runCity(context.Background(), "Taipei")

	if len(store.nextDepartureKeys) != 1 || store.nextDepartureKeys[0] != wantKey {
		t.Fatalf("next-departure keys = %+v, want [%+v]", store.nextDepartureKeys, wantKey)
	}
	if store.nextDepartureTOD != "09:15:00" || store.nextDepartureBit != 1 {
		t.Fatalf("next-departure time/day = %q/%d, want 09:15:00/1", store.nextDepartureTOD, store.nextDepartureBit)
	}
	if len(store.travelAverageUIDs) != 1 || store.travelAverageUIDs[0] != "TPE1" || store.travelAverageHour != 9 || store.travelAverageDay != int(time.Monday) {
		t.Fatalf("travel-average inputs = %+v hour=%d day=%d", store.travelAverageUIDs, store.travelAverageHour, store.travelAverageDay)
	}
	if sink.setFor(shared.BusRouteEtaKey("TPE1")) == nil {
		t.Fatal("modified feed did not publish the route snapshot")
	}
	if store.predictionCalls != 1 || len(store.predictions) != 1 {
		t.Fatalf("prediction persistence calls/rows = %d/%+v, want one call with one row", store.predictionCalls, store.predictions)
	}
	prediction := store.predictions[0]
	if prediction.subRouteUID != "TPE1" || prediction.direction != 1 || prediction.stopUID != "STOP2" || prediction.source != sourcePropagation {
		t.Fatalf("prediction persistence row = %+v", prediction)
	}
}

func TestBusLiveJobReusesStaticStopCache(t *testing.T) {
	prefix := citymap["Taipei"]
	busStaticMapCache.Delete(prefix)
	t.Cleanup(func() { busStaticMapCache.Delete(prefix) })

	src := &fakeLiveSource{fixtures: map[string][]byte{
		"bus_EstimatedTimeOfArrivalTaipei": []byte(`[]`),
		"bus_RealTimeByFrequencyTaipei":    []byte(`[]`),
	}}
	sink := &captureLiveSink{}
	store := &fakeBusEtaStore{stops: []busStationmap{{
		StationUID: "STATION1", StationName: "站牌一", SubRouteUID: "TPE1",
		SubRouteName: "一路", StopUID: "STOP1", StopSequence: 1,
	}}}
	job := busLiveJob{
		fetch: bindFetch(src, sink, specByKey(t, "bus")), sink: sink, store: store,
		notifier: &captureBusArrivalNotifier{}, now: func() time.Time { return time.Date(2026, time.July, 6, 9, 15, 0, 0, taipei) },
	}

	job.runCity(context.Background(), "Taipei")
	job.runCity(context.Background(), "Taipei")

	if store.staticStopCalls != 1 {
		t.Fatalf("static stop loads = %d, want 1", store.staticStopCalls)
	}
}
