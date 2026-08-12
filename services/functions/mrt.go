package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"go.uber.org/zap"
	"google.golang.org/protobuf/proto"
)

// mrtStation decodes a TDX Rail/Metro/Station element used for the metro static
// station table.
type mrtStation struct {
	StationPosition struct {
		PositionLon float64 `json:"PositionLon"`
		PositionLat float64 `json:"PositionLat"`
	} `json:"StationPosition"`
	LocationCity       string `json:"LocationCity"`
	StationID          string `json:"StationID"`
	BikeAllowOnHoliday bool   `json:"BikeAllowOnHoliday"`
	StationName        struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"StationName"`
}

// mrtFirstlast decodes a TDX Rail/Metro/FirstLastTimetable element: first/last
// train times per station, line, and destination for a weekly service pattern.
type mrtFirstlast struct {
	LineID                 string `json:"LineID"`
	StationID              string `json:"StationID"`
	TripHeadSign           string `json:"TripHeadSign"`
	DestinationStaionID    string `json:"DestinationStaionID"`
	DestinationStationName struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"DestinationStationName"`
	FirstTrainTime string `json:"FirstTrainTime"`
	LastTrainTime  string `json:"LastTrainTime"`
	ServiceDay     struct {
		Monday           bool `json:"Monday"`
		Tuesday          bool `json:"Tuesday"`
		Wednesday        bool `json:"Wednesday"`
		Thursday         bool `json:"Thursday"`
		Friday           bool `json:"Friday"`
		Saturday         bool `json:"Saturday"`
		Sunday           bool `json:"Sunday"`
		NationalHolidays bool `json:"NationalHolidays"`
	} `json:"ServiceDay"`
}

// mrtLive decodes a TDX Rail/Metro/LiveBoard element: the live estimate for a
// train approaching a station toward a destination.
//
//nolint:unused // ADR-0014: TDX metro LiveBoard is paused, not removed
type mrtLive struct {
	LineID                 string `json:"LineID"`
	StationID              string `json:"StationID"`
	TripHeadSign           string `json:"TripHeadSign"`
	city                   string
	DestinationStaionID    string `json:"DestinationStaionID"`
	DestinationStationName struct {
		ZhTw string `json:"Zh_tw"`
	} `json:"DestinationStationName"`
	ServiceStatus uint8 `json:"ServiceStatus"`
	EstimateTime  int32 `json:"EstimateTime"`
}

// loadMrtStations upserts one metro system's stations into mrt_station via a
// temp-table COPY then ON CONFLICT (station_id, system) upsert. It consumes an
// already-opened decoder; the temp_mrt COPY and upsert are byte-identical to the
// legacy transform.
func loadMrtStations(ctx context.Context, dec *json.Decoder, sink loadSink, system string) error {
	if strings.TrimSpace(system) == "" {
		return errors.New("mrt stations: system is required")
	}
	stations, err := decodeLoadArray[mrtStation](dec, "mrt stations "+system, func(_ int, station mrtStation) error {
		if strings.TrimSpace(station.StationID) == "" {
			return errors.New("StationID is required")
		}
		if !validPosition(station.StationPosition.PositionLon, station.StationPosition.PositionLat) {
			return _oops.With("position_lon", station.StationPosition.PositionLon).With("position_lat", station.StationPosition.PositionLat).Errorf("position is invalid: lon= lat=")
		}
		return nil
	})
	if err != nil {
		return err
	}
	row := [][]any{}
	seen := make(map[string][]any, len(stations))
	for _, temp := range stations {
		g := fmt.Sprintf("POINT(%.6f %.6f)", temp.StationPosition.PositionLon, temp.StationPosition.PositionLat)
		candidate := []any{
			g,
			system,
			temp.StationName.ZhTw,
			temp.LocationCity,
			temp.StationID,
			temp.BikeAllowOnHoliday,
		}
		if err := appendUniqueLoadRow(&row, seen, system+"\x00"+temp.StationID, "station", candidate); err != nil {
			return _oops.With("system", system).Wrapf(err, "mrt stations")
		}
	}
	if len(row) == 0 {
		return nil
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "mrt_station",
		createSQL: `CREATE TEMP TABLE temp_mrt (
					geom text,
					system text,
					name text,
					city text,
					id text,
					bike bool
				) ON COMMIT DROP;`,
		tempTable: "temp_mrt",
		copyCols:  []string{"geom", "system", "name", "city", "id", "bike"},
		insertSQL: `INSERT INTO mrt_station (
					stationposition,
					system,
					name,
					city,
					station_id,
					bikeallowonholiday,
					updated_at
				)
				SELECT st_geomfromtext(geom, 4326), system, name, city,id, bike,NOW() FROM temp_mrt
				ON CONFLICT (station_id,system) DO UPDATE SET name = EXCLUDED.name,city = excluded.city,stationposition = EXCLUDED.stationposition,bikeallowonholiday = EXCLUDED.bikeallowonholiday,updated_at = NOW();`,
	}, row)
}

