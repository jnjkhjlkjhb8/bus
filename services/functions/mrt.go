package main

import (
	"context"
	"encoding/json"
	"sync"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_car/models"

	"fmt"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/protobuf/proto"
)

// mrtStation decodes a TDX Rail/Metro/Station element used for the metro static
// station table. serviceType is unexported and not populated from JSON.
type mrtStation struct {
	StationPosition struct {
		PositionLon float64 `json:"PositionLon"`
		PositionLat float64 `json:"PositionLat"`
	} `json:"StationPosition"`
	LocationCity       string `json:"LocationCity"`
	serviceType        string
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
	city                   string
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
	if _, err := dec.Token(); err != nil {
		log.Infof("[MRT] action=getmrt_station system=%s event=decode_error error=%v", system, err)
		return err
	}
	row := [][]any{}
	for dec.More() {
		var temp mrtStation
		if err := dec.Decode(&temp); err == nil {
			g := fmt.Sprintf("POINT(%.6f %.6f)", temp.StationPosition.PositionLon, temp.StationPosition.PositionLat)
			row = append(row, []any{
				g,
				system,
				temp.StationName.ZhTw,
				temp.LocationCity,
				temp.StationID,
				temp.BikeAllowOnHoliday,
			})
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
				ON CONFLICT (station_id,system) DO UPDATE SET name = EXCLUDED.name,city = excluded.city,stationposition = EXCLUDED.stationposition,updated_at = NOW();`,
	}, row)
}

// loadMrtFirstlast rebuilds mrt_schedule (first/last train times) for one metro
// system as partition-replace: within ONE transaction it DELETEs the system's
// rows, COPYs the fresh rows into temp_mrt, then plain-INSERTs them with no
// DISTINCT ON and no ON CONFLICT. The natural key (station_id, lineid,
// destinationstaionid, serviceday, system) is not unique in real data, so every
// raw row must survive rather than be collapsed. It consumes an already-opened
// decoder. updated_at is stamped NOW() so the freshness probe (main.go's
// MAX(updated_at) per system) keeps working.
func loadMrtFirstlast(ctx context.Context, dec *json.Decoder, sink loadSink, system string) error {
	if _, err := dec.Token(); err != nil {
		log.Infof("[MRT] action=getmrt_firstlast system=%s event=decode_error error=%v", system, err)
		return err
	}
	row := [][]any{}
	for dec.More() {
		var temp mrtFirstlast
		if err := dec.Decode(&temp); err == nil {
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
	}
	if len(row) == 0 {
		return nil
	}
	// Partition-replace: DELETE this system's rows before re-inserting, and the
	// drain is a plain INSERT (no ON CONFLICT) because the natural key is not
	// unique in real data so every raw row must survive.
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
					SELECT id,lid, dsid, dsname, ft, lt,mask,sys,NOW(),NOW(),sign FROM temp_mrt`,
	}, row)
}

// mrtServiceWindow is one first/last-train window from mrt_schedule, in minutes
// since midnight; last exceeds 1440 when the last train runs past midnight.
type mrtServiceWindow struct {
	first, last int
}

// mrtWindowGraceMin pads each service window: a train can legitimately appear on
// the live board a few minutes before the first departure and linger a few
// minutes after the station's last-train time.
const mrtWindowGraceMin = 10

// mrtWindowCacheTTL bounds how long the in-memory schedule windows are reused
// before re-reading mrt_schedule. The table only changes at the 03:30 daily
// load, so an hourly reload tracks it without a loader-side invalidation hook.
const mrtWindowCacheTTL = time.Hour

