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

// Data.taipei (大臺北公車) is the upstream TDX relays Taipei bus data from, and
// it publishes two things TDX drops on the way: the plate number and the
// 附屬路線 id of every reporting vehicle (GetBusData), plus which stop that
// vehicle is standing at (GetBusEvent). TDX's Taipei position feed carries
// neither, which is why bus_eta.go pairs vehicles to arrivals by GPS distance
// (FDPL-66 Phase 1; Phase 2 replaces that pairing with the plate).
//
// The feed only ever replaces positions. Estimates stay on TDX: Data.taipei's
// GetEstimateTime is keyed on the 主路線, the same route-level granularity TDX
// already gives, so swapping it would buy nothing.
//
// There is no SLA behind these blobs. Every failure path here returns the TDX
// positions untouched, so a stalled or unreachable feed degrades to exactly the
// behavior that shipped before this file existed.

const dataTaipeiBlobBase = "https://tcgbusfs.blob.core.windows.net/blobbus/"

// dataTaipeiCity is the only city the feed can be joined to. All 792 subroutes
// it publishes resolve to TPE-prefixed TDX UIDs (measured 2026-08-06:
// 415/415 routes, 784/792 subroutes, 28701/28742 stops) — New Taipei's own
// routes are not in it, so the NewTaipei job stays entirely on TDX.
const dataTaipeiCity = "Taipei"

// dataTaipeiUIDPrefix turns a bare Data.taipei number into a TDX UID. Verified
// by scripts/probe-datataipei-ids.py, which is the gate this whole path rests on.
const dataTaipeiUIDPrefix = "TPE"

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

// dataTaipeiFeed holds one conditional-GET session against the blobs. The blobs
// answer with an ETag and rewrite roughly every 20 seconds, so the last decoded
// payload is kept per endpoint: a 304 on one of the two must not discard the
// other's rows, and the position and event feeds do not always turn over on the
// same tick.
type dataTaipeiFeed struct {
	client *resty.Client

	mu     sync.Mutex
	etag   map[string]string
	buses  []dataTaipeiBus
	events []dataTaipeiEvent
	seats  []dataTaipeiSeat
}

// dataTaipeiClient is shared across ticks for connection reuse, the same shape
// trtcClient has; per-tick deadlines come from the live runner's context.
var dataTaipeiClient = resty.New().
	SetBaseURL(dataTaipeiBlobBase).
	SetTimeout(dataTaipeiTimeout)

var _ vehicleSource = (*dataTaipeiFeed)(nil)

func newDataTaipeiFeed() *dataTaipeiFeed {
	return &dataTaipeiFeed{
		client: dataTaipeiClient,
		etag:   make(map[string]string, 2),
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
	return dataTaipeiRawPositions(buses, events, seats), nil
}

// dataTaipeiRawPositions converts the feed onto the TDX position shape the ETA
// job already consumes. Rows that cannot be placed on a route — an unknown
// direction ("2"), an unparseable coordinate — are dropped rather than passed
// on as a bus at (0, 0).
func dataTaipeiRawPositions(buses []dataTaipeiBus, events []dataTaipeiEvent, seats []dataTaipeiSeat) []rawBusPosition {
	atStop := make(map[string]string, len(events))
	for _, e := range events {
		if e.CarOnStop == "1" && e.StopID != "" {
			atStop[e.BusID] = dataTaipeiUIDPrefix + e.StopID
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
			SubRouteUID: dataTaipeiUIDPrefix + b.RouteID,
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

// overlayVehicles is the ETA job's whole view of this file: for the city the
// configured feed covers it swaps in the richer vehicles, and for every other
// city, every failure, and a job with no feed at all it hands back the TDX
// positions it was given.
func (j *busLiveJob) overlayVehicles(ctx context.Context, city string, tdx []rawBusPosition) []rawBusPosition {
	if j.vehicles == nil || city != dataTaipeiCity {
		return tdx
	}
	fresh, err := j.vehicles.positions(ctx)
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
