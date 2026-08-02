package main

import (
	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"

	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"google.golang.org/protobuf/proto"
)

// cities is the set of TDX city codes iterated by every bus/bike ingestion loop.
// "InterCity" is the highway coach operator, not a municipality. Order is not
// significant.
var cities = []string{
	"Taipei", "NewTaipei", "Taoyuan", "Taichung", "Tainan", "Kaohsiung",
	"InterCity", "Hsinchu", "HsinchuCounty", "MiaoliCounty", "ChanghuaCounty",
	"NantouCounty", "YunlinCounty", "ChiayiCounty", "Chiayi", "PingtungCounty",
	"YilanCounty", "HualienCounty", "TaitungCounty", "PenghuCounty", "KinmenCounty", "LienchiangCounty", "Keelung",
}

// citymap maps a TDX city code to its short prefix used in UID construction and
// as the authority_code for operators. Every entry in cities must have a key
// here: readBusCitySnapshot rejects an unmapped city before the writer can turn
// its partition-replacement prefix into the destructive pattern "%".
var citymap = map[string]string{
	"Taipei": "TPE", "NewTaipei": "NWT", "Taoyuan": "TAO", "Taichung": "TXG",
	"Tainan": "TNN", "Kaohsiung": "KHH", "InterCity": "THB", "Keelung": "KEE",
	"Hsinchu": "HSZ", "HsinchuCounty": "HSQ", "MiaoliCounty": "MIA", "ChanghuaCounty": "CHA",
	"NantouCounty": "NAN", "Chiayi": "CYI", "ChiayiCounty": "CYQ", "YunlinCounty": "YUN",
	"PingtungCounty": "PIF", "YilanCounty": "ILA", "HualienCounty": "HUA", "TaitungCounty": "TTT",
	"PenghuCounty": "PEN", "KinmenCounty": "KIN", "LienchiangCounty": "LIE",
}

// citymap2 is the inverse of citymap, resolving a short prefix back to a TDX
// city code. Used when rail data carries LocationCityCode prefixes.
var citymap2 = map[string]string{
	"TPE": "Taipei", "NWT": "NewTaipei", "TAO": "Taoyuan", "TXG": "Taichung",
	"TNN": "Tainan", "KHH": "Kaohsiung", "THB": "InterCity", "KEE": "Keelung",
	"HSZ": "Hsinchu", "HSQ": "HsinchuCounty", "MIA": "MiaoliCounty", "CHA": "ChanghuaCounty",
	"NAN": "NantouCounty", "CYI": "Chiayi", "CYQ": "ChiayiCounty", "YUN": "YunlinCounty",
	"PIF": "PingtungCounty", "ILA": "YilanCounty", "HUA": "HualienCounty", "TTT": "TaitungCounty",
	"PEN": "PenghuCounty", "KIN": "KinmenCounty", "LIE": "LienchiangCounty",
}

// busSubroutesUpsertSQL upserts one subroute per (sub_route_uid, direction) into
// bus_subroutes from the temp_bus staging table, building the stops array from
// the staged rawstop jsonb. DISTINCT ON dedupes staged duplicates.
const busSubroutesUpsertSQL = `
			INSERT INTO bus_subroutes(
				sub_route_uid,
				route_uid,
				direction,
				route_name,
				sub_route_name,
				city,
				depart,
				destin,
				geometry,
				stops,
				schedule,
				operators
			)
			SELECT DISTINCT ON (uid, d) uid, rid, d, name1, name2,city,depart,destin,geom,
				   ARRAY(
					   SELECT ROW(
								  s ->> 'StationID',
								  s ->> 'StopName',
								  (s ->> 'StopSequence')::int,
								  (s ->> 'PositionLon')::float,
								  (s ->> 'PositionLat')::float
							  )::stop
					   FROM jsonb_array_elements(rawstop) AS s
				   ),schedule,operators
			FROM temp_bus
			ORDER BY uid, d
			ON CONFLICT (sub_route_uid, direction)
			DO UPDATE SET
				route_uid = EXCLUDED.route_uid,
				route_name = EXCLUDED.route_name,
				sub_route_name = EXCLUDED.sub_route_name,
				city = EXCLUDED.city,
				geometry = EXCLUDED.geometry,
				stops = EXCLUDED.stops,
				depart = EXCLUDED.depart,
				destin = EXCLUDED.destin,
				schedule = EXCLUDED.schedule,
				operators = EXCLUDED.operators,
				updated_at = NOW();
			`