// loadMrtFirstlast rebuilds mrt_schedule (first/last train times) for one metro
// system as partition-replace: within ONE transaction it DELETEs the system's
// rows, COPYs the fresh rows into temp_mrt, then INSERTs them DISTINCT ON the
// natural key (station_id, lineid, destinationstaionid, serviceday, system).
// TDX FirstLastTimetable repeats that key within one system's payload (TRTC
// especially), so the drain MUST collapse the duplicates: the mrt_schedule_natural_key
// UNIQUE constraint (2026-06-14-perf-indexes.sql) — the same tuple PowerSync
// derives its row id from — rejects duplicate rows, so an un-deduped INSERT
// aborts the whole transaction and rolls back the partition DELETE, leaving the
// system's schedule permanently empty. It consumes an already-opened decoder.
// updated_at is stamped NOW() so the freshness probe (main.go's MAX(updated_at)
// per system) keeps working.
func loadMrtFirstlast(ctx context.Context, dec *json.Decoder, sink loadSink, system string) error {
	if strings.TrimSpace(system) == "" {
		return errors.New("mrt first-last: system is required")
	}
	timetables, err := decodeLoadArray[mrtFirstlast](dec, "mrt first-last "+system, func(_ int, timetable mrtFirstlast) error {
		if strings.TrimSpace(timetable.StationID) == "" {
			return errors.New("StationID is required")
		}
		if strings.TrimSpace(timetable.LineID) == "" {
			return errors.New("LineID is required")
		}
		if strings.TrimSpace(timetable.DestinationStaionID) == "" {
			return errors.New("DestinationStaionID is required")
		}
		// An empty first/last train time means the operator publishes no
		// window for this line/destination, not a defect; mrtServiceWindows
		// already skips a row it cannot parse. Only a malformed value is
		// rejected, matching the bus snapshot's empty-is-absent rule.
		if v := strings.TrimSpace(timetable.FirstTrainTime); v != "" {
			if _, ok := parseHHMM(v); !ok {
				return _oops.With("first_train_time", timetable.FirstTrainTime).Errorf("FirstTrainTime is invalid")
			}
		}
		if v := strings.TrimSpace(timetable.LastTrainTime); v != "" {
			if _, ok := parseHHMM(v); !ok {
				return _oops.With("last_train_time", timetable.LastTrainTime).Errorf("LastTrainTime is invalid")
			}
		}
		if mask(timetable.ServiceDay.Monday, timetable.ServiceDay.Tuesday, timetable.ServiceDay.Wednesday,
			timetable.ServiceDay.Thursday, timetable.ServiceDay.Friday, timetable.ServiceDay.Saturday,
			timetable.ServiceDay.Sunday, timetable.ServiceDay.NationalHolidays) == 0 {
			return errors.New("ServiceDay must enable at least one day")
		}
		return nil
	})
	if err != nil {
		return err
	}
	row := [][]any{}
	for _, temp := range timetables {
		row = append(row, []any{
			temp.StationID,
			temp.LineID,
			temp.TripHeadSign,
			temp.DestinationStaionID,
			temp.DestinationStationName.ZhTw,
			temp.FirstTrainTime,
			temp.LastTrainTime,
			mask(temp.ServiceDay.Monday, temp.ServiceDay.Tuesday, temp.ServiceDay.Wednesday, temp.ServiceDay.Thursday, temp.ServiceDay.Friday, temp.ServiceDay.Saturday, temp.ServiceDay.Sunday, temp.ServiceDay.NationalHolidays),
			system,
		})
	}
	// Partition-replace: DELETE this system's rows before re-inserting, then
	// DISTINCT ON the natural key so duplicates within the payload collapse to
	// one row. The DELETE clears the partition first, so the deduped batch can
	// never trip mrt_schedule_natural_key. (ON CONFLICT DO UPDATE would not help
	// here: two conflicting rows in one INSERT raise "cannot affect row a second
	// time" — the dedupe has to happen in the SELECT.)
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key:     "mrt_firstlast",
		preExec: []copyUpsertStmt{{sql: `DELETE FROM mrt_schedule WHERE system = $1`, args: []any{system}}},
		createSQL: `CREATE TEMP TABLE temp_mrt (
                               id text,
                               lid text,
							   sign text,
                               dsid text,
                               dsname text,
                               ft text,
                               lt text,
       						   mask int2,
       						   sys text
					) ON COMMIT DROP;`,
		tempTable: "temp_mrt",
		copyCols:  []string{"id", "lid", "sign", "dsid", "dsname", "ft", "lt", "mask", "sys"},
		insertSQL: `INSERT INTO mrt_schedule (
						station_id,
						lineid,
						destinationstaionid,
						destinationstationname,
						firsttraintime,
						lasttraintime,
						serviceday,
						system,
						created_at,
						updated_at,
						trip_head_sign
					)
					SELECT DISTINCT ON (id, lid, dsid, mask, sys)
						id,lid, dsid, dsname, ft, lt,mask,sys,NOW(),NOW(),sign FROM temp_mrt
					ORDER BY id, lid, dsid, mask, sys, ft, lt, dsname, sign`,
	}, row)
}

