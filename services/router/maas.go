package main

import (
	"context"
	"crypto/sha256"
	"fmt"
	"strings"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
	"golang.org/x/sync/singleflight"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"

	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
)

// MaasServer answers multimodal route-planning requests by proxying the TDX
// MaaS routing API. Responses are cached in Redis keyed by request parameters,
// and sfGroup collapses concurrent identical requests into a single upstream
// call. Bus sections are enriched with in-app notification identities looked up
// in db.
type MaasServer struct {
	pb.UnimplementedMaasServiceServer
	rc         *redis.Client
	db         maasDB
	maasClient *resty.Client
	osrmClient *resty.Client
	sfGroup    singleflight.Group
}

type maasDB interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
}

func newMaasServer(rc *redis.Client, db maasDB, tdxAuthToken func() string) *MaasServer {
	c := resty.New().
		SetBaseURL("https://tdx.transportdata.tw/api/maas").
		SetHeader("Content-Type", "application/json").
		SetRetryCount(3).
		SetRetryWaitTime(500 * time.Millisecond).
		AddRetryCondition(func(r *resty.Response, err error) bool {
			if err != nil {
				return true
			}
			return r.StatusCode() == 429 || r.StatusCode() == 503
		}).
		OnBeforeRequest(func(_ *resty.Client, req *resty.Request) error {
			req.SetAuthToken(tdxAuthToken())
			return nil
		})
	return &MaasServer{rc: rc, db: db, maasClient: c, osrmClient: resty.New().SetTimeout(5 * time.Second)}
}

type tdxRoute struct {
	TravelTime int64        `json:"travel_time"`
	StartTime  string       `json:"start_time"`
	EndTime    string       `json:"end_time"`
	Transfers  int32        `json:"transfers"`
	Sections   []tdxSection `json:"sections"`
}
type tdxSection struct {
	Type              string       `json:"type"`
	TravelSummary     tdxSummary   `json:"travelSummary"`
	Departure         tdxPlaceInfo `json:"departure"`
	Arrival           tdxPlaceInfo `json:"arrival"`
	Transport         tdxTransport `json:"transport"`
	IntermediateStops []tdxStop    `json:"intermediateStops"`
	Agency            tdxAgency    `json:"agency"`
}
type tdxSummary struct {
	Duration int64   `json:"duration"`
	Length   float64 `json:"length"`
}
type tdxPlaceInfo struct {
	Time  string   `json:"time"`
	Place tdxPlace `json:"place"`
}
type tdxPlace struct {
	Name     string      `json:"name"`
	Type     string      `json:"type"`
	Location tdxLocation `json:"location"`
}
type tdxLocation struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}
type tdxTransport struct {
	Mode       string `json:"mode"`
	Name       string `json:"name"`
	ShortName  string `json:"shortName"`
	Number     string `json:"number"`
	LongName   string `json:"longName"`
	Headsign   string `json:"headsign"`
	Category   string `json:"category"`
	RouteColor string `json:"route_color"`
}
type tdxStop struct {
	Departure tdxPlaceInfo `json:"departure"`
}
type tdxAgency struct {
	AgencyId string `json:"agency_id"`
	Name     string `json:"name"`
	Website  string `json:"website"`
	Phone    string `json:"phone"`
}
type tdxAPIResponse struct {
	Result string `json:"result"`
	Data   struct {
		Routes []tdxRoute `json:"routes"`
	} `json:"data"`
}

