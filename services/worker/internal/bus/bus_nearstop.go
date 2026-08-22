package bus

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/pipeline"
	"go.uber.org/zap"
)

// TDX's A2 feed (Bus/RealTimeNearStop) reports a vehicle entering or leaving a
// named stop, which is the one thing A1 (RealTimeByFrequency) cannot say: A1
// carries a coordinate, so every stop-to-vehicle attribution off it is a
// proximity guess. A2 names the stop outright.
//
// TDX serves A2 for every city (all 23 partitions answered with rows on
// 2026-08-09), so this list is a choice, not a limit. Only 公路總局 and the
// counties whose dynamic systems it manages are fetched: TDX publishes their A2
// about 5 seconds behind the source against ~30 seconds for Taoyuan, Taichung
// and Kaohsiung, Taipei and New Taipei already get stop-level attribution from
// Data.taipei, and each city added costs one more TDX request on every tick of a
// 30-second cron.
var _busNearStopCities = map[string]struct{}{
	"InterCity":      {},
	"Keelung":        {},
	"Hsinchu":        {},
	"HsinchuCounty":  {},
	"MiaoliCounty":   {},
	"NantouCounty":   {},
	"ChanghuaCounty": {},
	"YunlinCounty":   {},
	"Chiayi":         {},
	"ChiayiCounty":   {},
	"PingtungCounty": {},
	"YilanCounty":    {},
	"HualienCounty":  {},
	"TaitungCounty":  {},
	"PenghuCounty":   {},
}

// rawBusNearStop decodes a TDX Bus/RealTimeNearStop element: one vehicle's
// arrival at, or departure from, one stop of one subroute.
type rawBusNearStop struct {
	PlateNumb    string `json:"PlateNumb"`
	SubRouteUID  string `json:"SubRouteUID"`
	Direction    uint8  `json:"Direction"`
	StopUID      string `json:"StopUID"`
	StopSequence uint8  `json:"StopSequence"`
	A2EventType  uint8  `json:"A2EventType"`
	DutyStatus   uint8  `json:"DutyStatus"`
	BusStatus    uint8  `json:"BusStatus"`
	GPSTime      string `json:"GPSTime"`
	// TripStartTime is the run's first-stop departure and TripStartTimeType says
	// how it was arrived at: 0 actual, 1 estimated from segment travel times,
	// 2 not derivable.
	TripStartTime     string `json:"TripStartTime"`
	TripStartTimeType uint8  `json:"TripStartTimeType"`
}

// A2EventType, established by sampling the InterCity feed twice a minute apart
// (2026-08-09): of the vehicles whose latest record moved while staying at one
// stop, every transition ran 1 -> 0 and none ran 0 -> 1. A bus arrives before it
// leaves, so 1 is the arrival and 0 the departure — matched by the cross-stop
// transitions, where 0 at stop N is followed by 1 at stop N+1.
const (
	_busA2EventDepart uint8 = 0
	_busA2EventArrive uint8 = 1
)

// How recent an A2 record must be to place a vehicle at a stop. The record is
// the last thing that happened to that vehicle, and TDX keeps it for two hours,
// so without a window every stop a bus called at this morning would still claim
// it. One ETA cron period plus the feed's own publish lag.
const _busNearStopMaxAge = 90 * time.Second

// nearStopRecords fetches one city's A2 feed. An unmodified feed (304) yields no
// records: the previous tick's events have already been archived, and a stale
// event may not place a vehicle anywhere, so the tick falls back to A1 proximity
// rather than repeating itself.
func nearStopRecords(ctx context.Context, fetch pipeline.BoundFetch, city string) ([]rawBusNearStop, error) {
	url := fmt.Sprintf("/v2/Bus/RealTimeNearStop/City/%s", city)
	if city == "InterCity" {
		url = "/v2/Bus/RealTimeNearStop/InterCity"
	}
	result, err := fetch(ctx, url, "bus_RealTimeNearStop"+city)
	if err != nil {
		return nil, _oops.With("city", city).Wrapf(err, "fetch bus near-stop events")
	}
	if !result.Modified {
		return nil, pipeline.InvalidateTDXFetch(result)
	}
	rows := make([]rawBusNearStop, 0)
	if err := pipeline.CommitTDXFetch(result, func(dec *json.Decoder) error {
		return pipeline.DecodeLiveItems(dec, func(r rawBusNearStop) error {
			rows = append(rows, r)
			return nil
		})
	}); err != nil {
		return nil, _oops.With("city", city).Wrapf(err, "decode bus near-stop events")
	}
	return rows, nil
}