// mrtServiceWindow is one first/last-train window from mrt_schedule, in minutes
// since midnight; last exceeds 1440 when the last train runs past midnight.
type mrtServiceWindow struct {
	first, last int
}

// _mrtWindowGraceMin pads each service window: a train can legitimately appear on
// the live board a few minutes before the first departure and linger a few
// minutes after the station's last-train time.
const _mrtWindowGraceMin = 10

// _mrtWindowCacheTTL bounds how long the in-memory schedule windows are reused
// before re-reading mrt_schedule. The table only changes at the 03:30 daily
// load, so an hourly reload tracks it without a loader-side invalidation hook.
const _mrtWindowCacheTTL = time.Hour

var _mrtWindowCache struct {
	sync.Mutex
	loaded time.Time
	byKey  map[string][]mrtServiceWindow
}

func mrtWindowKey(system, stationID, lineID, destStationID string) string {
	return system + "|" + stationID + "|" + lineID + "|" + destStationID
}

// parseHHMM parses "HH:MM" into minutes since midnight; ok is false for any
// other shape (mrt_schedule stores times as text straight from TDX).
func parseHHMM(s string) (int, bool) {
	if len(s) != 5 || s[2] != ':' {
		return 0, false
	}
	allDigits := isASCIIDigit(s[0]) && isASCIIDigit(s[1]) && isASCIIDigit(s[3]) && isASCIIDigit(s[4])
	if !allDigits {
		return 0, false
	}
	// 24..29 are kept: TDX publishes past-midnight departures as hour 24+.
	h := int(s[0]-'0')*10 + int(s[1]-'0')
	m := int(s[3]-'0')*10 + int(s[4]-'0')
	if h > 29 || m > 59 {
		return 0, false
	}
	return h*60 + m, true
}

func isASCIIDigit(b byte) bool {
	return b >= '0' && b <= '9'
}

// mrtServiceWindows returns the schedule windows keyed by
// system|station|line|destination, reloading from mrt_schedule at most once per
// mrtWindowCacheTTL. Service-day masks are deliberately ignored: a row for any
// day widens the window, so filtering only ever drops entries outside every
// documented service window. Returns nil (callers fail open) on query error or
// nil db.
func mrtServiceWindows(ctx context.Context, db *pgxpool.Pool) map[string][]mrtServiceWindow {
	if db == nil {
		return nil
	}
	_mrtWindowCache.Lock()
	defer _mrtWindowCache.Unlock()
	if _mrtWindowCache.byKey != nil && time.Since(_mrtWindowCache.loaded) < _mrtWindowCacheTTL {
		return _mrtWindowCache.byKey
	}
	rows, err := db.Query(ctx, `SELECT system, station_id, lineid, destinationstaionid, firsttraintime, lasttraintime FROM mrt_schedule`)
	if err != nil {
		zap.S().Errorw("query error",
			"component", "mrt_eta",
			"action", "mrt_windows",
			"event", "query_error",
			"err", err,
		)
		return _mrtWindowCache.byKey // stale beats none; nil on first failure
	}
	defer rows.Close()
	byKey := map[string][]mrtServiceWindow{}
	for rows.Next() {
		var system, station, line, dest, ft, lt string
		if err := rows.Scan(&system, &station, &line, &dest, &ft, &lt); err != nil {
			continue
		}
		first, ok1 := parseHHMM(ft)
		last, ok2 := parseHHMM(lt)
		if !ok1 || !ok2 {
			continue
		}
		if last <= first {
			last += 24 * 60 // last train past midnight belongs to the same service day
		}
		k := mrtWindowKey(system, station, line, dest)
		byKey[k] = append(byKey[k], mrtServiceWindow{first: first, last: last})
	}
	if err := rows.Err(); err != nil {
		zap.S().Errorw("scan error",
			"component", "mrt_eta",
			"action", "mrt_windows",
			"event", "scan_error",
			"err", err,
		)
		return _mrtWindowCache.byKey
	}
	_mrtWindowCache.byKey = byKey
	_mrtWindowCache.loaded = time.Now()
	zap.S().Infow("reloaded",
		"component", "mrt_eta",
		"action", "mrt_windows",
		"event", "reloaded",
		"keys", len(byKey),
	)
	return byKey
}

// mrtInService reports whether a live-board entry falls inside any schedule
// window for its key (with grace padding). Entries with no schedule rows pass:
// TDX emits stale zero-estimate rows after close, so the filter only drops what
// the static timetable positively places outside service hours.
func mrtInService(windows map[string][]mrtServiceWindow, key string, now time.Time) bool {
	ws, ok := windows[key]
	if !ok || len(ws) == 0 {
		return true
	}
	minutes := now.Hour()*60 + now.Minute()
	for _, w := range ws {
		lo, hi := w.first-_mrtWindowGraceMin, w.last+_mrtWindowGraceMin
		// Check the same clock time on both the current and previous service
		// day, so 00:30 matches a 06:00–24:40 window via +24h.
		if (minutes >= lo && minutes <= hi) || (minutes+24*60 >= lo && minutes+24*60 <= hi) {
			return true
		}
	}
	return false
}

