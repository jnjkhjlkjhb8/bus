package main

import (
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"

	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
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
// as the authority_code for operators. Note it lacks the "County" suffixes that
// appear in cities (e.g. "Miaoli" not "MiaoliCounty").
var citymap = map[string]string{
	"Taipei": "TPE", "NewTaipei": "NWT", "Taoyuan": "TAO", "Taichung": "TXG",
	"Tainan": "TNN", "Kaohsiung": "KHH", "InterCity": "THB", "Keelung": "KEE",
	"Hsinchu": "HSZ", "HsinchuCounty": "HSQ", "Miaoli": "MIA", "Changhua": "CHA",
	"Nantou": "NAN", "Chiayi": "CYI", "ChiayiCounty": "CYQ", "Yunlin": "YUN",
	"Pingtung": "PIF", "Yilan": "ILA", "Hualien": "HUA", "Taitung": "TTT",
	"Penghu": "PEN", "Kinmen": "KIN", "Lienchiang": "LIE",
}

// citymap2 is the inverse of citymap, resolving a short prefix back to a TDX
// city code. Used when rail data carries LocationCityCode prefixes.
var citymap2 = map[string]string{
	"TPE": "Taipei", "NWT": "NewTaipei", "TAO": "Taoyuan", "TXG": "Taichung",
	"TNN": "Tainan", "KHH": "Kaohsiung", "THB": "InterCity", "KEE": "Keelung",
	"HSZ": "Hsinchu", "HSQ": "HsinchuCounty", "MIA": "Miaoli", "CHA": "Changhua",
	"NAN": "Nantou", "CYI": "Chiayi", "CYQ": "ChiayiCounty", "YUN": "Yunlin",
	"PIF": "Pingtung", "ILA": "Yilan", "HUA": "Hualien", "TTT": "Taitung",
	"PEN": "Penghu", "KIN": "Kinmen", "LIE": "Lienchiang",
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
								  s ->> 'StationUID',
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
			DO UPDATE SET city = excluded.city,geometry = EXCLUDED.geometry,stops = EXCLUDED.stops,depart = EXCLUDED.depart,destin = EXCLUDED.destin,schedule = EXCLUDED.schedule,operators = EXCLUDED.operators,updated_at = NOW();
			`

// busScheduleUpsertSQL upserts bus timetable and frequency rows from temp_bus
// into bus_schedule. The dual-purpose column names (e.g.
// "stop_uid/MinHeadwayMins") hold either a fixed timetable stop or a
// frequency-based headway depending on the type flag.
const busScheduleUpsertSQL = `INSERT INTO bus_schedule (sub_route_uid, direction, type, tripid, islowfloor, stopsequence, "stop_uid/MinHeadwayMins", "stop_name/MaxHeadwayMins", "arrival_time/StartTime", "departure_time/EndTime", service_day, updated_at)
				SELECT DISTINCT ON (uid, dir, type, sdays, id, stopuid)
					uid, dir, type, id, floor, seq, stopuid, stopname, arrival::time, departure::time, sdays, NOW()
				FROM temp_bus
				ORDER BY uid, dir, type, sdays, id, stopuid
				ON CONFLICT (sub_route_uid, direction, type, service_day, tripid, "stop_uid/MinHeadwayMins")
				DO UPDATE SET islowfloor = EXCLUDED.islowfloor, stopsequence = EXCLUDED.stopsequence,
					"stop_name/MaxHeadwayMins" = EXCLUDED."stop_name/MaxHeadwayMins",
					"arrival_time/StartTime" = EXCLUDED."arrival_time/StartTime",
					"departure_time/EndTime" = EXCLUDED."departure_time/EndTime",
					updated_at = NOW()`

// busRouteEtaKey returns the Redis key holding (and the channel publishing) the
// per-subroute ETA snapshot consumed by the router's route-arrival stream.
func busRouteEtaKey(subRouteUID string) string {
	return fmt.Sprintf("bus_eta_route:%s", subRouteUID)
}

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
	Direction   uint8  `json:"Direction"`
	Timetables  []struct {
		TripID     string `json:"TripID"`
		IsLowFloor bool   `json:"IsLowFloor"`
		StopTimes  []struct {
			StopSequence  int    `json:"StopSequence"`
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
	PlateNumb     string `json:"PlateNumb"`
	StopUID       string `json:"StopUID"`
	SubRouteUID   string `json:"SubRouteUID"`
	Direction     uint8  `json:"Direction"`
	EstimatedTime int32  `json:"EstimatedTime"`
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
	Azimuth    int     `json:"Azimuth"`
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
	SubRouteName string
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

// rawBusStation decodes a TDX Bus/Station element: a physical station and its
// optional group membership, used to build station groups.
type rawBusStation struct {
	StationUID     string `json:"StationUID"`
	StationID      string `json:"StationID"`
	StationGroupID string `json:"StationGroupID"`
	StationName    struct {
		Zhtw string `json:"Zh_tw"`
	} `json:"StationName"`
	StationPosition struct {
		PositionLon float64 `json:"PositionLon"`
		PositionLat float64 `json:"PositionLat"`
	} `json:"StationPosition"`
}

// rawBusStationGroup decodes a TDX Bus/StationGroup element: a named group of
// nearby stations sharing one position.
type rawBusStationGroup struct {
	StationGroupUID  string `json:"StationGroupUID"`
	StationGroupID   string `json:"StationGroupID"`
	StationGroupName struct {
		Zhtw string `json:"Zh_tw"`
	} `json:"StationGroupName"`
	StationGroupPosition struct {
		PositionLon float64 `json:"PositionLon"`
		PositionLat float64 `json:"PositionLat"`
	} `json:"StationGroupPosition"`
}

// rawBusOperator decodes a TDX Bus/Operator element and doubles as the row shape
// for the DB fallback in busOperators.
type rawBusOperator struct {
	OperatorID   string `json:"OperatorID"`
	OperatorName struct {
		Zhtw string `json:"Zh_tw"`
	} `json:"OperatorName"`
	OperatorPhone string `json:"OperatorPhone"`
	OperatorUrl   string `json:"OperatorUrl"`
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

// busDailyroute caches each subroute's daily timetable in Redis as a protobuf
// under bus_daily_timetable:<subRouteUID>, TTL just under 24h so a missed daily
// refresh expires the stale copy. A short skip list omits cities whose daily
// timetable TDX does not serve. Runs both at boot and in the 03:00 static cron.
func busDailyroute(client *resty.Client, rc *redis.Client) {
	log.Infof("[bus] action=bus_dailyroute event=start")
	var temp rawBusDailytimetable
	for _, city := range cities {
		if city == "Taipei" || city == "NewTaipei" || city == "Tainan" || city == "KinmenCounty" || city == "LienchiangCounty" {
			continue
		}
		var url string
		if city == "InterCity" {
			url = fmt.Sprintf("/v2/Bus/DailyTimeTable/InterCity")
		} else {
			url = fmt.Sprintf("/v2/Bus/DailyTimeTable/City/%s", city)
		}
		log.Infof("[bus] action=bus_dailyroute city=%s event=city_start", city)
		dec, comp, err, flipopen := callApi(client, rc, url, "DailyTimeTable"+city)
		if err != nil {
			log.Infof("[bus] action=bus_dailyroute city=%s event=skip reason=api_error,error=%s", city, err)
			continue
		}
		if !comp {
			log.Infof("[bus] action=bus_dailyroute city=%s event=skip reason=already", city)
			continue
		}
		if _, err := dec.Token(); err != nil {
			log.Infof("[bus] action=bus_dailyroute city=%s event=decode_error error=%v", city, err)
			continue
		}
		func() {
			defer flipopen()
			pipe := rc.Pipeline()
			mp := make(map[string]map[int32]*models.Temp, 300)
			for dec.More() {
				temp = rawBusDailytimetable{}
				if err := dec.Decode(&temp); err == nil {
					uid, dir := makethatsame(city, temp.SubRouteUID, temp.Direction)
					if _, exists := mp[uid]; !exists {
						mp[uid] = make(map[int32]*models.Temp, 4)
					}
					if _, exists := mp[uid][int32(dir)]; !exists {
						mp[uid][int32(dir)] = &models.Temp{
							DailyTimetables: make([]*models.Bus_DailyTimetable, 0, 64),
						}
					}
					for _, t := range temp.Timetables {
						stop := make([]*models.Temp_StopTimes, len(t.StopTimes))
						for i, st := range t.StopTimes {
							stop[i] = &models.Temp_StopTimes{
								StopSequence:  int32(st.StopSequence),
								ArrivalTime:   st.ArrivalTime,
								DepartureTime: st.DepartureTime,
							}
						}
						timtable := &models.Bus_DailyTimetable{
							TripID:     t.TripID,
							IsLowFloor: t.IsLowFloor,
							StopTimes:  stop,
						}
						mp[uid][int32(dir)].DailyTimetables = append(mp[uid][int32(dir)].DailyTimetables, timtable)
					}
				}
			}
			for subRouteUID, t := range mp {
				pbRoute := &models.Bus_DailyTimetables{
					SubRouteUID: subRouteUID,
					Direction:   t,
				}
				pb, err := proto.Marshal(pbRoute)
				if err != nil {
					log.Infof("[bus] action=bus_dailyroute subRouteUID=%s event=marshal_error error=%v", subRouteUID, err)
					continue
				}
				pipe.Set(fmt.Sprintf("bus_daily_timetable:%s", subRouteUID), pb, 23*time.Hour+30*time.Minute)
			}
			_, _ = pipe.Exec()
			log.Infof("[bus] action= %s bus_dailyroute event=complete", city)
		}()
	}
	log.Infof("[bus] action=bus_dailyroute event=complete")
}

// jsonOrNil returns nil for empty or literal-null JSON so the value is stored as
// SQL NULL rather than the string "null".
func jsonOrNil(r json.RawMessage) []byte {
	if len(r) == 0 || string(r) == "null" {
		return nil
	}
	return r
}

// cloneBusFare deep-copies a fare and stamps it with subRouteUID, so a
// route-wide fare shared across subroutes can be attached to each without
// aliasing the same proto message. Returns nil for a nil input.
func cloneBusFare(f *models.Bus_Fare, subRouteUID string) *models.Bus_Fare {
	if f == nil {
		return nil
	}
	cloned := proto.Clone(f).(*models.Bus_Fare)
	cloned.SubRouteUid = subRouteUID
	return cloned
}

// cityFares fetches a city's route fares and returns two lookups: fares keyed by
// subroute UID, and route-wide fares (IsForAllSubRoutes) keyed by route UID for
// subroutes without their own fare. Returns nil, nil on fetch/decode failure.
// It deletes the IMS cache first so fares are always refetched.
func cityFares(ctx context.Context, client *resty.Client, rc *redis.Client, city string) (map[string]*models.Bus_Fare, map[string]*models.Bus_Fare) {
	url := fmt.Sprintf("/v2/Bus/RouteFare/City/%s", city)
	if city == "InterCity" {
		url = "/v2/Bus/RouteFare/InterCity"
	}
	cacheKey := "bus_RouteFare" + city
	if err := rc.Del("LastTimeGet_" + cacheKey).Err(); err != nil {
		log.Infof("[BUS_FARE] action=bus_fare city=%s event=cache_delete_error error=%v", city, err)
	}
	dec, comp, err, flipopen := callApi(client, rc, url, cacheKey)
	if err != nil || !comp {
		log.Infof("[BUS_FARE] action=bus_fare city=%s event=skip reason=api_error", city)
		return nil, nil
	}
	defer flipopen()
	if _, err := dec.Token(); err != nil {
		log.Infof("[BUS_FARE] action=bus_fare city=%s event=decode_error error=%v", city, err)
		return nil, nil
	}
	pre := citymap[city]
	bySub := make(map[string]*models.Bus_Fare)
	byRoute := make(map[string]*models.Bus_Fare)
	for dec.More() {
		var f rawBusFare
		if err := dec.Decode(&f); err != nil {
			continue
		}
		fare := &models.Bus_Fare{
			FarePricingType:  f.FarePricingType,
			IsFreeBus:        f.IsFreeBus == 1,
			SectionFaresJson: jsonOrNil(f.SectionFares),
			StageFaresJson:   jsonOrNil(f.StageFares),
			OdFaresJson:      jsonOrNil(f.ODFares),
		}
		if f.SubRouteID != "" {
			uid := pre + f.SubRouteID
			fare.SubRouteUid = uid
			bySub[uid] = fare
		}
		if f.IsForAllSubRoutes == 1 && f.RouteID != "" {
			byRoute[pre+f.RouteID] = fare
		}
	}
	log.Infof("[BUS_FARE] action=bus_fare city=%s event=success sub_count=%d route_count=%d", city, len(bySub), len(byRoute))
	return bySub, byRoute
}

// busOperators returns a city's operators keyed by OperatorID, fetching from TDX
// and upserting into bus_operators. If the fetch fails or returns no update, it
// falls back to reading the previously stored operators from the DB so a
// transient TDX outage does not blank out operator detail on routes.
func busOperators(ctx context.Context, client *resty.Client, rc *redis.Client, db *pgxpool.Pool, city string) map[string]rawBusOperator {
	result := make(map[string]rawBusOperator)
	var url string
	if city == "InterCity" {
		url = "/v2/Bus/Operator/InterCity"
	} else {
		url = fmt.Sprintf("/v2/Bus/Operator/City/%s", city)
	}
	dec, comp, err, flipopen := callApi(client, rc, url, "bus_Operator"+city)
	if err != nil || !comp {
		rows, qErr := db.Query(ctx, `SELECT operator_id, operator_name, COALESCE(operator_phone,''), COALESCE(operator_url,''), authority_code FROM bus_operators WHERE authority_code = $1`, citymap[city])
		if qErr != nil {
			log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=db_fallback_error error=%v", city, qErr)
			return result
		}
		defer rows.Close()
		for rows.Next() {
			var op rawBusOperator
			if err := rows.Scan(&op.OperatorID, &op.OperatorName.Zhtw, &op.OperatorPhone, &op.OperatorUrl, &op.AuthorityCode); err == nil {
				result[op.OperatorID] = op
			}
		}
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=loaded_from_db count=%d", city, len(result))
		return result
	}
	defer flipopen()
	if _, err := dec.Token(); err != nil {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=decode_error error=%v", city, err)
		return result
	}
	var copyRows [][]interface{}
	for dec.More() {
		var op rawBusOperator
		if err := dec.Decode(&op); err != nil {
			continue
		}
		result[op.OperatorID] = op
		copyRows = append(copyRows, []interface{}{op.OperatorID, op.AuthorityCode, op.OperatorName.Zhtw, op.OperatorPhone, op.OperatorUrl})
	}
	if len(copyRows) == 0 {
		return result
	}
	b, err := db.Begin(ctx)
	if err != nil {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=begin_error error=%v", city, err)
		return result
	}
	defer func() { _ = b.Rollback(ctx) }()
	if _, err := b.Exec(ctx, `CREATE TEMP TABLE temp_op (oid text, ac text, name text, phone text, url text) ON COMMIT DROP`); err != nil {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=create_temp_error error=%v", city, err)
		return result
	}
	if _, err := b.CopyFrom(ctx, pgx.Identifier{"temp_op"}, []string{"oid", "ac", "name", "phone", "url"}, pgx.CopyFromRows(copyRows)); err != nil {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=copyfrom_error error=%v", city, err)
		return result
	}
	if _, err := b.Exec(ctx, `INSERT INTO bus_operators (operator_id, authority_code, operator_name, operator_phone, operator_url)
		SELECT DISTINCT ON (oid, ac) oid, ac, name, phone, url FROM temp_op
		ON CONFLICT (operator_id, authority_code) DO UPDATE SET
			operator_name  = EXCLUDED.operator_name,
			operator_phone = EXCLUDED.operator_phone,
			operator_url   = EXCLUDED.operator_url,
			updated_at     = NOW()`); err != nil {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=insert_error error=%v", city, err)
		return result
	}
	if err := b.Commit(ctx); err != nil {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=commit_error error=%v", city, err)
	} else {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=complete count=%d", city, len(result))
	}
	return result
}