// busScheduleInsertSQL inserts the write-ready timetable and frequency rows
// from temp_bus_schedule after the atomic writer has deleted the city's
// partition in the same transaction. No DISTINCT ON and no ON CONFLICT: the
// natural key (sub_route_uid, direction, type, service_day, tripid,
// "stop_uid/MinHeadwayMins") is not unique in real data — a circular route
// visits the same stop twice in one trip — so every raw row must survive rather
// than be collapsed. The dual-purpose column names (e.g.
// "stop_uid/MinHeadwayMins") hold either a fixed timetable stop or a
// frequency-based headway depending on the type flag.
const busScheduleInsertSQL = `INSERT INTO bus_schedule (sub_route_uid, direction, type, tripid, islowfloor, stopsequence, "stop_uid/MinHeadwayMins", "stop_name/MaxHeadwayMins", "arrival_time/StartTime", "departure_time/EndTime", service_day, updated_at)
				SELECT uid, dir, type, id, floor, seq, stopuid, stopname, arrival::time, departure::time, sdays, NOW()
				FROM temp_bus_schedule`

// rawBusRoute decodes a TDX Bus/Route element: a route and its per-direction
// subroutes, operators, and first/last service times.
type rawBusRoute struct {
	RouteUID  string `json:"RouteUID"`
	RouteName struct {
		Zhtw string `json:"Zh_tw"`
	} `json:"RouteName"`
	DepartureStopNameZh   string `json:"DepartureStopNameZh"`
	DestinationStopNameZh string `json:"DestinationStopNameZh"`
	Operators             []struct {
		OperatorID string `json:"OperatorID"`
	} `json:"Operators"`
	SubRoutes []struct {
		SubRouteUID  string `json:"SubRouteUID"`
		SubRouteID   string `json:"SubRouteID"`
		SubRouteName struct {
			Zhtw string `json:"Zh_tw"`
		} `json:"SubRouteName"`
		Direction             uint8  `json:"Direction"`
		DepartureStopNameZh   string `json:"DepartureStopNameZh,omitempty"`
		DestinationStopNameZh string `json:"DestinationStopNameZh,omitempty"`
		FirstBusTime          string `json:"FirstBusTime"`
		LastBusTime           string `json:"LastBusTime"`
		HolidayFirstBusTime   string `json:"HolidayFirstBusTime"`
		HolidayLastBusTime    string `json:"HolidayLastBusTime"`
	} `json:"SubRoutes"`
}

// rawBusFare decodes a TDX Bus/RouteFare element. Fare detail arrays are kept as
// raw JSON and stored verbatim. IsForAllSubRoutes marks a route-wide fare that
// applies when no subroute-specific fare exists.
type rawBusFare struct {
	RouteID           string          `json:"RouteID"`
	SubRouteID        string          `json:"SubRouteID"`
	FarePricingType   int32           `json:"FarePricingType"`
	IsFreeBus         uint8           `json:"IsFreeBus"`
	IsForAllSubRoutes uint8           `json:"IsForAllSubRoutes"`
	SectionFares      json.RawMessage `json:"SectionFares"`
	StageFares        json.RawMessage `json:"StageFares"`
	ODFares           json.RawMessage `json:"ODFares"`
}

// rawStopofroute decodes a TDX Bus/StopOfRoute element: the ordered stops of one
// subroute direction.
type rawStopofroute struct {
	RouteUID    string `json:"RouteUID"`
	SubRouteUID string `json:"SubRouteUID"`
	Direction   uint8  `json:"Direction"`
	Stops       []struct {
		StopUID  string `json:"StopUID"`
		StopName struct {
			Zhtw string `json:"Zh_tw"`
		} `json:"StopName"`
		StopSequence uint8 `json:"StopSequence"`
		StopPosition struct {
			PositionLon float64 `json:"PositionLon"`
			PositionLat float64 `json:"PositionLat"`
		} `json:"StopPosition"`
		StationID        string `json:"StationID"`
		LocationCityCode string `json:"LocationCityCode"`
	} `json:"Stops"`
}