// mrtEta refreshes live metro arrivals into Redis on the 10s cron. Per system it
// pipelines a protobuf MrtLive per (station, line) under mrt_live:... with a
// 2-minute TTL and publishes per-station updates for live streaming. NTMC is
// excluded (no live board). Per-system failures are logged and skipped.
// Entries outside their static first/last-train window are dropped: after close
// TDX keeps returning rows with EstimateTime 0 and ServiceStatus 0, which would
// otherwise surface as "approaching" in the app at night.
//
//nolint:unused // ADR-0014: TDX metro LiveBoard is paused, not removed
func mrtEta(ctx context.Context, fetch boundFetch, sink liveSink, db *pgxpool.Pool) error {
	zap.S().Infow("start", "component", "mrt_eta", "action", "mrt_eta", "event", "start")
	windows := mrtServiceWindows(ctx, db)
	now := time.Now().In(_taipei)
	systems := []string{"TRTC", "KRTC", "KLRT", "TYMC"}
	var jobErr error
	for _, system := range systems {
		filtered := 0
		zap.S().Infow("system start",
			"component", "mrt_eta",
			"action", "mrt_eta",
			"system", system,
			"event", "system_start",
		)
		result, err := fetch(ctx, fmt.Sprintf("/v2/Rail/Metro/LiveBoard/%s", system), "mrt_LiveBoard"+system)
		if err != nil {
			jobErr = errors.Join(jobErr, _oops.With("system", system).Wrapf(err, "mrt fetch"))
			continue
		}
		if !result.Modified {
			// A 304 has already refreshed the cached arrivals' TTL via boundFetch.
			zap.S().Warnw("skip",
				"component", "mrt_eta",
				"action", "mrt_eta",
				"system", system,
				"event", "skip",
				"reason", "not_updated",
			)
			continue
		}
		if err := commitTDXFetch(result, func(dec *json.Decoder) error {
			pipe := sink.pipeline()
			ownedKeys := make([]string, 0)
			if err := decodeLiveItems(dec, func(temp mrtLive) error {
				if !mrtInService(windows, mrtWindowKey(system, temp.StationID, temp.LineID, temp.DestinationStaionID), now) {
					filtered++
					return nil
				}
				raw := &models.MrtLive{
					LineID:                 temp.LineID,
					StationID:              temp.StationID,
					System:                 system,
					TripHeadSign:           temp.TripHeadSign,
					DestinationStaionID:    temp.DestinationStaionID,
					DestinationStationName: temp.DestinationStationName.ZhTw,
					ServiceStatus:          int32(temp.ServiceStatus),
					EstimateTime:           temp.EstimateTime,
				}
				pb, err := proto.Marshal(raw)
				if err != nil {
					return err
				}
				key := shared.MrtLiveKey(system, temp.StationID, temp.LineID, temp.DestinationStaionID)
				pipe.Set(key, pb, _mrtLiveTTL)
				ownedKeys = append(ownedKeys, key)
				pipe.Publish(shared.MrtLiveChannel(system, temp.StationID), string(pb))
				return nil
			}); err != nil {
				return err
			}
			pipe.ReplaceOwnedKeys(shared.LiveOwnedKeysKey("mrt", system), ownedKeys, _ownedKeysTTL)
			if err := pipe.Exec(ctx); err != nil {
				return _oops.With("system", system).Wrapf(err, "publish MRT live board")
			}
			return nil
		}); err != nil {
			jobErr = errors.Join(jobErr, _oops.With("system", system).Wrapf(err, "mrt process"))
		}
		if filtered > 0 {
			zap.S().Infow("out of service filtered",
				"component", "mrt_eta",
				"action", "mrt_eta",
				"system", system,
				"event", "out_of_service_filtered",
				"count", filtered,
			)
		}
	}
	zap.S().Infow("complete", "component", "mrt_eta", "action", "mrt_eta", "event", "complete")
	return jobErr
}

// mrtODFare decodes a TDX Rail/Metro/ODFare element: fares between an
// origin/destination station pair, by ticket type. For KRTC/KLRT the same feed
// carries the station-to-station TravelTime (whole minutes), which populates
// mrt_journey_matrix.travel_time_min. TravelTime is json.Number because TDX has
// emitted it both as a bare number and as a quoted string across systems; a
// missing value yields 0 (left as-is by the upsert's conditional update), while
// malformed, fractional, or negative input aborts the load.
// TRTC's ODFare omits TravelTime entirely — its times are computed separately by
// loadMrtTrtcTravelTime from the segment + transfer graph.
//
// The two fare axes are independent: TicketType is the ticket medium (1 = single
// journey) and FareClass is the passenger category (1 = 全票, 2 = 半票). Both must
// be matched — filtering on TicketType alone spans several classes.
type mrtODFare struct {
	OriginStationID      string      `json:"OriginStationID"`
	DestinationStationID string      `json:"DestinationStationID"`
	TravelTime           json.Number `json:"TravelTime"`
	Fares                []struct {
		TicketType int `json:"TicketType"`
		FareClass  int `json:"FareClass"`
		Price      int `json:"Price"`
	} `json:"Fares"`
}