func (s *MaasServer) Plan(ctx context.Context, req *pb.MaasPlanRequest) (*pb.MaasPlanResponse, error) {
	cacheKey := maasKey(req)
	if cached, err := s.rc.Get(cacheKey).Bytes(); err == nil {
		var resp pb.MaasPlanResponse
		if err := proto.Unmarshal(cached, &resp); err == nil {
			return &resp, nil
		}
	}
	raw, err, _ := s.sfGroup.Do(cacheKey, func() (interface{}, error) {
		return s.get(ctx, req)
	})
	if err != nil {
		log.Infof("[MAAS] plan error: %v", err)
		return nil, status.Errorf(codes.Unavailable, "route planning unavailable: %v", err)
	}

	resp := raw.(*pb.MaasPlanResponse)
	if bytes, err := proto.Marshal(resp); err == nil {
		s.rc.Set(cacheKey, bytes, 90*time.Second)
	}

	return resp, nil
}
func (s *MaasServer) get(ctx context.Context, req *pb.MaasPlanRequest) (*pb.MaasPlanResponse, error) {
	// TDX expects a full yyyy-mm-ddTHH:mm:ss timestamp; the app sends HH:mm, so
	// pad the seconds when they are missing.
	timeStr := req.Time
	if len(timeStr) == len("HH:mm") {
		timeStr += ":00"
	}
	paramTime := fmt.Sprintf("%sT%s", req.Date, timeStr)

	gc := req.Gc
	if gc < 0 || gc > 1 {
		gc = 0.0
	}

	transitModes := req.TransitModes
	if len(transitModes) == 0 {
		transitModes = []int32{3, 4, 5, 6, 7, 8, 9}
	}
	parts := make([]string, len(transitModes))
	for i, m := range transitModes {
		parts[i] = fmt.Sprintf("%d", m)
	}
	transitStr := strings.Join(parts, ",")

	top := clampInt(req.Top, 1, 10, 5)
	tMin := clampInt(req.TransferTimeMin, 0, 60, 15)
	tMax := clampInt(req.TransferTimeMax, 0, 60, 60)
	if tMin > tMax {
		tMin, tMax = tMax, tMin
	}
	firstMode := clampInt(req.FirstMileMode, 0, 3, 0)
	firstTime := clampInt(req.FirstMileTime, 1, 60, 10)
	lastMode := clampInt(req.LastMileMode, 0, 3, 0)
	lastTime := clampInt(req.LastMileTime, 1, 60, 10)

	var apiResp tdxAPIResponse
	resp, err := s.maasClient.R().
		SetContext(ctx).
		SetQueryParam("origin", fmt.Sprintf("%.6f,%.6f", req.FromLat, req.FromLon)).
		SetQueryParam("destination", fmt.Sprintf("%.6f,%.6f", req.ToLat, req.ToLon)).
		SetQueryParam("depart", paramTime).
		SetQueryParam("arrival", paramTime).
		SetQueryParam("gc", fmt.Sprintf("%.1f", gc)).
		SetQueryParam("top", fmt.Sprintf("%d", top)).
		SetQueryParam("transit", transitStr).
		SetQueryParam("transfer_time", fmt.Sprintf("%d,%d", tMin, tMax)).
		SetQueryParam("first_mile_mode", fmt.Sprintf("%d", firstMode)).
		SetQueryParam("first_mile_time", fmt.Sprintf("%d", firstTime)).
		SetQueryParam("last_mile_mode", fmt.Sprintf("%d", lastMode)).
		SetQueryParam("last_mile_time", fmt.Sprintf("%d", lastTime)).
		SetResult(&apiResp).
		Get("/routing")
	if err != nil {
		return nil, err
	}
	if !resp.IsSuccess() {
		return nil, fmt.Errorf("TDX MaaS HTTP %d", resp.StatusCode())
	}
	return convert(ctx, s.db, s.osrmClient, &apiResp), nil
}
func convert(ctx context.Context, db maasDB, osrmClient *resty.Client, api *tdxAPIResponse) *pb.MaasPlanResponse {
	out := &pb.MaasPlanResponse{}
	for _, route := range api.Data.Routes {
		pbRoute := &pb.Route{
			TravelTime: route.TravelTime,
			StartTime:  route.StartTime,
			EndTime:    route.EndTime,
			Transfers:  route.Transfers,
		}
		for secIdx, sec := range route.Sections {
			pbSec := &pb.Section{
				Type: sec.Type,
				TravelSummary: &pb.Summary{
					Duration: sec.TravelSummary.Duration,
					Length:   sec.TravelSummary.Length,
				},
				Departure: &pb.Place{
					Name: sec.Departure.Place.Name,
					Type: sec.Departure.Place.Type,
					Time: sec.Departure.Time,
					Location: &pb.Location{
						Lat: sec.Departure.Place.Location.Lat,
						Lng: sec.Departure.Place.Location.Lng,
					},
				},
				Arrival: &pb.Place{
					Name: sec.Arrival.Place.Name,
					Type: sec.Arrival.Place.Type,
					Time: sec.Arrival.Time,
					Location: &pb.Location{
						Lat: sec.Arrival.Place.Location.Lat,
						Lng: sec.Arrival.Place.Location.Lng,
					},
				},
				NotificationIdentity: &pb.NotificationIdentity{},
			}
			if sec.Transport.Mode != "" {
				pbSec.Transport = &pb.Transport{
					Mode:       sec.Transport.Mode,
					Name:       sec.Transport.Name,
					ShortName:  sec.Transport.ShortName,
					LongName:   sec.Transport.LongName,
					Headsign:   sec.Transport.Headsign,
					Category:   sec.Transport.Category,
					RouteColor: sec.Transport.RouteColor,
				}
			}
			for _, stop := range sec.IntermediateStops {
				pbSec.IntermediateStops = append(pbSec.IntermediateStops, &pb.IntermediateStop{
					Name:          stop.Departure.Place.Name,
					DepartureTime: stop.Departure.Time,
					Location: &pb.Location{
						Lat: stop.Departure.Place.Location.Lat,
						Lng: stop.Departure.Place.Location.Lng,
					},
				})
			}
			if sec.Agency.Name != "" {
				pbSec.Agency = &pb.Agency{
					AgencyId: sec.Agency.AgencyId,
					Name:     sec.Agency.Name,
					Website:  sec.Agency.Website,
					Phone:    sec.Agency.Phone,
				}
			}
			pbSec.NotificationIdentity = resolveBusNotificationIdentity(ctx, db, sec)

			// First/last-mile walks: TDX bakes the fixed first_mile_time /
			// last_mile_time budget into their duration. Replace it with the real
			// OSRM foot time when both endpoints have coordinates; on any OSRM
			// error or missing coordinate the TDX value is left untouched.
			if isWalkMode(sec.Transport.Mode) && (secIdx == 0 || secIdx == len(route.Sections)-1) {
				if secs, ok := walkDurationSeconds(ctx, osrmClient, pbSec.Departure.Location, pbSec.Arrival.Location); ok {
					pbSec.TravelSummary.Duration = secs
				}
			}

			if fare, ok := sectionFare(ctx, db, sec); ok {
				pbSec.Fare = fare
				pbRoute.TotalFare += fare
			}

			pbRoute.Sections = append(pbRoute.Sections, pbSec)
		}
		out.Routes = append(out.Routes, pbRoute)
	}
	return out
}