var mrtWindowCache struct {
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
	h := int(s[0]-'0')*10 + int(s[1]-'0')
	m := int(s[3]-'0')*10 + int(s[4]-'0')
	if s[0] < '0' || s[0] > '9' || s[1] < '0' || s[1] > '9' ||
		s[3] < '0' || s[3] > '9' || s[4] < '0' || s[4] > '9' ||
		h > 29 || m > 59 {
		return 0, false
	}
	return h*60 + m, true
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
	mrtWindowCache.Lock()
	defer mrtWindowCache.Unlock()
	if mrtWindowCache.byKey != nil && time.Since(mrtWindowCache.loaded) < mrtWindowCacheTTL {
		return mrtWindowCache.byKey
	}
	rows, err := db.Query(ctx, `SELECT system, station_id, lineid, destinationstaionid, firsttraintime, lasttraintime FROM mrt_schedule`)
	if err != nil {
		log.Infof("[MRT_ETA] action=mrt_windows event=query_error error=%v", err)
		return mrtWindowCache.byKey // stale beats none; nil on first failure
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
		log.Infof("[MRT_ETA] action=mrt_windows event=scan_error error=%v", err)
		return mrtWindowCache.byKey
	}
	mrtWindowCache.byKey = byKey
	mrtWindowCache.loaded = time.Now()
	log.Infof("[MRT_ETA] action=mrt_windows event=reloaded keys=%d", len(byKey))
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
		lo, hi := w.first-mrtWindowGraceMin, w.last+mrtWindowGraceMin
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
func mrtEta(ctx context.Context, fetch boundFetch, sink liveSink, db *pgxpool.Pool) {
	log.Infof("[MRT_ETA] action=mrt_eta event=start")
	windows := mrtServiceWindows(ctx, db)
	now := time.Now().In(taipei)
	var systems = []string{"TRTC", "KRTC", "KLRT", "TYMC"}
	for _, system := range systems {
		filtered := 0
		log.Infof("[MRT_ETA] action=mrt_eta system=%s event=system_start", system)
		dec, comp, flipopen, err := fetch(ctx, fmt.Sprintf("/v2/Rail/Metro/LiveBoard/%s", system), "mrt_LiveBoard"+system)
		if !comp {
			// A 304 has already refreshed the cached arrivals' TTL via boundFetch.
			log.Infof("[MRT_ETA] action=mrt_eta system=%s event=skip reason=no updated", system)
			continue
		}
		if err != nil {
			log.Infof("[MRT_ETA] action=mrt_eta system=%s event=skip reason=api_error", system)
			continue
		}
		func() {
			defer flipopen()
			pipe := sink.pipeline()
			if err := publishProto(dec, pipe, mrtLiveTTL, func(temp mrtLive) (string, string, proto.Message, bool) {
				if !mrtInService(windows, mrtWindowKey(system, temp.StationID, temp.LineID, temp.DestinationStaionID), now) {
					filtered++
					return "", "", nil, false
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
				return shared.MrtLiveKey(system, temp.StationID, temp.LineID),
					shared.MrtLiveChannel(system, temp.StationID), raw, true
			}); err != nil {
				log.Infof("[MRT_ETA] action=mrt_eta system=%s event=decode_error error=%v", system, err)
				return
			}
			_ = pipe.Exec()
		}()
		if filtered > 0 {
			log.Infof("[MRT_ETA] action=mrt_eta system=%s event=out_of_service_filtered count=%d", system, filtered)
		}
	}
	log.Infof("[MRT_ETA] action=mrt_eta event=complete")
}

// mrtODFare decodes a TDX Rail/Metro/ODFare element: fares between an
// origin/destination station pair, by ticket type. For KRTC/KLRT the same feed
// carries the station-to-station TravelTime (whole minutes), which populates
// mrt_journey_matrix.travel_time_min. TravelTime is json.Number because TDX has
// emitted it both as a bare number and as a quoted string across systems; a
// missing or unparseable value yields 0 (left as-is by the upsert's COALESCE).
// TRTC's ODFare omits TravelTime entirely — its times are computed separately by
// loadMrtTrtcTravelTime from the segment + transfer graph.
type mrtODFare struct {
	OriginStationID      string      `json:"OriginStationID"`
	DestinationStationID string      `json:"DestinationStationID"`
	TravelTime           json.Number `json:"TravelTime"`
	Fares                []struct {
		TicketType int `json:"TicketType"`
		Price      int `json:"Price"`
	} `json:"Fares"`
}

// travelTimeMin parses an mrtODFare's TravelTime into whole minutes, returning 0
// when absent or unparseable.
func (f mrtODFare) travelTimeMin() int {
	if f.TravelTime == "" {
		return 0
	}
	if v, err := f.TravelTime.Float64(); err == nil && v > 0 {
		return int(v)
	}
	return 0
}

// mrtJourneyMatrixUpsert is the shared ON CONFLICT upsert for the metro journey
// matrix. fare_nt always tracks the latest ODFare; travel_time_min is only
// overwritten when the incoming value is positive, so a fare-only refresh (or a
// system whose feed omits TravelTime) never zeroes a previously populated time.
const mrtJourneyMatrixUpsert = `
	INSERT INTO mrt_journey_matrix
		(id, from_station_id, to_station_id, system, travel_time_min, fare_nt, updated_at)
	VALUES ($1,$2,$3,$4,$5,$6,NOW())
	ON CONFLICT (from_station_id, to_station_id, system)
	DO UPDATE SET
		fare_nt = EXCLUDED.fare_nt,
		travel_time_min = CASE
			WHEN EXCLUDED.travel_time_min > 0 THEN EXCLUDED.travel_time_min
			ELSE mrt_journey_matrix.travel_time_min
		END,
		updated_at = NOW()`

// loadMrtJourneyMatrix upserts one metro system's OD fare matrix into
// mrt_journey_matrix from a decoder over the reconstructed raw_tdx array. It
// decodes []mrtODFare and applies mrtJourneyMatrixUpsert, which writes both the
// adult fare (TicketType 1) and the station-to-station travel time from the
// same ODFare feed. This is the sole writer of mrt_journey_matrix (loader
// registry key "mrt_odfare").
func loadMrtJourneyMatrix(ctx context.Context, dec *json.Decoder, db *pgxpool.Pool, _ *redis.Client, system string) error {
	var fares []mrtODFare
	if err := dec.Decode(&fares); err != nil {
		log.Infof("[MRT] action=mrt_journey_matrix system=%s event=decode_error error=%v", system, err)
		return err
	}
	batch := &pgx.Batch{}
	for _, f := range fares {
		adultPrice := 0
		for _, t := range f.Fares {
			if t.TicketType == 1 {
				adultPrice = t.Price
			}
		}
		id := fmt.Sprintf("%s-%s-%s", system, f.OriginStationID, f.DestinationStationID)
		batch.Queue(mrtJourneyMatrixUpsert,
			id, f.OriginStationID, f.DestinationStationID, system, f.travelTimeMin(), adultPrice,
		)
	}
	br := db.SendBatch(ctx, batch)
	if err := br.Close(); err != nil {
		return fmt.Errorf("mrt journey matrix batch %s: %w", system, err)
	}
	log.Infof("[MRT] journey matrix upserted %d rows for %s", len(fares), system)
	return nil
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

// jsonNumInt parses a json.Number into a non-negative int, returning 0 when
// absent or unparseable (the TDX times are whole non-negative values).
func jsonNumInt(n json.Number) int {
	if n == "" {
		return 0
	}
	if v, err := n.Float64(); err == nil && v > 0 {
		return int(v)
	}
	return 0
}

// loadMrtTrtcTravelTime computes TRTC OD travel times from the segment + transfer
// graph and writes them into mrt_journey_matrix.travel_time_min. TRTC's ODFare
// feed omits per-OD TravelTime (unlike KRTC/KLRT), so mrtJourneyMatrixUpsert
// leaves those rows at 0; this runs after mrt_odfare (registry order) and fills
// them in. It reads both landed graph inputs via src (like loadBus's multi-table
// read), builds an undirected weighted graph (edge weight in seconds: adjacent
// hops = RunTime + StopTime, interchanges = TransferTime * 60), all-pairs
// shortest-paths it (Floyd-Warshall, ~130 nodes), and UPDATEs each reachable pair
// that already exists in the matrix. Unreachable/absent pairs keep their current
// value, so a missing feed never zeroes good data — it just no-ops.
func loadMrtTrtcTravelTime(ctx context.Context, src loadSource, db *pgxpool.Pool, system string) error {
	s2sBody, _, err := src.datasetJSON(ctx, "metro_s2straveltime", "system", system)
	if err != nil {
		return fmt.Errorf("mrt s2s read %s: %w", system, err)
	}
	var lines []mrtS2SRow
	if err := json.Unmarshal(s2sBody, &lines); err != nil {
		return fmt.Errorf("mrt s2s decode %s: %w", system, err)
	}
	trBody, _, err := src.datasetJSON(ctx, "metro_linetransfer", "system", system)
	if err != nil {
		return fmt.Errorf("mrt linetransfer read %s: %w", system, err)
	}
	var transfers []mrtLineTransfer
	if err := json.Unmarshal(trBody, &transfers); err != nil {
		return fmt.Errorf("mrt linetransfer decode %s: %w", system, err)
	}

	stations, dist, segCount, transferCount := mrtTravelGraph(lines, transfers)
	if len(stations) == 0 || segCount == 0 {
		log.Infof("[MRT] action=trtc_traveltime system=%s event=no_graph segments=%d transfers=%d", system, segCount, transferCount)
		return nil
	}

	// UPDATE only rows that already exist (created by mrt_odfare); a pair absent
	// from the matrix no-ops. Idx order is deterministic via the stations slice.
	const upd = `UPDATE mrt_journey_matrix SET travel_time_min=$1, updated_at=NOW()
		WHERE from_station_id=$2 AND to_station_id=$3 AND system=$4`
	batch := &pgx.Batch{}
	computed := 0
	for i, from := range stations {
		for j, to := range stations {
			if i == j {
				continue
			}
			d := dist[i][j]
			if d <= 0 || d >= mrtGraphInf {
				continue
			}
			mins := max((d+30)/60, 1) // round to nearest minute, floor 1
			batch.Queue(upd, mins, from, to, system)
			computed++
		}
	}
	br := db.SendBatch(ctx, batch)
	if err := br.Close(); err != nil {
		return fmt.Errorf("mrt trtc traveltime batch %s: %w", system, err)
	}
	log.Infof("[MRT] action=trtc_traveltime system=%s event=complete stations=%d segments=%d transfers=%d pairs_computed=%d",
		system, len(stations), segCount, transferCount, computed)
	return nil
}

const mrtGraphInf = 1 << 30

// mrtTravelGraph builds the undirected shortest-path distance matrix (seconds)
// over every station appearing in a segment or transfer. Returns the station-id
// slice (index i ↔ dist row i), the all-pairs distance matrix, and the segment /
// transfer edge counts for logging. Split out from loadMrtTrtcTravelTime so the
// graph math is unit-testable without a database.
func mrtTravelGraph(lines []mrtS2SRow, transfers []mrtLineTransfer) ([]string, [][]int, int, int) {
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
	type edge struct{ a, b, w int }
	var edges []edge
	segCount, transferCount := 0, 0
	for _, ln := range lines {
		for _, s := range ln.TravelTimes {
			if s.FromStationID == "" || s.ToStationID == "" {
				continue
			}
			edges = append(edges, edge{id(s.FromStationID), id(s.ToStationID), jsonNumInt(s.RunTime) + jsonNumInt(s.StopTime)})
			segCount++
		}
	}
	for _, t := range transfers {
		if t.FromStationID == "" || t.ToStationID == "" {
			continue
		}
		edges = append(edges, edge{id(t.FromStationID), id(t.ToStationID), jsonNumInt(t.TransferTime) * 60})
		transferCount++
	}
	n := len(stations)
	dist := make([][]int, n)
	for i := range dist {
		dist[i] = make([]int, n)
		for j := range dist[i] {
			if i != j {
				dist[i][j] = mrtGraphInf
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
			if dist[i][k] >= mrtGraphInf {
				continue
			}
			for j := range n {
				if d := dist[i][k] + dist[k][j]; d < dist[i][j] {
					dist[i][j] = d
				}
			}
		}
	}
	return stations, dist, segCount, transferCount
}
