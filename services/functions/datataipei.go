package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/go-resty/resty/v2"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"go.uber.org/zap"
)

// Data.taipei (大臺北公車) is the upstream TDX relays Taipei and New Taipei bus
// data from. Each city is its own blob container (dataTaipeiDynamicCities)
// with independent Route/Stop numbering — New Taipei's is not a partition of
// Taipei's — verified against TDX's own UIDs by scripts/probe-datataipei-ids.py.
// It publishes several things TDX drops or only gives at route level: the
// plate number and the 附屬路線 id of every reporting vehicle (GetBusData),
// which stop that vehicle is standing at (GetBusEvent), and its seat crowding
// (BusSeatEvent) — FDPL-66 Phase 1/2. Those three only ever overlay the TDX
// positions bus_eta.go already fetched (overlayVehicles).
//
// GetEstimateTime is different: it is the same route-level granularity TDX
// itself gives for these two cities (buildBusEtaMap's comment on
// SubRouteUID), so there is no detail lost by using it instead — runCity
// skips the TDX ETA call entirely for a city dataTaipeiDynamicCities lists,
// rather than overlaying its result (FDPL-66 Phase 4).
//
// There is no SLA behind these blobs. A vehicle-feed failure returns the TDX
// positions untouched, so a stalled or unreachable feed degrades to exactly
// the behavior that shipped before this file existed. An ETA-feed failure
// fails that city's tick outright: there is no TDX ETA fetched for it to fall
// back to.

const dataTaipeiBlobBase = "https://tcgbusfs.blob.core.windows.net/blobbus/"
const dataTaipeiNTPCBusBase = "https://tcgbusfs.blob.core.windows.net/ntpcbus/"

// dataTaipeiCity is the only city GetSpecTimeTable — the daily timetable feed
// landed in datataipei_static.go — can join to; New Taipei's blob does not
// publish that endpoint at all. The live feeds in this file are broader and
// use dataTaipeiDynamicCities instead.
const dataTaipeiCity = "Taipei"

// dataTaipeiUIDPrefix turns a bare Data.taipei number into a Taipei TDX UID,
// used by the Taipei-only daily timetable landing (datataipei_static.go). The
// live feeds in this file carry their own per-city prefix instead
// (dataTaipeiDynamicCities).
const dataTaipeiUIDPrefix = "TPE"

// dataTaipeiDynamicCities are the cities Data.taipei publishes live vehicle
// position, stop events, seat crowding, and estimated arrivals for. Verified
// by scripts/probe-datataipei-ids.py (2026-08-07): every RouteID the live
// GetEstimateTime feed publishes resolves to a bus_static.route_uid under the
// listed prefix for both cities (100%), and 96-98% of StopID to a
// bus_station_stop_map.stop_uid.
var dataTaipeiDynamicCities = map[string]struct {
	base   string
	prefix string
}{
	"Taipei":    {base: dataTaipeiBlobBase, prefix: dataTaipeiUIDPrefix},
	"NewTaipei": {base: dataTaipeiNTPCBusBase, prefix: "NWT"},
}

const dataTaipeiTimeout = 10 * time.Second

// dataTaipeiBus is one GetBusData element: a vehicle's current position.
// Every numeric is delivered as a string, including the coordinates.
type dataTaipeiBus struct {
	BusID      string `json:"BusID"`   // 車牌號碼
	RouteID    string `json:"RouteID"` // 附屬路線 id
	GoBack     string `json:"GoBack"`
	Longitude  string `json:"Longitude"`
	Latitude   string `json:"Latitude"`
	Speed      string `json:"Speed"`
	Azimuth    string `json:"Azimuth"`
	DutyStatus string `json:"DutyStatus"`
	BusStatus  string `json:"BusStatus"`
	DataTime   string `json:"DataTime"`
}

// dataTaipeiEvent is one GetBusEvent element: a vehicle entering or leaving a
// stop. CarOnStop is "1" while the vehicle is at the stop and "0" once it has
// pulled out, so only the former places a bus anywhere.
type dataTaipeiEvent struct {
	BusID     string `json:"BusID"`
	StopID    string `json:"StopID"`
	CarOnStop string `json:"CarOnStop"`
}

// dataTaipeiSeat is one BusSeatEvent element: how full a vehicle is. Level is
// the operator's own 0/1/2 banding; RemainingNum (車上人數) is deliberately not
// carried through, because a passenger count is a number riders read as precise
// and the feed gives no basis for that.
//
// Level is a *int rather than an int: 33 of 1,541 vehicles publish null, and a
// missing reading has to stay missing instead of decoding to 0 (舒適).
type dataTaipeiSeat struct {
	BusID string `json:"BusID"`
	Level *int   `json:"Level"`
}