// rawBusDailytimetable decodes a TDX Bus/DailyTimeTable element: per-trip
// stop-by-stop scheduled times for one service day, cached for realtime use.
type rawBusDailytimetable struct {
	SubRouteUID string `json:"SubRouteUID"`
	Direction   *uint8 `json:"Direction"`
	Timetables  []struct {
		TripID     string `json:"TripID"`
		IsLowFloor bool   `json:"IsLowFloor"`
		StopTimes  []struct {
			StopSequence  int64  `json:"StopSequence"`
			StopUID       string `json:"StopUID"`
			ArrivalTime   string `json:"ArrivalTime"`
			DepartureTime string `json:"DepartureTime"`
		} `json:"StopTimes"`
	} `json:"Timetables"`
}

// rawBusSchedule decodes a TDX Bus/Schedule element: recurring service. A
// subroute uses either fixed Timetables (per-stop times) or Frequencys
// (headway windows), keyed by a weekly ServiceDay pattern.
type rawBusSchedule struct {
	SubRouteUID string `json:"SubRouteUID"`
	RouteUID    string `json:"RouteUID"`
	Direction   uint8  `json:"Direction"`
	Timetables  []struct {
		TripID     string `json:"TripID"`
		IsLowFloor bool   `json:"IsLowFloor"`
		ServiceDay struct {
			Sunday    uint8 `json:"Sunday"`
			Monday    uint8 `json:"Monday"`
			Tuesday   uint8 `json:"Tuesday"`
			Wednesday uint8 `json:"Wednesday"`
			Thursday  uint8 `json:"Thursday"`
			Friday    uint8 `json:"Friday"`
			Saturday  uint8 `json:"Saturday"`
		} `json:"ServiceDay"`
		StopTimes []struct {
			StopSequence int    `json:"StopSequence"`
			StopUID      string `json:"StopUID"`
			StopName     struct {
				Zhtw string `json:"Zh_tw"`
			} `json:"StopName"`
			ArrivalTime   string `json:"ArrivalTime"`
			DepartureTime string `json:"DepartureTime"`
		} `json:"StopTimes"`
	} `json:"Timetables"`
	Frequencys []struct {
		StartTime      string `json:"StartTime"`
		EndTime        string `json:"EndTime"`
		MinHeadwayMins uint8  `json:"MinHeadwayMins"`
		MaxHeadwayMins uint8  `json:"MaxHeadwayMins"`
		ServiceDay     struct {
			Sunday    uint8 `json:"Sunday"`
			Monday    uint8 `json:"Monday"`
			Tuesday   uint8 `json:"Tuesday"`
			Wednesday uint8 `json:"Wednesday"`
			Thursday  uint8 `json:"Thursday"`
			Friday    uint8 `json:"Friday"`
			Saturday  uint8 `json:"Saturday"`
		} `json:"ServiceDay"`
	} `json:"Frequencys"`
}

// rawBusEsimated decodes a TDX Bus/EstimatedTimeOfArrival element: the live ETA
// for one plate at one stop. EstimatedTime is seconds; StopStatus 0 means a bus
// is en route; an empty NextBusTime with StopStatus 1 is the gap that ETA
// prediction fills. The type name's misspelling is retained to match existing code.
type rawBusEsimated struct {
	PlateNumb string `json:"PlateNumb"`
	StopUID   string `json:"StopUID"`
	// Taipei and NewTaipei publish route-level arrivals: their entries carry only
	// RouteUID, with SubRouteUID absent. buildBusEtaMap fans those out across the
	// route's subroutes, so both fields must be decoded.
	SubRouteUID string `json:"SubRouteUID"`
	RouteUID    string `json:"RouteUID"`
	Direction   uint8  `json:"Direction"`
	// TDX spells this "EstimateTime", not "EstimatedTime". The struct field keeps
	// the grammatical name; only the tag has to match the wire.
	EstimatedTime int32  `json:"EstimateTime"`
	NextBusTime   string `json:"NextBusTime"`
	StopStatus    uint8  `json:"StopStatus"`
	SrcUpdateTime string `json:"SrcUpdateTime"`
}