// isWalkMode reports whether a section's transport mode is a pedestrian leg.
// TDX emits an empty mode or "WALK" for walking sections.
func isWalkMode(mode string) bool {
	return mode == "" || strings.EqualFold(mode, "walk")
}

// walkDurationSeconds returns the OSRM foot travel time (seconds) between two
// points. ok is false when either point lacks coordinates or OSRM does not
// return a usable duration, so the caller keeps the fixed TDX estimate.
func walkDurationSeconds(ctx context.Context, osrmClient *resty.Client, from, to *pb.Location) (int64, bool) {
	if osrmClient == nil || from == nil || to == nil {
		return 0, false
	}
	if (from.Lat == 0 && from.Lng == 0) || (to.Lat == 0 && to.Lng == 0) {
		return 0, false
	}
	coords := fmt.Sprintf("%f,%f;%f,%f", from.Lng, from.Lat, to.Lng, to.Lat)
	var out struct {
		Code      string      `json:"code"`
		Durations [][]float64 `json:"durations"`
	}
	resp, err := osrmClient.R().
		SetContext(ctx).
		SetQueryParam("sources", "0").
		SetQueryParam("destinations", "1").
		SetQueryParam("annotations", "duration").
		SetResult(&out).
		Get(fmt.Sprintf("http://osrm:5000/table/v1/foot/%s", coords))
	if err != nil || !resp.IsSuccess() || out.Code != "Ok" || len(out.Durations) == 0 || len(out.Durations[0]) == 0 {
		return 0, false
	}
	return int64(out.Durations[0][0]), true
}

// sectionFare resolves the adult full fare (NT$) for one transit section by
// looking up the origin/destination station pair (matched by station name) in
// the mode's fare table: metro → mrt_journey_matrix, TRA → tra_fares, THSR →
// thsr_fares. ok is false for non-rail modes, a missing db, a query error, or
// no matching fare — the caller then leaves the fare unset (a missing fare must
// never fail the plan).
func sectionFare(ctx context.Context, db maasDB, sec tdxSection) (int32, bool) {
	if db == nil {
		return 0, false
	}
	from := sec.Departure.Place.Name
	to := sec.Arrival.Place.Name
	if from == "" || to == "" {
		return 0, false
	}
	switch {
	case isMetroMode(sec.Transport.Mode):
		return queryFare(ctx, db, `
			SELECT m.fare_nt
			FROM mrt_journey_matrix m
			JOIN mrt_station o ON o.station_id = m.from_station_id AND o.system = m.system
			JOIN mrt_station d ON d.station_id = m.to_station_id AND d.system = m.system
			WHERE o.name = $1 AND d.name = $2
			LIMIT 1`, from, to)
	case isThsrMode(sec.Transport.Mode):
		return queryFare(ctx, db, `
			SELECT f.price
			FROM thsr_fares f
			JOIN thsr_stations o ON o.station_id = f.origin_station_id
			JOIN thsr_stations d ON d.station_id = f.destination_station_id
			WHERE o.name = $1 AND d.name = $2 AND f.ticket_type = 1 AND f.fare_class = 1
			ORDER BY f.price
			LIMIT 1`, from, to)
	case isRailMode(sec.Transport.Mode):
		return queryFare(ctx, db, `
			SELECT f.price
			FROM tra_fares f
			JOIN tra_stations o ON o.station_id = f.origin_station_id
			JOIN tra_stations d ON d.station_id = f.destination_station_id
			WHERE o.name = $1 AND d.name = $2
			ORDER BY f.price
			LIMIT 1`, from, to)
	}
	return 0, false
}