// dataTaipeiFeed holds one conditional-GET session against one city's blobs.
// The blobs answer with an ETag and rewrite roughly every 20 seconds, so the
// last decoded payload is kept per endpoint: a 304 on one of them must not
// discard another's rows, since the position, event, seat, and estimate feeds
// do not all turn over on the same tick.
type dataTaipeiFeed struct {
	client *resty.Client
	prefix string

	mu           sync.Mutex
	etag         map[string]string
	buses        []dataTaipeiBus
	events       []dataTaipeiEvent
	seats        []dataTaipeiSeat
	estimateRows []dataTaipeiEstimate
}

// dataTaipeiClients are shared across ticks for connection reuse, the same
// shape trtcClient has, one per dataTaipeiDynamicCities entry; per-tick
// deadlines come from the live runner's context.
var dataTaipeiClients = func() map[string]*resty.Client {
	clients := make(map[string]*resty.Client, len(dataTaipeiDynamicCities))
	for city, cfg := range dataTaipeiDynamicCities {
		clients[city] = resty.New().SetBaseURL(cfg.base).SetTimeout(dataTaipeiTimeout)
	}
	return clients
}()

var _ vehicleSource = (*dataTaipeiFeed)(nil)
var _ etaSource = (*dataTaipeiFeed)(nil)

// newDataTaipeiFeed builds a feed scoped to one dataTaipeiDynamicCities entry.
// Callers only ever pass a listed city (busEta, ingestor.go's daily timetable
// landing), so an unlisted one is not defended against here.
func newDataTaipeiFeed(city string) *dataTaipeiFeed {
	cfg := dataTaipeiDynamicCities[city]
	return &dataTaipeiFeed{
		client: dataTaipeiClients[city],
		prefix: cfg.prefix,
		etag:   make(map[string]string, 4),
	}
}

// getEnvelope fetches one blob, decoding the whole document into out only when
// the body changed. It reports whether anything was decoded, so the caller can
// keep its last copy.
func (f *dataTaipeiFeed) getEnvelope(ctx context.Context, name string, out any) (bool, error) {
	f.mu.Lock()
	prior := f.etag[name]
	f.mu.Unlock()
	req := f.client.R().SetContext(ctx)
	if prior != "" {
		req.SetHeader("If-None-Match", prior)
	}
	resp, err := req.Get(name + ".gz")
	if err != nil {
		return false, err
	}
	if resp.StatusCode() == http.StatusNotModified {
		return false, nil
	}
	if resp.StatusCode() != http.StatusOK {
		return false, fmt.Errorf("%s: HTTP %d", name, resp.StatusCode())
	}
	body, err := gunzipIfCompressed(resp.Body())
	if err != nil {
		return false, fmt.Errorf("%s: %w", name, err)
	}
	if err := json.Unmarshal(body, out); err != nil {
		return false, fmt.Errorf("%s: %w", name, err)
	}
	f.mu.Lock()
	f.etag[name] = resp.Header().Get("ETag")
	f.mu.Unlock()
	return true, nil
}

// getRows fetches one of the blobs that wrap their rows in
// {"EssentialInfo": …, "BusInfo": [...]} and decodes the rows alone. The
// timetable blobs use their own envelope and go through getEnvelope instead.
func (f *dataTaipeiFeed) getRows(ctx context.Context, name string, out any) (bool, error) {
	var envelope struct {
		BusInfo json.RawMessage `json:"BusInfo"`
	}
	modified, err := f.getEnvelope(ctx, name, &envelope)
	if err != nil || !modified {
		return false, err
	}
	if err := json.Unmarshal(envelope.BusInfo, out); err != nil {
		return false, fmt.Errorf("%s: %w", name, err)
	}
	return true, nil
}