// rawBusPosition decodes a TDX Bus/RealTimeByFrequency element: a bus's live GPS
// position and status, used to attach the nearest vehicle to a stop's ETA.
type rawBusPosition struct {
	PlateNumb   string `json:"PlateNumb"`
	SubRouteUID string `json:"SubRouteUID"`
	StopUID     string `json:"StopUID"`
	Direction   uint8  `json:"Direction"`
	BusPosition struct {
		PositionLon float64 `json:"PositionLon"`
		PositionLat float64 `json:"PositionLat"`
	} `json:"BusPosition"`
	// Azimuth is float64 for the same reason Speed is: TDX sends a fractional
	// bearing on some vehicles — 10% of Tainan's, e.g. 40.993683 — and decoding
	// that into an int fails the element, which aborts the whole city's tick
	// before any ETA is matched or any history row is written. Tainan recorded
	// nothing between 2026-07-13 and 07-31 for exactly this reason, surviving only
	// in the small hours when no vehicle was reporting a fractional bearing.
	Azimuth    float64 `json:"Azimuth"`
	Speed      float64 `json:"Speed"`
	DutyStatus uint8   `json:"DutyStatus"`
	BusStatus  uint8   `json:"BusStatus"`
	GPSTime    string  `json:"GPSTime"`
}

// busStationmap is one stop of one subroute joined to its station group and
// coordinates, as loaded by busstaticmp and consumed by the bus ETA builder.
type busStationmap struct {
	StationUID   string
	StationName  string
	GroupUID     string
	GroupName    string
	SubRouteUID  string
	RouteUID     string
	SubRouteName string
	Destination  string
	Direction    uint8
	StopUID      string
	StopSequence uint8
	Lat          float64
	Lon          float64
}

// rawBusShape decodes a TDX Bus/Shape element: the WKT geometry of a route or
// subroute. When SubRouteUID is empty the geometry applies to every subroute of
// the route.
type rawBusShape struct {
	SubRouteUID string `json:"SubRouteUID,omitempty"`
	RouteUID    string `json:"RouteUID"`
	Direction   uint8  `json:"Direction"`
	Geometry    string `json:"Geometry"`
	UpdateTime  string `json:"UpdateTime"`
}

// rawBusOperator decodes a TDX Bus/Operator element for the atomic city
// snapshot's target upsert and route enrichment.
type rawBusOperator struct {
	OperatorID   string `json:"OperatorID"`
	OperatorName struct {
		Zhtw string `json:"Zh_tw"`
	} `json:"OperatorName"`
	OperatorPhone string `json:"OperatorPhone"`
	OperatorURL   string `json:"OperatorUrl"`
	AuthorityCode string `json:"AuthorityCode"`
}

// busOperatorJSON is the compact operator shape embedded as jsonb in a
// subroute's operators column (lowercase keys, distinct from the TDX field names).
type busOperatorJSON struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Phone string `json:"phone"`
	URL   string `json:"url"`
}

var operatorPhoneRun = regexp.MustCompile(`\d[\d\-() ]*\d|\d`)

func sanitizeOperatorPhone(s string) string {
	if !strings.ContainsRune(s, '�') {
		return s
	}
	return strings.Join(operatorPhoneRun.FindAllString(s, -1), " / ")
}

// busDailyTimetableSkip lists cities whose daily-timetable feed TDX does not
// serve; both the landing partitions and the loader path
// (loadBusDailyTimetable partitions) skip them so landed and loaded partitions
// agree.
func busDailyTimetableSkip(city string) bool {
	return city == "Taipei" || city == "NewTaipei" || city == "Tainan" ||
		city == "KinmenCounty" || city == "LienchiangCounty"
}

// busDailyOriginFilter indexes each subroute direction's origin stop from the
// city's raw StopOfRoute landing so daily-timetable trips can be checked
// against the direction they claim.
type busDailyOriginFilter struct {
	originUID  map[string]map[string]struct{} // uid\x00dir -> origin StopUIDs across operator variants
	originName map[string]map[string]struct{} // uid\x00dir -> origin stop names
	stopName   map[string]string              // StopUID -> name, over every route's stop list
}

func busDailyOriginKey(uid string, dir uint8) string {
	return fmt.Sprintf("%s\x00%d", uid, dir)
}