// TDX fare codes used by the metro ODFare feed.
const (
	_mrtTicketTypeSingle = 1 // 單程票
	_mrtFareClassFull    = 1 // 全票
	_mrtFareClassHalf    = 2 // 半票
)

// fares picks the single-journey full (全票) and half (半票) prices. A class the
// feed omits stays 0, which the upsert preserves rather than overwriting a known
// price with a zero.
func (f mrtODFare) fares() (full, half int) {
	for _, t := range f.Fares {
		if t.TicketType != _mrtTicketTypeSingle {
			continue
		}
		switch t.FareClass {
		case _mrtFareClassFull:
			full = t.Price
		case _mrtFareClassHalf:
			half = t.Price
		}
	}
	return full, half
}

// travelTimeMin parses an mrtODFare's optional whole-minute TravelTime. Missing
// values return zero; malformed, fractional, or negative values are errors.
func (f mrtODFare) travelTimeMin() (int, error) {
	value, err := nonNegativeJSONInteger(f.TravelTime, "TravelTime", true /* optional */, _maxPostgresInteger)
	if err != nil {
		return 0, err
	}
	return int(value), nil
}

// loadMrtJourneyMatrix upserts one metro system's OD fare matrix into
// mrt_journey_matrix from a decoder over the reconstructed raw_tdx array. It
// decodes []mrtODFare and writes the single-journey full (全票, TicketType 1
// FareClass 1) and half (半票, FareClass 2) fares plus the station-to-station
// travel time from the same ODFare feed. The inline upsert only replaces a fare
// or travel time with a positive value, so a feed that omits a fare class (or
// TravelTime, as TRTC's does) never zeroes a previously populated value.
func loadMrtJourneyMatrix(ctx context.Context, dec *json.Decoder, sink copyUpsertSink, system string) error {
	if strings.TrimSpace(system) == "" {
		return errors.New("mrt journey matrix: system is required")
	}
	fares, err := decodeLoadArray[mrtODFare](dec, "mrt journey matrix "+system, func(_ int, fare mrtODFare) error {
		if strings.TrimSpace(fare.OriginStationID) == "" {
			return errors.New("OriginStationID is required")
		}
		if strings.TrimSpace(fare.DestinationStationID) == "" {
			return errors.New("DestinationStationID is required")
		}
		if _, err := fare.travelTimeMin(); err != nil {
			return err
		}
		singleSeen := false
		classPrices := map[int]int{}
		for i, item := range fare.Fares {
			if item.TicketType <= 0 {
				return _oops.With("index", i).With("ticket_type", item.TicketType).Errorf("fares element TicketType must be positive")
			}
			if item.FareClass < 0 {
				return _oops.With("index", i).With("fare_class", item.FareClass).Errorf("fares element FareClass must be non-negative")
			}
			if item.Price < 0 {
				return _oops.With("index", i).With("price", item.Price).Errorf("fares element Price must be non-negative")
			}
			if item.TicketType == _mrtTicketTypeSingle {
				// Only the full and half classes are ever read (see fares), so
				// scope the divergence check to them: a conflicting duplicate
				// on any other class disputes a value this loader discards, and
				// rejecting the system's whole matrix over it bought nothing.
				// A real conflict on a price users see stays fatal.
				if item.FareClass == _mrtFareClassFull || item.FareClass == _mrtFareClassHalf {
					if prior, seen := classPrices[item.FareClass]; seen && prior != item.Price {
						return _oops.With("index", i).With("fare_class", item.FareClass).Errorf("fares element divergent duplicate TicketType 1 FareClass")
					}
					classPrices[item.FareClass] = item.Price
				}
				singleSeen = true
			}
		}
		if !singleSeen {
			return errors.New("fares must include TicketType 1")
		}
		return nil
	})
	if err != nil {
		return err
	}
	if len(fares) == 0 {
		return nil
	}
	rows := make([][]any, 0, len(fares))
	seen := make(map[string][]any, len(fares))
	for _, f := range fares {
		full, half := f.fares()
		travelTime, err := f.travelTimeMin()
		if err != nil {
			return _oops.With("system", system).Wrapf(err, "mrt journey matrix row build")
		}
		id := fmt.Sprintf("%s-%s-%s", system, f.OriginStationID, f.DestinationStationID)
		candidate := []any{id, f.OriginStationID, f.DestinationStationID, system, travelTime, full, half}
		key := system + "\x00" + f.OriginStationID + "\x00" + f.DestinationStationID
		if err := appendUniqueLoadRow(&rows, seen, key, "OD", candidate); err != nil {
			return _oops.With("system", system).Wrapf(err, "mrt journey matrix")
		}
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "mrt_journey_matrix",
		createSQL: `CREATE TEMP TABLE temp_mrt_journey_matrix (
			id text, from_station_id text, to_station_id text, system text,
			travel_time_min int, fare_nt int, half_fare_nt int
		) ON COMMIT DROP`,
		tempTable: "temp_mrt_journey_matrix",
		copyCols:  []string{"id", "from_station_id", "to_station_id", "system", "travel_time_min", "fare_nt", "half_fare_nt"},
		insertSQL: `INSERT INTO mrt_journey_matrix
			(id, from_station_id, to_station_id, system, travel_time_min, fare_nt, half_fare_nt, updated_at)
			SELECT id, from_station_id, to_station_id, system, travel_time_min, fare_nt, half_fare_nt, NOW()
			FROM temp_mrt_journey_matrix
			ON CONFLICT (from_station_id, to_station_id, system)
			DO UPDATE SET
				fare_nt = CASE WHEN EXCLUDED.fare_nt > 0
					THEN EXCLUDED.fare_nt ELSE mrt_journey_matrix.fare_nt END,
				half_fare_nt = CASE WHEN EXCLUDED.half_fare_nt > 0
					THEN EXCLUDED.half_fare_nt ELSE mrt_journey_matrix.half_fare_nt END,
				travel_time_min = CASE WHEN EXCLUDED.travel_time_min > 0
					THEN EXCLUDED.travel_time_min ELSE mrt_journey_matrix.travel_time_min END,
				updated_at = NOW()`,
	}, rows)
}

