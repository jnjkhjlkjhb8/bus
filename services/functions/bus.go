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
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
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

// busScheduleInsertSQL inserts bus timetable and frequency rows from temp_bus
// into bus_schedule after saveschedule has deleted the city's partition in the
// same transaction (partition-replace). No DISTINCT ON and no ON CONFLICT: the
// natural key (sub_route_uid, direction, type, service_day, tripid,
// "stop_uid/MinHeadwayMins") is not unique in real data — a circular route
// visits the same stop twice in one trip — so every raw row must survive rather
// than be collapsed. The dual-purpose column names (e.g.
// "stop_uid/MinHeadwayMins") hold either a fixed timetable stop or a
// frequency-based headway depending on the type flag.
const busScheduleInsertSQL = `INSERT INTO bus_schedule (sub_route_uid, direction, type, tripid, islowfloor, stopsequence, "stop_uid/MinHeadwayMins", "stop_name/MaxHeadwayMins", "arrival_time/StartTime", "departure_time/EndTime", service_day, updated_at)
				SELECT uid, dir, type, id, floor, seq, stopuid, stopname, arrival::time, departure::time, sdays, NOW()
				FROM temp_bus`

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

// rawBusOperator decodes a TDX Bus/Operator element and doubles as the row shape
// for the DB fallback in busOperatorsFromDB.
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

// busDailyTimetableSkip lists cities whose daily-timetable feed TDX does not
// serve; both the legacy fetch path (busDailyroute) and the loader path
// (loadBusDailyTimetable partitions) skip them so landed and loaded partitions
// agree.
func busDailyTimetableSkip(city string) bool {
	return city == "Taipei" || city == "NewTaipei" || city == "Tainan" ||
		city == "KinmenCounty" || city == "LienchiangCounty"
}

// busDailyroute caches each subroute's daily timetable in Redis as a protobuf
// under bus_daily_timetable:<subRouteUID>, TTL just under 24h so a missed daily
// refresh expires the stale copy. A short skip list omits cities whose daily
// timetable TDX does not serve. Runs both at boot and in the 03:00 static cron.
// The fetch wrapper only owns the TDX call; the decoder-side assembly and Redis
// writes are shared with the loader path via loadBusDailyTimetable.
func busDailyroute(client *resty.Client, rc *redis.Client) {
	log.Infof("[bus] action=bus_dailyroute event=start")
	for _, city := range cities {
		if busDailyTimetableSkip(city) {
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
		func() {
			defer flipopen()
			if err := loadBusDailyTimetable(context.Background(), dec, nil, rc, city); err != nil {
				log.Infof("[bus] action=bus_dailyroute city=%s event=error error=%v", city, err)
			}
		}()
	}
	log.Infof("[bus] action=bus_dailyroute event=complete")
}

// loadBusDailyTimetable assembles one city's daily timetables from an opened
// decoder and writes each subroute's protobuf into Redis under
// bus_daily_timetable:<subRouteUID> (TTL 23h30m), byte-identical to the legacy
// busDailyroute transform. It consumes the decoder from the opening '[' onward,
// so both the TDX fetch wrapper and the loader (which hands an unopened decoder
// over reconstructed raw_tdx.bus_dailytimetable bytes) call it the same way. db
// is unused (this dataset is Redis-only); the parameter keeps the loadSpec
// signature.
func loadBusDailyTimetable(_ context.Context, dec *json.Decoder, _ *pgxpool.Pool, rc *redis.Client, city string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[bus] action=bus_dailyroute city=%s event=decode_error error=%v", city, err)
		return err
	}
	pipe := rc.Pipeline()
	mp := make(map[string]map[int32]*models.Temp, 300)
	var temp rawBusDailytimetable
	for dec.More() {
		temp = rawBusDailytimetable{}
		if err := dec.Decode(&temp); err == nil {
			uid, dir := shared.CanonicalSubroute(city, temp.SubRouteUID, temp.Direction)
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
	log.Infof("[BUS] action=bus_dailyroute event=complete city=%s", city)
	return nil
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

// loadBusFares parses a city's route fares from an already-opened decoder (the
// raw_tdx loader, via loadBusFareMaps) into two lookups: fares keyed by subroute
// UID, and route-wide fares (IsForAllSubRoutes) keyed by route UID. Pure parsing
// — no SQL; the fare protos are embedded into bus_subroutes / bus_static by the
// downstream upserts.
func loadBusFares(dec *json.Decoder, city string) (map[string]*models.Bus_Fare, map[string]*models.Bus_Fare, error) {
	if _, err := dec.Token(); err != nil {
		log.Infof("[BUS_FARE] action=bus_fare city=%s event=decode_error error=%v", city, err)
		return nil, nil, err
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
	return bySub, byRoute, nil
}

// busOperatorsFromDB reads a city's previously stored operators from
// bus_operators, the fallback used when the TDX operator feed is unavailable so
// a transient outage does not blank out operator detail on routes. The SELECT is
// byte-identical to the legacy inline fallback.
func busOperatorsFromDB(ctx context.Context, db *pgxpool.Pool, city string) map[string]rawBusOperator {
	result := make(map[string]rawBusOperator)
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

// loadBusOperators decodes a city's operators from an already-opened decoder
// (from callApi or the raw_tdx loader), upserts them into bus_operators, and
// returns them keyed by OperatorID for the subroute assembly. The temp_op COPY
// and ON CONFLICT (operator_id, authority_code) upsert are byte-identical to
// the legacy fetch-coupled body. The map is returned even on a write error so
// enrichment can proceed from whatever decoded.
func loadBusOperators(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, city string) (map[string]rawBusOperator, error) {
	result := make(map[string]rawBusOperator)
	if _, err := dec.Token(); err != nil {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=decode_error error=%v", city, err)
		return result, err
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
		return result, nil
	}
	b, err := db.Begin(ctx)
	if err != nil {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=begin_error error=%v", city, err)
		return result, err
	}
	defer func() { _ = b.Rollback(ctx) }()
	if _, err := b.Exec(ctx, `CREATE TEMP TABLE temp_op (oid text, ac text, name text, phone text, url text) ON COMMIT DROP`); err != nil {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=create_temp_error error=%v", city, err)
		return result, err
	}
	if _, err := b.CopyFrom(ctx, pgx.Identifier{"temp_op"}, []string{"oid", "ac", "name", "phone", "url"}, pgx.CopyFromRows(copyRows)); err != nil {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=copyfrom_error error=%v", city, err)
		return result, err
	}
	if _, err := b.Exec(ctx, `INSERT INTO bus_operators (operator_id, authority_code, operator_name, operator_phone, operator_url)
		SELECT DISTINCT ON (oid, ac) oid, ac, name, phone, url FROM temp_op
		ON CONFLICT (operator_id, authority_code) DO UPDATE SET
			operator_name  = EXCLUDED.operator_name,
			operator_phone = EXCLUDED.operator_phone,
			operator_url   = EXCLUDED.operator_url,
			updated_at     = NOW()`); err != nil {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=insert_error error=%v", city, err)
		return result, err
	}
	if err := b.Commit(ctx); err != nil {
		log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=commit_error error=%v", city, err)
		return result, err
	}
	log.Infof("[BUS_OPERATOR] action=busOperators city=%s event=complete count=%d", city, len(result))
	return result, nil
}