// gunzipIfCompressed decompresses body when it is gzip, and returns it
// unchanged when it is not. The blobs are stored gzipped and normally arrive
// that way, but Go's transport transparently decompresses any response it
// negotiated Content-Encoding for, so which of the two we hold depends on
// details outside this function. The magic number settles it either way.
func gunzipIfCompressed(body []byte) ([]byte, error) {
	if len(body) < 2 || body[0] != 0x1f || body[1] != 0x8b {
		return body, nil
	}
	zr, err := gzip.NewReader(bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	defer func() { _ = zr.Close() }()
	return io.ReadAll(zr)
}

// positions fetches both blobs and returns them as TDX-shaped position rows.
func (f *dataTaipeiFeed) positions(ctx context.Context) ([]rawBusPosition, error) {
	var buses []dataTaipeiBus
	freshBuses, busErr := f.getRows(ctx, "GetBusData", &buses)
	var events []dataTaipeiEvent
	freshEvents, eventErr := f.getRows(ctx, "GetBusEvent", &events)
	var seats []dataTaipeiSeat
	freshSeats, seatErr := f.getRows(ctx, "BusSeatEvent", &seats)
	if err := errors.Join(busErr, eventErr, seatErr); err != nil {
		return nil, err
	}
	f.mu.Lock()
	if freshBuses {
		f.buses = buses
	}
	if freshEvents {
		f.events = events
	}
	if freshSeats {
		f.seats = seats
	}
	buses, events, seats = f.buses, f.events, f.seats
	f.mu.Unlock()
	return dataTaipeiRawPositions(f.prefix, buses, events, seats), nil
}

// dataTaipeiRawPositions converts the feed onto the TDX position shape the ETA
// job already consumes. Rows that cannot be placed on a route — an unknown
// direction ("2"), an unparseable coordinate — are dropped rather than passed
// on as a bus at (0, 0).
func dataTaipeiRawPositions(prefix string, buses []dataTaipeiBus, events []dataTaipeiEvent, seats []dataTaipeiSeat) []rawBusPosition {
	atStop := make(map[string]string, len(events))
	for _, e := range events {
		if e.CarOnStop == "1" && e.StopID != "" {
			atStop[e.BusID] = prefix + e.StopID
		}
	}
	crowd := make(map[string]models.BusCrowdLevel, len(seats))
	for _, s := range seats {
		if level, ok := dataTaipeiCrowdLevel(s.Level); ok {
			crowd[s.BusID] = level
		}
	}
	out := make([]rawBusPosition, 0, len(buses))
	for _, b := range buses {
		direction, ok := dataTaipeiDirection(b.GoBack)
		if !ok || b.RouteID == "" {
			continue
		}
		lon, lonErr := strconv.ParseFloat(b.Longitude, 64)
		lat, latErr := strconv.ParseFloat(b.Latitude, 64)
		if lonErr != nil || latErr != nil {
			continue
		}
		p := rawBusPosition{
			PlateNumb:   b.BusID,
			SubRouteUID: prefix + b.RouteID,
			StopUID:     atStop[b.BusID],
			Direction:   direction,
			Azimuth:     dataTaipeiFloat(b.Azimuth),
			Speed:       dataTaipeiFloat(b.Speed),
			DutyStatus:  dataTaipeiUint8(b.DutyStatus),
			BusStatus:   dataTaipeiUint8(b.BusStatus),
			GPSTime:     b.DataTime,
			CrowdLevel:  crowd[b.BusID],
		}
		p.BusPosition.PositionLon = lon
		p.BusPosition.PositionLat = lat
		out = append(out, p)
	}
	return out
}

// dataTaipeiCrowdLevel maps the feed's 0/1/2 banding onto the wire enum, which
// reserves its own zero for "no reading". A null Level, or a band the feed has
// not documented, reports false and leaves the vehicle unlabelled.
func dataTaipeiCrowdLevel(level *int) (models.BusCrowdLevel, bool) {
	if level == nil {
		return models.BusCrowdLevel_BUS_CROWD_UNKNOWN, false
	}
	switch *level {
	case 0:
		return models.BusCrowdLevel_BUS_CROWD_COMFORTABLE, true
	case 1:
		return models.BusCrowdLevel_BUS_CROWD_NORMAL, true
	case 2:
		return models.BusCrowdLevel_BUS_CROWD_CROWDED, true
	default:
		return models.BusCrowdLevel_BUS_CROWD_UNKNOWN, false
	}
}

// dataTaipeiDirection maps GoBack onto the TDX Direction. "2" is the feed's
// 未知, which no canonical subroute can be derived from.
func dataTaipeiDirection(goBack string) (uint8, bool) {
	switch goBack {
	case "0":
		return 0, true
	case "1":
		return 1, true
	default:
		return 0, false
	}
}

func dataTaipeiFloat(s string) float64 {
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0
	}
	return v
}

func dataTaipeiUint8(s string) uint8 {
	v, err := strconv.Atoi(s)
	if err != nil || v < 0 || v > 255 {
		return 0
	}
	return uint8(v)
}

// dataTaipeiEstimate is one GetEstimateTime element: a route's live estimate at
// one stop. Unlike TDX's EstimatedTimeOfArrival, status is folded into
// EstimateTime's sign instead of a separate field: positive is seconds to
// arrival, and -1/-2/-3/-4 name the same four schedule states TDX's own
// StopStatus enum does (app/lib/data/models/eta_format.dart). RouteID is the
// 主路線 (main route) — the same route-level granularity Taipei and NewTaipei
// already publish through TDX (see buildBusEtaMap's comment on SubRouteUID),
// so this loses no detail relative to what ships today.
type dataTaipeiEstimate struct {
	RouteID      int    `json:"RouteID"`
	StopID       int    `json:"StopID"`
	EstimateTime string `json:"EstimateTime"`
	GoBack       string `json:"GoBack"`
}