const _maxPostgresInteger int64 = 1<<31 - 1

func nonNegativeJSONInteger(number json.Number, field string, optional bool, maximum int64) (int64, error) {
	if number == "" {
		if optional {
			return 0, nil
		}
		return 0, _oops.With("field", field).Errorf("is required")
	}
	value, ok := new(big.Rat).SetString(number.String())
	if !ok || value.Sign() < 0 {
		return 0, _oops.With("field", field).With("number", number).Errorf("must be an exact non-negative number")
	}
	if !value.IsInt() {
		return 0, _oops.With("field", field).With("number", number).Errorf("must use whole units")
	}
	integer := value.Num()
	if !integer.IsInt64() || integer.Int64() > maximum {
		return 0, _oops.With("field", field).With("maximum", maximum).With("number", number).Errorf("must be between 0")
	}
	return integer.Int64(), nil
}

// mrtS2SRow decodes one TDX Rail/Metro/S2STravelTime element: a line and its
// ordered adjacent-station segments. The nested TravelTimes array lands as jsonb
// (the landing lowercases only top-level keys), so it is decoded here with
// case-insensitive struct tags. Only the segment endpoints and their RunTime +
// StopTime (seconds) are used to build the metro graph.
type mrtS2SRow struct {
	TravelTimes []struct {
		FromStationID string      `json:"FromStationID"`
		ToStationID   string      `json:"ToStationID"`
		RunTime       json.Number `json:"RunTime"`
		StopTime      json.Number `json:"StopTime"`
	} `json:"TravelTimes"`
}

// mrtLineTransfer decodes one TDX Rail/Metro/LineTransfer element: an interchange
// edge between two station IDs. TransferTime is whole minutes per the TDX schema.
type mrtLineTransfer struct {
	FromStationID string      `json:"FromStationID"`
	ToStationID   string      `json:"ToStationID"`
	TransferTime  json.Number `json:"TransferTime"`
}

// jsonNumInt parses a required whole-unit duration without silently converting
// malformed values to zero.
func jsonNumInt(n json.Number, field string) (int64, error) {
	value, err := nonNegativeJSONInteger(n, field, false /* optional */, _maxPostgresInteger)
	if err != nil {
		return 0, err
	}
	return value, nil
}

