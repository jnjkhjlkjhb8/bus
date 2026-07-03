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
	return &MaasServer{rc: rc, db: db, maasClient: c}
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

func (s *MaasServer) plan(ctx context.Context, req *pb.MaasPlanRequest) (*pb.MaasPlanResponse, error) {
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
	paramTime := fmt.Sprintf("%sT%s", req.Date, req.Time)

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

	var apiResp tdxAPIResponse
	resp, err := s.maasClient.R().
		SetContext(ctx).
		SetQueryParam("origin", fmt.Sprintf("%.6f,%.6f", req.FromLat, req.FromLon)).
		SetQueryParam("destination", fmt.Sprintf("%.6f,%.6f", req.ToLat, req.ToLon)).
		SetQueryParam("depart", paramTime).
		SetQueryParam("arrival", paramTime).
		SetQueryParam("gc", fmt.Sprintf("%.2f", gc)).
		SetQueryParam("top", "5").
		SetQueryParam("transit", transitStr).
		SetQueryParam("transfer_time", "15,60").
		SetQueryParam("first_mile_mode", "0").
		SetQueryParam("first_mile_time", "10").
		SetQueryParam("last_mile_mode", "0").
		SetQueryParam("last_mile_time", "10").
		SetResult(&apiResp).
		Get("/routing")
	if err != nil {
		return nil, err
	}
	if !resp.IsSuccess() {
		return nil, fmt.Errorf("TDX MaaS HTTP %d", resp.StatusCode())
	}
	return convert(ctx, s.db, &apiResp), nil
}
func convert(ctx context.Context, db maasDB, api *tdxAPIResponse) *pb.MaasPlanResponse {
	out := &pb.MaasPlanResponse{}
	for _, route := range api.Data.Routes {
		pbRoute := &pb.Route{
			TravelTime: route.TravelTime,
			StartTime:  route.StartTime,
			EndTime:    route.EndTime,
			Transfers:  route.Transfers,
		}
		for _, sec := range route.Sections {
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
			pbRoute.Sections = append(pbRoute.Sections, pbSec)
		}
		out.Routes = append(out.Routes, pbRoute)
	}
	return out
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

func maasKey(req *pb.MaasPlanRequest) string {
	key := fmt.Sprintf("%.6f,%.6f,%.6f,%.6f,%s,%s,%v,%.2f,%v",
		req.FromLat, req.FromLon, req.ToLat, req.ToLon,
		req.Date, req.Time, req.ArriveBy, req.Gc, req.TransitModes)
	sum := sha256.Sum256([]byte(key))
	return fmt.Sprintf("maas:plan:v2:%x", sum[:8])
}