// etaSource is a live ETA feed that replaces TDX's for a city rather than
// overlaying it, the way vehicleSource's positions do. A nil map entry (or a
// city missing from it) leaves that city on TDX.
type etaSource interface {
	estimates(context.Context) ([]rawBusEsimated, error)
}

// estimates fetches GetEstimateTime and returns it as TDX-shaped ETA rows.
func (f *dataTaipeiFeed) estimates(ctx context.Context) ([]rawBusEsimated, error) {
	var rows []dataTaipeiEstimate
	fresh, err := f.getRows(ctx, "GetEstimateTime", &rows)
	if err != nil {
		return nil, err
	}
	f.mu.Lock()
	if fresh {
		f.estimateRows = rows
	}
	rows = f.estimateRows
	f.mu.Unlock()
	return dataTaipeiRawEstimates(f.prefix, rows), nil
}

// dataTaipeiRawEstimates converts the feed onto the TDX ETA shape the ETA job
// already consumes. A row whose EstimateTime does not parse as one of the
// documented values is dropped rather than guessed at.
func dataTaipeiRawEstimates(prefix string, rows []dataTaipeiEstimate) []rawBusEsimated {
	out := make([]rawBusEsimated, 0, len(rows))
	for _, r := range rows {
		status, seconds, ok := dataTaipeiStopStatus(r.EstimateTime)
		if !ok {
			continue
		}
		out = append(out, rawBusEsimated{
			StopUID:       fmt.Sprintf("%s%d", prefix, r.StopID),
			RouteUID:      fmt.Sprintf("%s%d", prefix, r.RouteID),
			Direction:     dataTaipeiEstimateDirection(r.GoBack),
			EstimatedTime: seconds,
			StopStatus:    status,
		})
	}
	return out
}

// dataTaipeiStopStatus maps EstimateTime's sign onto TDX's StopStatus: a
// positive value is status 0 (a live countdown) with that many seconds to
// arrival, and -1/-2/-3/-4 are TDX's 1/2/3/4 in disguise — not yet departed,
// traffic control, last bus passed, not operating today.
func dataTaipeiStopStatus(estimateTime string) (status uint8, seconds int32, ok bool) {
	v, err := strconv.Atoi(estimateTime)
	if err != nil {
		return 0, 0, false
	}
	if v > 0 {
		return 0, int32(v), true
	}
	switch v {
	case -1, -2, -3, -4:
		return uint8(-v), 0, true
	default:
		return 0, 0, false
	}
}

// dataTaipeiEstimateDirection maps GoBack onto TDX's Direction. "2" (not yet
// departed) and "3" (last bus gone) carry no direction; busEtaDirectionUnknown
// fans such an entry out across every direction mp records for the route —
// the same widening buildBusEtaMap already does for Tainan's schedule-only
// entries.
func dataTaipeiEstimateDirection(goBack string) uint8 {
	switch goBack {
	case "0":
		return 0
	case "1":
		return 1
	default:
		return busEtaDirectionUnknown
	}
}

// mergeDataTaipeiPositions layers the Data.taipei rows over the TDX ones: a
// subroute direction Data.taipei reports is taken from Data.taipei entirely,
// and one it does not report keeps its TDX rows. Overlaying rather than
// replacing matters because the two feeds do not cover the same set — a
// subroute TDX knows and Data.taipei has never heard of would otherwise lose
// its vehicles the moment this path turned on.
func mergeDataTaipeiPositions(tdx, dataTaipei []rawBusPosition) []rawBusPosition {
	if len(dataTaipei) == 0 {
		return tdx
	}
	covered := make(map[string]struct{}, len(dataTaipei))
	for _, p := range dataTaipei {
		covered[busPositionIdentity(p.SubRouteUID, p.Direction)] = struct{}{}
	}
	merged := make([]rawBusPosition, 0, len(tdx)+len(dataTaipei))
	merged = append(merged, dataTaipei...)
	for _, p := range tdx {
		if _, ok := covered[busPositionIdentity(p.SubRouteUID, p.Direction)]; !ok {
			merged = append(merged, p)
		}
	}
	return merged
}

// overlayVehicles is the ETA job's whole view of this file: for a city listed
// in j.vehicles it swaps in the richer vehicles, and for every other city,
// every failure, and a job with no feed at all it hands back the TDX
// positions it was given.
func (j *busLiveJob) overlayVehicles(ctx context.Context, city string, tdx []rawBusPosition) []rawBusPosition {
	feed, ok := j.vehicles[city]
	if !ok {
		return tdx
	}
	fresh, err := feed.positions(ctx)
	if err != nil {
		zap.S().Warnw(fmt.Sprintf("fetch failed; keeping TDX positions: %v", err),
			"component", "datataipei",
			"action", "positions",
			"city", city,
		)
		return tdx
	}
	return mergeDataTaipeiPositions(tdx, fresh)
}