// loadMrtTrtcTravelTime computes TRTC OD travel times from the segment + transfer
// graph and writes them into mrt_journey_matrix.travel_time_min. TRTC's ODFare
// feed omits per-OD TravelTime (unlike KRTC/KLRT), so the ODFare load leaves
// those rows at 0; this runs after mrt_odfare (registry order) and fills them
// in. It reads both landed graph inputs via src (like loadBus's multi-table
// read), builds an undirected weighted graph (edge weight in seconds: adjacent
// hops = RunTime + StopTime, interchanges = TransferTime * 60), all-pairs
// shortest-paths it (Floyd-Warshall, ~130 nodes), and UPDATEs each reachable pair
// that already exists in the matrix. Unreachable/absent pairs keep their current
// value, so a missing feed never zeroes good data — it just no-ops.
func loadMrtTrtcTravelTime(ctx context.Context, src loadSource, sink copyUpsertSink, system string) error {
	if strings.TrimSpace(system) == "" {
		return errors.New("mrt travel time: system is required")
	}
	s2sBody, _, err := src.datasetJSON(ctx, "metro_s2straveltime", "system", system)
	if err != nil {
		return _oops.With("system", system).Wrapf(err, "mrt s2s read")
	}
	lines, err := decodeLoadArray[mrtS2SRow](json.NewDecoder(bytes.NewReader(s2sBody)), "mrt s2s "+system, func(_ int, line mrtS2SRow) error {
		for i, segment := range line.TravelTimes {
			if strings.TrimSpace(segment.FromStationID) == "" {
				return _oops.With("index", i).Errorf("TravelTimes element FromStationID is required")
			}
			if strings.TrimSpace(segment.ToStationID) == "" {
				return _oops.With("index", i).Errorf("TravelTimes element ToStationID is required")
			}
			runTime, err := nonNegativeJSONInteger(segment.RunTime, "RunTime", false /* optional */, _maxPostgresInteger)
			if err != nil {
				return _oops.With("index", i).Wrapf(err, "TravelTimes element")
			}
			if runTime == 0 {
				return _oops.With("index", i).Errorf("TravelTimes element: RunTime must be positive")
			}
			if _, err := nonNegativeJSONInteger(segment.StopTime, "StopTime", false /* optional */, _maxPostgresInteger); err != nil {
				return _oops.With("index", i).Wrapf(err, "TravelTimes element")
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	trBody, _, err := src.datasetJSON(ctx, "metro_linetransfer", "system", system)
	if err != nil {
		return _oops.With("system", system).Wrapf(err, "mrt linetransfer read")
	}
	transfers, err := decodeLoadArray[mrtLineTransfer](json.NewDecoder(bytes.NewReader(trBody)), "mrt line transfer "+system, func(_ int, transfer mrtLineTransfer) error {
		if strings.TrimSpace(transfer.FromStationID) == "" {
			return errors.New("FromStationID is required")
		}
		if strings.TrimSpace(transfer.ToStationID) == "" {
			return errors.New("ToStationID is required")
		}
		transferTime, err := nonNegativeJSONInteger(transfer.TransferTime, "TransferTime", false /* optional */, _maxPostgresInteger)
		if err != nil {
			return err
		}
		if transferTime == 0 {
			return errors.New("TransferTime must be positive")
		}
		return nil
	})
	if err != nil {
		return err
	}

	stations, dist, segCount, transferCount, err := mrtTravelGraph(lines, transfers)
	if err != nil {
		return _oops.With("system", system).Wrapf(err, "mrt travel graph")
	}
	if len(stations) == 0 || segCount == 0 {
		zap.S().Infow("no graph",
			"component", "mrt",
			"action", "trtc_traveltime",
			"system", system,
			"event", "no_graph",
			"segments", segCount,
			"transfers", transferCount,
		)
		return nil
	}

	// UPDATE only rows that already exist (created by mrt_odfare); a pair absent
	// from the matrix no-ops. Idx order is deterministic via the stations slice.
	rows := make([][]any, 0, len(stations)*len(stations))
	for i, from := range stations {
		for j, to := range stations {
			if i == j {
				continue
			}
			d := dist[i][j]
			if d <= 0 || d >= _mrtGraphInf {
				continue
			}
			mins := max((d+30)/60, 1) // round to nearest minute, floor 1
			if mins > _maxPostgresInteger {
				return _oops.With("system", system).With("from", from).With("to", to).Errorf("mrt travel time to exceeds PostgreSQL integer maximum")
			}
			rows = append(rows, []any{mins, from, to, system})
		}
	}
	if len(rows) == 0 {
		return nil
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "mrt_traveltime",
		createSQL: `CREATE TEMP TABLE temp_mrt_travel_time (
			travel_time_min int, from_station_id text, to_station_id text, system text
		) ON COMMIT DROP`,
		tempTable: "temp_mrt_travel_time",
		copyCols:  []string{"travel_time_min", "from_station_id", "to_station_id", "system"},
		insertSQL: `UPDATE mrt_journey_matrix AS matrix
			SET travel_time_min = fresh.travel_time_min, updated_at = NOW()
			FROM temp_mrt_travel_time AS fresh
			WHERE matrix.from_station_id = fresh.from_station_id
			  AND matrix.to_station_id = fresh.to_station_id
			  AND matrix.system = fresh.system`,
	}, rows)
}

// mrtAdjacencyRow decodes one S2STravelTime element for the adjacency graph: the
// line and its ordered adjacent-station segments. Only the line and the segment
// endpoints matter here (times are loadMrtTrtcTravelTime's concern), and the
// nested TravelTimes array — jsonb in raw_tdx — decodes with case-insensitive
// struct tags. LineID is the element's top-level lineid.
type mrtAdjacencyRow struct {
	LineID      string `json:"LineID"`
	TravelTimes []struct {
		FromStationID string `json:"FromStationID"`
		ToStationID   string `json:"ToStationID"`
	} `json:"TravelTimes"`
}

// loadMrtAdjacency fills mrt_adjacency from a system's S2STravelTime segments
// (ADR-0015): the same-line ride graph a metro alight-reminder session walks. It
// stores both directions of every segment so the router's board→terminal BFS is
// an undirected walk via directed-edge lookups. Interchange (LineTransfer) edges
// are intentionally excluded — one train never crosses them, so joining two
// lines into one component would let BFS route through a transfer a rider must
// physically make. Rows are refreshed in place via an upsert; a system whose
// feed is momentarily empty no-ops rather than deleting good edges.
func loadMrtAdjacency(ctx context.Context, dec *json.Decoder, sink loadSink, system string) error {
	if strings.TrimSpace(system) == "" {
		return errors.New("mrt adjacency: system is required")
	}
	lines, err := decodeLoadArray[mrtAdjacencyRow](dec, "mrt adjacency "+system, func(_ int, line mrtAdjacencyRow) error {
		if strings.TrimSpace(line.LineID) == "" {
			return errors.New("LineID is required")
		}
		for i, seg := range line.TravelTimes {
			if strings.TrimSpace(seg.FromStationID) == "" {
				return _oops.With("index", i).Errorf("TravelTimes element FromStationID is required")
			}
			if strings.TrimSpace(seg.ToStationID) == "" {
				return _oops.With("index", i).Errorf("TravelTimes element ToStationID is required")
			}
		}
		return nil
	})
	if err != nil {
		return err
	}
	rows := mrtAdjacencyRows(lines, system)
	if len(rows) == 0 {
		zap.S().Infow("no edges",
			"component", "mrt",
			"action", "mrt_adjacency",
			"system", system,
			"event", "no_edges",
		)
		return nil
	}
	return sink.copyUpsert(ctx, copyUpsertSpec{
		key: "mrt_adjacency",
		createSQL: `CREATE TEMP TABLE temp_mrt_adjacency (
			system text, line_id text, from_station_id text, to_station_id text
		) ON COMMIT DROP`,
		tempTable: "temp_mrt_adjacency",
		copyCols:  []string{"system", "line_id", "from_station_id", "to_station_id"},
		insertSQL: `INSERT INTO mrt_adjacency (system, line_id, from_station_id, to_station_id, updated_at)
			SELECT system, line_id, from_station_id, to_station_id, NOW() FROM temp_mrt_adjacency
			ON CONFLICT (system, from_station_id, to_station_id)
			DO UPDATE SET line_id = EXCLUDED.line_id, updated_at = NOW()`,
	}, rows)
}

// mrtAdjacencyRows flattens the decoded lines into both-direction edge rows,
// keeping the first line seen for a (from, to) pair so the copy set has no
// duplicate primary key. Split from loadMrtAdjacency so the flattening is
// unit-testable without a database.
func mrtAdjacencyRows(lines []mrtAdjacencyRow, system string) [][]any {
	seen := map[string]bool{}
	var rows [][]any
	add := func(lineID, from, to string) {
		key := from + "\x00" + to
		if seen[key] {
			return
		}
		seen[key] = true
		rows = append(rows, []any{system, lineID, from, to})
	}
	for _, line := range lines {
		for _, seg := range line.TravelTimes {
			if seg.FromStationID == "" || seg.ToStationID == "" {
				continue
			}
			add(line.LineID, seg.FromStationID, seg.ToStationID)
			add(line.LineID, seg.ToStationID, seg.FromStationID)
		}
	}
	return rows
}

const _mrtGraphInf int64 = 1 << 62

// mrtTravelGraph builds the undirected shortest-path distance matrix (seconds)
// over every station appearing in a segment or transfer. Returns the station-id
// slice (index i ↔ dist row i), the all-pairs distance matrix, and the segment /
// transfer edge counts for logging. Split out from loadMrtTrtcTravelTime so the
// graph math is unit-testable without a database.
func mrtTravelGraph(lines []mrtS2SRow, transfers []mrtLineTransfer) ([]string, [][]int64, int, int, error) {
	stations := []string{}
	idx := map[string]int{}
	id := func(s string) int {
		if i, ok := idx[s]; ok {
			return i
		}
		i := len(stations)
		idx[s] = i
		stations = append(stations, s)
		return i
	}
	type edge struct {
		a, b int
		w    int64
	}
	var edges []edge
	segCount, transferCount := 0, 0
	for _, ln := range lines {
		for _, s := range ln.TravelTimes {
			if s.FromStationID == "" || s.ToStationID == "" {
				continue
			}
			runTime, err := jsonNumInt(s.RunTime, "RunTime")
			if err != nil {
				return nil, nil, 0, 0, err
			}
			stopTime, err := jsonNumInt(s.StopTime, "StopTime")
			if err != nil {
				return nil, nil, 0, 0, err
			}
			edges = append(edges, edge{id(s.FromStationID), id(s.ToStationID), runTime + stopTime})
			segCount++
		}
	}
	for _, t := range transfers {
		if t.FromStationID == "" || t.ToStationID == "" {
			continue
		}
		transferTime, err := jsonNumInt(t.TransferTime, "TransferTime")
		if err != nil {
			return nil, nil, 0, 0, err
		}
		edges = append(edges, edge{id(t.FromStationID), id(t.ToStationID), transferTime * 60})
		transferCount++
	}
	n := len(stations)
	dist := make([][]int64, n)
	for i := range dist {
		dist[i] = make([]int64, n)
		for j := range dist[i] {
			if i != j {
				dist[i][j] = _mrtGraphInf
			}
		}
	}
	for _, e := range edges {
		if e.w < dist[e.a][e.b] {
			dist[e.a][e.b] = e.w
			dist[e.b][e.a] = e.w
		}
	}
	for k := range n {
		for i := range n {
			if dist[i][k] >= _mrtGraphInf {
				continue
			}
			for j := range n {
				if dist[k][j] >= _mrtGraphInf || dist[i][k] > _mrtGraphInf-dist[k][j] {
					continue
				}
				if d := dist[i][k] + dist[k][j]; d < dist[i][j] {
					dist[i][j] = d
				}
			}
		}
	}
	return stations, dist, segCount, transferCount, nil
}