// newBusDailyOriginFilter reads the city's raw StopOfRoute landing. A read or
// decode failure returns nil (filtering disabled): an unfiltered timetable is
// the pre-filter status quo, not worth failing the city's load over.
func newBusDailyOriginFilter(ctx context.Context, src loadSource, city string) *busDailyOriginFilter {
	if src == nil {
		return nil
	}
	body, _, err := src.datasetJSON(ctx, "bus_stopofroute", "city", city)
	if err != nil {
		log.Warnf("[LOAD] action=bus_dailytimetable event=origin_filter_unavailable city=%s error=%v", city, err)
		return nil
	}
	var variants []rawStopofroute
	if err := json.Unmarshal(body, &variants); err != nil {
		log.Warnf("[LOAD] action=bus_dailytimetable event=origin_filter_unavailable city=%s error=%v", city, err)
		return nil
	}
	f := &busDailyOriginFilter{
		originUID:  make(map[string]map[string]struct{}, len(variants)),
		originName: make(map[string]map[string]struct{}, len(variants)),
		stopName:   make(map[string]string, len(variants)*32),
	}
	for _, v := range variants {
		if len(v.Stops) == 0 {
			continue
		}
		uid, dir := shared.CanonicalSubroute(city, v.SubRouteUID, v.Direction)
		first := v.Stops[0]
		for _, s := range v.Stops {
			if s.StopSequence < first.StopSequence {
				first = s
			}
			f.stopName[s.StopUID] = s.StopName.Zhtw
		}
		key := busDailyOriginKey(uid, dir)
		if f.originUID[key] == nil {
			f.originUID[key] = make(map[string]struct{}, 1)
			f.originName[key] = make(map[string]struct{}, 1)
		}
		f.originUID[key][first.StopUID] = struct{}{}
		f.originName[key][first.StopName.Zhtw] = struct{}{}
	}
	return f
}

// keep reports whether a trip whose first timed stop is firstStopUID belongs
// to (uid, dir). TDX registers a circular route's return-leg trips under both
// direction arrays (Taoyuan does this route-wide), so a trip departing the
// opposite direction's origin is a misfiled return trip, not a schedule.
// Names decide, not UIDs: TDX gives paired roadside stops distinct UIDs.
// Every uncertain case keeps the trip — unknown stop, no StopOfRoute entry,
// or both termini sharing a name (a loop that starts and ends at one station).
func (f *busDailyOriginFilter) keep(uid string, dir uint8, firstStopUID string) bool {
	if f == nil {
		return true
	}
	thisKey := busDailyOriginKey(uid, dir)
	if _, ok := f.originUID[thisKey][firstStopUID]; ok {
		return true
	}
	thisNames := f.originName[thisKey]
	if len(thisNames) == 0 {
		return true
	}
	otherNames := f.originName[busDailyOriginKey(uid, 1-dir)]
	for n := range thisNames {
		if _, ok := otherNames[n]; ok {
			return true
		}
	}
	name, ok := f.stopName[firstStopUID]
	if !ok {
		return true
	}
	if _, ok := thisNames[name]; ok {
		return true
	}
	if _, ok := otherNames[name]; ok {
		return false
	}
	return true
}