// queryFare runs a single-value fare query and reports whether a positive fare
// was found. Any error or non-positive fare yields ok=false.
func queryFare(ctx context.Context, db maasDB, q string, args ...any) (int32, bool) {
	rows, err := db.Query(ctx, q, args...)
	if err != nil {
		return 0, false
	}
	defer rows.Close()
	if !rows.Next() {
		return 0, false
	}
	var fare int32
	if err := rows.Scan(&fare); err != nil || fare <= 0 {
		return 0, false
	}
	return fare, true
}

// Rail-mode classifiers. TDX MaaS mode strings vary by dataset; these cover the
// documented values (SUBWAY/METRO for metro, RAIL/TRA for conventional rail,
// THSR/HSR for high-speed rail).
func isMetroMode(mode string) bool {
	return strings.EqualFold(mode, "subway") || strings.EqualFold(mode, "metro") || strings.EqualFold(mode, "mrt")
}
func isThsrMode(mode string) bool {
	return strings.EqualFold(mode, "thsr") || strings.EqualFold(mode, "hsr")
}
func isRailMode(mode string) bool {
	return strings.EqualFold(mode, "rail") || strings.EqualFold(mode, "tra") || strings.EqualFold(mode, "train")
}

func resolveBusNotificationIdentity(ctx context.Context, db maasDB, sec tdxSection) *pb.NotificationIdentity {
	identity := &pb.NotificationIdentity{}
	if db == nil || !isBusMode(sec.Transport.Mode) {
		return identity
	}
	rows, err := db.Query(ctx, `
		SELECT b.sub_route_uid, b.direction, departure.stop_uid, arrival.stop_uid
		FROM bus_subroutes b
		JOIN bus_station_stop_map departure
		  ON departure.sub_route_uid=b.sub_route_uid AND departure.direction=b.direction
		JOIN bus_station_stop_map arrival
		  ON arrival.sub_route_uid=b.sub_route_uid AND arrival.direction=b.direction
		WHERE departure.station_name=$1
		  AND arrival.station_name=$2
		  AND arrival.stop_sequence>departure.stop_sequence
		  AND (
		    ($3<>'' AND (b.route_name=$3 OR b.sub_route_name=$3))
		    OR ($4<>'' AND (b.route_name=$4 OR b.sub_route_name=$4))
		    OR ($5<>'' AND (b.route_name=$5 OR b.sub_route_name=$5))
		  )
		LIMIT 2`,
		sec.Departure.Place.Name,
		sec.Arrival.Place.Name,
		sec.Transport.Name,
		sec.Transport.ShortName,
		sec.Transport.Number,
	)
	if err != nil {
		return identity
	}
	defer rows.Close()
	var matches []*pb.NotificationIdentity
	for rows.Next() {
		match := &pb.NotificationIdentity{RouteType: "bus", Supported: true}
		var direction int32
		if rows.Scan(&match.RouteKey, &direction, &match.DepartureStopKey, &match.ArrivalStopKey) != nil {
			return identity
		}
		match.Direction = fmt.Sprint(direction)
		matches = append(matches, match)
	}
	if rows.Err() != nil || len(matches) != 1 {
		return identity
	}
	return matches[0]
}

func isBusMode(mode string) bool {
	return strings.EqualFold(mode, "bus") || strings.EqualFold(mode, "HighwayBus")
}

// clampInt returns v bounded to [min,max], or def when v is unset (0) and 0 is
// outside the valid range — so old clients / cached zero-value requests fall
// back to the TDX defaults rather than sending 0.
func clampInt(v, min, max, def int32) int32 {
	if v == 0 && (0 < min || 0 > max) {
		return def
	}
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}

func maasKey(req *pb.MaasPlanRequest) string {
	key := fmt.Sprintf("%.6f,%.6f,%.6f,%.6f,%s,%s,%v,%.2f,%v,%d,%d,%d,%d,%d,%d,%d",
		req.FromLat, req.FromLon, req.ToLat, req.ToLon,
		req.Date, req.Time, req.ArriveBy, req.Gc, req.TransitModes,
		req.Top, req.TransferTimeMin, req.TransferTimeMax,
		req.FirstMileMode, req.FirstMileTime, req.LastMileMode, req.LastMileTime)
	sum := sha256.Sum256([]byte(key))
	return fmt.Sprintf("maas:plan:v3:%x", sum[:8])
}