// buildNearStopIndex places each vehicle at the stop it most recently arrived
// at, on the same canonical subroute/direction axis as the rest of the ETA job.
// A departure event places it nowhere: the bus has left that stop, and the next
// one has nothing but nearest-GPS until the arrival event lands. Out-of-service
// vehicles and events older than _busNearStopMaxAge are dropped for the same
// reasons they are on the A1 path.
//
// Last event wins on the rare double: two vehicles of one subroute direction at
// one stop are both there, and neither is the better answer.
func buildNearStopIndex(city string, rows []rawBusNearStop, now time.Time) map[busAtStopKey]stopPresence {
	index := make(map[busAtStopKey]stopPresence, len(rows))
	for _, r := range rows {
		plate := normalizeArrivalPlate(r.PlateNumb)
		if r.StopUID == "" || plate == "" {
			continue
		}
		if r.A2EventType != _busA2EventArrive {
			continue
		}
		if r.DutyStatus == _busDutyStatusEnded || r.BusStatus == _busStatusNotInService {
			continue
		}
		at := parseGPSTimeUnix(r.GPSTime)
		if at == 0 || now.Sub(time.Unix(at, 0)) > _busNearStopMaxAge {
			continue
		}
		uid, direction := shared.CanonicalSubroute(city, r.SubRouteUID, r.Direction)
		index[busAtStopKey{uid, direction, r.StopUID}] = stopPresence{plate: plate}
	}
	return index
}

// nearStops is the ETA job's whole view of the A2 feed: for a city TDX serves
// it with, the stop each vehicle was last seen at, and for every other city and
// every failure an empty index, leaving that city on nearestBus. The same
// records are handed to the archive on the way past — they are the only
// observed arrival and departure instants this system sees.
//
// A failure is logged rather than returned: the A2 feed is an improvement on a
// proximity guess, so losing it degrades attribution instead of costing the city
// its ETA tick.
func (j *busLiveJob) nearStops(ctx context.Context, city string, now time.Time) map[busAtStopKey]stopPresence {
	if _, ok := _busNearStopCities[city]; !ok {
		return nil
	}
	rows, err := nearStopRecords(ctx, j.fetch, city)
	if err != nil {
		zap.S().Warnw("fetch failed; falling back to nearest-GPS attribution",
			"component", "bus_nearstop",
			"action", "near_stop",
			"city", city,
			"err", err,
		)
		return nil
	}
	j.store.saveStopEvents(ctx, busStopEventRows(city, rows, now))
	return buildNearStopIndex(city, rows, now)
}

// busStopEventRows turns one city's A2 records into archive rows: the observed
// arrival and departure instants that segment travel time is currently
// estimated from ETA countdowns instead. Records with no plate, stop or clock
// carry no observation and are skipped.
func busStopEventRows(city string, rows []rawBusNearStop, now time.Time) [][]any {
	out := make([][]any, 0, len(rows))
	for _, r := range rows {
		plate := normalizeArrivalPlate(r.PlateNumb)
		at := parseGPSTimeUnix(r.GPSTime)
		if plate == "" || r.StopUID == "" || at == 0 {
			continue
		}
		uid, direction := shared.CanonicalSubroute(city, r.SubRouteUID, r.Direction)
		var tripStart any
		if t, ok := parseSrcUpdateTime(r.TripStartTime); ok {
			tripStart = t
		}
		out = append(out, []any{
			plate, city, uid, int16(direction), r.StopUID, int16(r.StopSequence),
			int16(r.A2EventType), time.Unix(at, 0), tripStart, int16(r.TripStartTimeType), now,
		})
	}
	return out
}