// loadBusDailyTimetable assembles one city's daily timetables from an opened
// decoder and writes each subroute's protobuf into Redis under
// bus_daily_timetable:<subRouteUID> (TTL 26h). It consumes the decoder from
// the opening '[' onward; the loader hands it an unopened decoder over
// reconstructed raw_tdx.bus_dailytimetable bytes. src supplies the city's raw
// StopOfRoute landing for the direction filter (nil disables it). db is unused
// (this dataset is Redis-only); the parameter keeps the loadSpec signature.
func loadBusDailyTimetable(ctx context.Context, dec *json.Decoder, src loadSource, _ *pgxpool.Pool, rc *redis.Client, city string) error {
	if strings.TrimSpace(city) == "" {
		return errors.New("bus daily timetable: city is required")
	}
	entries, err := decodeLoadArray[rawBusDailytimetable](dec, "bus daily timetable "+city, func(_ int, timetable rawBusDailytimetable) error {
		return validateBusDailyTimetable(timetable)
	})
	if err != nil {
		return err
	}
	q := newLoadQuarantine("bus_dailytimetable", city)
	defer q.report()
	for _, temp := range entries {
		q.consider("trip", len(temp.Timetables))
		for _, t := range temp.Timetables {
			q.consider("stoptime", len(t.StopTimes))
		}
	}
	filter := newBusDailyOriginFilter(ctx, src, city)
	// Misfiled trips bypass the quarantine on purpose: Taoyuan misfiles ~40%
	// of its trips (see keep), and quarantine's ratio gate would fail the
	// whole city over an expected, correctly-filtered data shape.
	misfiled := 0
	misfiledSample := ""
	mp := make(map[string]map[int32]*models.Bus_DirectionTimetable, 300)
	seenTrips := make(map[string]*models.Bus_DailyTimetable)
	for _, temp := range entries {
		uid, dir, err := canonicalBusDailyIdentity(city, temp.SubRouteUID, *temp.Direction)
		if err != nil {
			return err
		}
		if _, exists := mp[uid]; !exists {
			mp[uid] = make(map[int32]*models.Bus_DirectionTimetable, 4)
		}
		if _, exists := mp[uid][int32(dir)]; !exists {
			mp[uid][int32(dir)] = &models.Bus_DirectionTimetable{
				DailyTimetables: make([]*models.Bus_DailyTimetable, 0, 64),
			}
		}
		for _, t := range temp.Timetables {
			firstStop := t.StopTimes[0]
			for _, st := range t.StopTimes[1:] {
				if st.StopSequence < firstStop.StopSequence {
					firstStop = st
				}
			}
			if !filter.keep(uid, dir, firstStop.StopUID) {
				misfiled++
				if misfiledSample == "" {
					misfiledSample = fmt.Sprintf("TripID %q for %s/%d departs %s", t.TripID, uid, dir, firstStop.StopUID)
				}
				continue
			}
			stop := make([]*models.Bus_StopTime, 0, len(t.StopTimes))
			seenStops := make(map[int64]*models.Bus_StopTime, len(t.StopTimes))
			for _, st := range t.StopTimes {
				candidate := &models.Bus_StopTime{
					StopSequence:  int32(st.StopSequence),
					ArrivalTime:   st.ArrivalTime,
					DepartureTime: st.DepartureTime,
					StopUID:       st.StopUID,
				}
				if prior, exists := seenStops[st.StopSequence]; exists {
					// First variant wins: TDX repeats a stop sequence with a
					// different time and does not say which is right, and one
					// such trip is not worth the city's whole timetable.
					if !proto.Equal(prior, candidate) {
						q.drop("stoptime", "stoptime_divergent", fmt.Sprintf("TripID %q StopSequence %d", t.TripID, st.StopSequence))
					}
					continue
				}
				seenStops[st.StopSequence] = candidate
				stop = append(stop, candidate)
			}
			timetable := &models.Bus_DailyTimetable{
				TripID:     t.TripID,
				IsLowFloor: t.IsLowFloor,
				StopTimes:  stop,
			}
			key := fmt.Sprintf("%s\x00%d\x00%s", uid, dir, t.TripID)
			if prior, exists := seenTrips[key]; exists {
				// First variant wins, as for the stop times above.
				if !proto.Equal(prior, timetable) {
					q.drop("trip", "trip_divergent", fmt.Sprintf("TripID %q for %s/%d", t.TripID, uid, dir))
				}
				continue
			}
			seenTrips[key] = timetable
			mp[uid][int32(dir)].DailyTimetables = append(mp[uid][int32(dir)].DailyTimetables, timetable)
		}
	}
	if misfiled > 0 {
		log.Infof("[LOAD] action=bus_dailytimetable event=misfiled_direction_trips city=%s dropped=%d first=%s",
			city, misfiled, logSafeDetail(misfiledSample))
	}
	// Past the ratio the city's timetable fails instead of publishing a gutted
	// one; the previous load's Redis payload stays in place.
	if err := q.exceeded(); err != nil {
		return err
	}
	type redisWrite struct {
		key   string
		value []byte
	}
	uids := make([]string, 0, len(mp))
	for uid := range mp {
		uids = append(uids, uid)
	}
	sort.Strings(uids)
	writes := make([]redisWrite, 0, len(uids))
	for _, subRouteUID := range uids {
		pbRoute := &models.Bus_DailyTimetables{
			SubRouteUID: subRouteUID,
			Direction:   mp[subRouteUID],
		}
		pb, err := (proto.MarshalOptions{Deterministic: true}).Marshal(pbRoute)
		if err != nil {
			return fmt.Errorf("bus daily timetable %s marshal %s: %w", city, subRouteUID, err)
		}
		writes = append(writes, redisWrite{key: shared.BusDailyTimetableKey(subRouteUID), value: pb})
	}
	if len(writes) == 0 {
		return nil
	}
	if err := ctx.Err(); err != nil {
		return fmt.Errorf("bus daily timetable %s context before Redis transaction: %w", city, err)
	}
	if rc == nil {
		return fmt.Errorf("bus daily timetable %s Redis transaction: nil client", city)
	}
	pipe := rc.TxPipeline()
	defer pipe.Discard()
	for _, write := range writes {
		pipe.Set(ctx, write.key, write.value, 26*time.Hour)
	}
	if err := ctx.Err(); err != nil {
		pipe.Discard()
		return fmt.Errorf("bus daily timetable %s context before Redis transaction: %w", city, err)
	}
	_, execErr := pipe.Exec(ctx)
	if ctxErr := ctx.Err(); ctxErr != nil {
		return fmt.Errorf("bus daily timetable %s context during Redis transaction: %w", city, errors.Join(ctxErr, execErr))
	}
	if execErr != nil {
		return fmt.Errorf("bus daily timetable %s Redis transaction: %w", city, execErr)
	}
	log.Infof("[BUS] action=bus_dailyroute event=complete city=%s", city)
	return nil
}

func validateBusDailyTimetable(timetable rawBusDailytimetable) error {
	if strings.TrimSpace(timetable.SubRouteUID) == "" {
		return errors.New("missing SubRouteUID")
	}
	if timetable.Direction == nil {
		return errors.New("missing Direction")
	}
	if *timetable.Direction > 1 {
		return fmt.Errorf("invalid Direction %d, want 0 or 1", *timetable.Direction)
	}
	if len(timetable.Timetables) == 0 {
		return errors.New("missing Timetables")
	}
	for timetableIndex, trip := range timetable.Timetables {
		if strings.TrimSpace(trip.TripID) == "" {
			return fmt.Errorf("timetables element %d missing TripID", timetableIndex)
		}
		if len(trip.StopTimes) == 0 {
			return fmt.Errorf("timetables element %d missing StopTimes", timetableIndex)
		}
		for stopIndex, stop := range trip.StopTimes {
			prefix := fmt.Sprintf("Timetables element %d StopTimes element %d", timetableIndex, stopIndex)
			if stop.StopSequence <= 0 || stop.StopSequence > 1<<31-1 {
				return fmt.Errorf("%s StopSequence must be between 1 and %d", prefix, int64(1<<31-1))
			}
			if strings.TrimSpace(stop.StopUID) == "" {
				return fmt.Errorf("%s StopUID is required", prefix)
			}
			if !validClock(stop.ArrivalTime) {
				return fmt.Errorf("%s ArrivalTime is invalid: %q", prefix, stop.ArrivalTime)
			}
			if !validClock(stop.DepartureTime) {
				return fmt.Errorf("%s DepartureTime is invalid: %q", prefix, stop.DepartureTime)
			}
		}
	}
	return nil
}

func canonicalBusDailyIdentity(city, subRouteUID string, direction uint8) (string, uint8, error) {
	prefix, ok := citymap[city]
	if !ok || prefix == "" {
		return "", 0, fmt.Errorf("bus daily timetable %s: authority is unknown", city)
	}
	uid, dir := shared.CanonicalSubroute(city, subRouteUID, direction)
	if strings.TrimSpace(uid) == "" {
		return "", 0, fmt.Errorf("bus daily timetable %s: canonical SubRouteUID is empty for %q", city, subRouteUID)
	}
	if dir > 1 {
		return "", 0, fmt.Errorf("bus daily timetable %s: canonical Direction must be 0 or 1, got %d", city, dir)
	}
	if !uidBelongsToPrefix(uid, prefix) {
		return "", 0, fmt.Errorf("bus daily timetable %s: canonical SubRouteUID %q does not belong to authority %s", city, uid, prefix)
	}
	return uid, dir, nil
}

// jsonOrNil returns nil for empty or literal-null JSON so the value is stored as
// SQL NULL rather than the string "null".
func jsonOrNil(r json.RawMessage) []byte {
	if len(r) == 0 || string(r) == "null" {
		return nil
	}
	return r
}

// cloneBusFare deep-copies a fare so a route-wide fare shared across subroutes
// can be attached to each without aliasing the same proto message. Returns nil
// for a nil input.
func cloneBusFare(f *models.Bus_Fare) *models.Bus_Fare {
	if f == nil {
		return nil
	}
	return proto.Clone(f).(*models.Bus_Fare)
}
