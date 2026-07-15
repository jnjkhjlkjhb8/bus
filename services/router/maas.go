package main

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	legacyredis "github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	redisv9 "github.com/redis/go-redis/v9"
	"golang.org/x/sync/errgroup"
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
	cache       maasCache
	db          maasDB
	maasClient  *resty.Client
	osrmClient  *resty.Client
	sfGroup     singleflight.Group
	workSlots   chan struct{}
	workTimeout time.Duration
}

type maasDB interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
}

type maasCache interface {
	Get(context.Context, string) ([]byte, error)
	Set(context.Context, string, []byte, time.Duration) error
}

type redisMaasCache struct{ client *redisv9.Client }

func v9SocketTimeout(effectiveLegacyTimeout time.Duration) time.Duration {
	if effectiveLegacyTimeout == 0 {
		return -1
	}
	return effectiveLegacyTimeout
}

func redisMaasOptions(legacy *legacyredis.Options) *redisv9.Options {
	maxRetries := legacy.MaxRetries
	if maxRetries == 0 {
		// v6 defaults to no command retries, while v9 uses three when this is
		// zero. Preserve the configured client's effective behavior.
		maxRetries = -1
	}
	var tlsConfig = legacy.TLSConfig
	if tlsConfig != nil {
		tlsConfig = tlsConfig.Clone()
	}
	return &redisv9.Options{
		Network: legacy.Network,
		Addr:    legacy.Addr,

		// go-redis v6 supports password-only authentication; it has no
		// username setting to copy.
		Password: legacy.Password,
		DB:       legacy.DB,

		MaxRetries:      maxRetries,
		MinRetryBackoff: legacy.MinRetryBackoff,
		MaxRetryBackoff: legacy.MaxRetryBackoff,

		DialTimeout:  legacy.DialTimeout,
		ReadTimeout:  v9SocketTimeout(legacy.ReadTimeout),
		WriteTimeout: v9SocketTimeout(legacy.WriteTimeout),

		PoolSize:        legacy.PoolSize,
		MinIdleConns:    legacy.MinIdleConns,
		PoolTimeout:     legacy.PoolTimeout,
		ConnMaxLifetime: legacy.MaxConnAge,
		ConnMaxIdleTime: legacy.IdleTimeout,

		TLSConfig:             tlsConfig,
		Protocol:              2,
		ContextTimeoutEnabled: true,
		DisableIdentity:       true,
	}
}

func newRedisMaasCache(legacy *legacyredis.Options) *redisMaasCache {
	return &redisMaasCache{client: redisv9.NewClient(redisMaasOptions(legacy))}
}

func (c *redisMaasCache) Get(ctx context.Context, key string) ([]byte, error) {
	value, err := c.client.Get(ctx, key).Bytes()
	if err != nil && ctx.Err() != nil {
		return nil, ctx.Err()
	}
	return value, err
}

func (c *redisMaasCache) Set(ctx context.Context, key string, value []byte, ttl time.Duration) error {
	err := c.client.Set(ctx, key, value, ttl).Err()
	if err != nil && ctx.Err() != nil {
		return ctx.Err()
	}
	return err
}

func (c *redisMaasCache) Close() error {
	return c.client.Close()
}

type maasSharedWorkConfig struct {
	MaxConcurrent int
	Timeout       time.Duration
}

var defaultMaasSharedWorkConfig = maasSharedWorkConfig{
	MaxConcurrent: 4,
	Timeout:       20 * time.Second,
}

const maasOSRMConcurrency = 4

func shouldRetryMaas(resp *resty.Response, err error) bool {
	if err != nil {
		return !errors.Is(err, context.Canceled) &&
			!errors.Is(err, context.DeadlineExceeded) &&
			!shared.IsTDXAuthError(err)
	}
	return resp != nil && (resp.StatusCode() == http.StatusTooManyRequests || resp.StatusCode() == http.StatusServiceUnavailable)
}

func newMaasServerWithCache(cache maasCache, db maasDB, tdx *shared.TDXClient, workConfig maasSharedWorkConfig) *MaasServer {
	// The MaaS API family has a different base URL and retry policy than the
	// basic conditional-GET client, so it gets its own resty client — but the
	// bearer-token auth flows through the shared TDX client (NewAuthedClient) so
	// the token exchange lives in exactly one place.
	c := tdx.NewAuthedClient("https://tdx.transportdata.tw/api/maas").
		SetHeader("Content-Type", "application/json").
		SetRetryCount(3).
		SetRetryWaitTime(500 * time.Millisecond).
		AddRetryCondition(shouldRetryMaas)
	if workConfig.MaxConcurrent <= 0 {
		workConfig.MaxConcurrent = defaultMaasSharedWorkConfig.MaxConcurrent
	}
	if workConfig.Timeout <= 0 {
		workConfig.Timeout = defaultMaasSharedWorkConfig.Timeout
	}
	return &MaasServer{
		cache: cache, db: db, maasClient: c, osrmClient: resty.New().SetTimeout(5 * time.Second),
		workSlots: make(chan struct{}, workConfig.MaxConcurrent), workTimeout: workConfig.Timeout,
	}
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
	result := s.sfGroup.DoChan(cacheKey, func() (any, error) {
		return s.runSharedPlan(cacheKey, req)
	})
	select {
	case <-ctx.Done():
		return nil, status.FromContextError(ctx.Err()).Err()
	case completed := <-result:
		if completed.Err != nil {
			log.Infof("[MAAS] plan error: %v", completed.Err)
			if errors.Is(completed.Err, context.Canceled) || errors.Is(completed.Err, context.DeadlineExceeded) {
				return nil, status.FromContextError(completed.Err).Err()
			}
			if status.Code(completed.Err) != codes.Unknown {
				return nil, completed.Err
			}
			return nil, status.Errorf(codes.Unavailable, "route planning unavailable: %v", completed.Err)
		}
		return completed.Val.(*pb.MaasPlanResponse), nil
	}
}

func (s *MaasServer) runSharedPlan(cacheKey string, req *pb.MaasPlanRequest) (*pb.MaasPlanResponse, error) {
	workCtx, cancel := context.WithTimeout(context.Background(), s.workTimeout)
	defer cancel()
	select {
	case s.workSlots <- struct{}{}:
		defer func() { <-s.workSlots }()
	default:
		return nil, status.Error(codes.ResourceExhausted, "MaaS concurrency limit exceeded")
	}

	cached, err := s.cache.Get(workCtx, cacheKey)
	if err == nil {
		var response pb.MaasPlanResponse
		if err := proto.Unmarshal(cached, &response); err == nil {
			return &response, nil
		}
	}
	if err := workCtx.Err(); err != nil {
		return nil, err
	}

	response, err := s.get(workCtx, req)
	if err != nil {
		return nil, err
	}
	encoded, err := proto.Marshal(response)
	if err != nil {
		return response, nil
	}
	if err := s.cache.Set(workCtx, cacheKey, encoded, 90*time.Second); err != nil {
		if contextErr := workCtx.Err(); contextErr != nil {
			return nil, contextErr
		}
		log.Infof("[MAAS] cache set failed: %v", err)
	}
	return response, nil
}

// maasTimeParam builds the TDX routing time query params. Despite the docs
// saying depart and arrival are mutually exclusive, TDX's validator requires
// BOTH to be present — omitting either returns code 40001 — so both are sent
// with the same value. TDX also rejects a depart at/before now with code
// 20001, so a depart search bumps the time one minute ahead when it is not in
// the future. The app sends HH:mm, so the seconds are padded (40001
// otherwise). Times are Taipei (server local per TDX); an unparseable value
// falls through as-is.
func maasTimeParam(date, timeStr string, arriveBy bool, now time.Time) (depart, arrival string) {
	if len(timeStr) == len("HH:mm") {
		timeStr += ":00"
	}
	const layout = "2006-01-02T15:04:05"
	value := fmt.Sprintf("%sT%s", date, timeStr)
	if !arriveBy {
		if t, err := time.ParseInLocation(layout, value, time.Local); err == nil && !t.After(now) {
			value = now.Add(time.Minute).Format(layout)
		}
	}
	return value, value
}

func (s *MaasServer) get(ctx context.Context, req *pb.MaasPlanRequest) (*pb.MaasPlanResponse, error) {
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
	r := s.maasClient.R().
		SetContext(ctx).
		SetQueryParam("origin", fmt.Sprintf("%.6f,%.6f", req.FromLat, req.FromLon)).
		SetQueryParam("destination", fmt.Sprintf("%.6f,%.6f", req.ToLat, req.ToLon)).
		SetQueryParam("gc", fmt.Sprintf("%.1f", gc)).
		SetQueryParam("top", fmt.Sprintf("%d", top)).
		SetQueryParam("transit", transitStr).
		SetQueryParam("transfer_time", fmt.Sprintf("%d,%d", tMin, tMax)).
		SetQueryParam("first_mile_mode", fmt.Sprintf("%d", firstMode)).
		SetQueryParam("first_mile_time", fmt.Sprintf("%d", firstTime)).
		SetQueryParam("last_mile_mode", fmt.Sprintf("%d", lastMode)).
		SetQueryParam("last_mile_time", fmt.Sprintf("%d", lastTime)).
		SetResult(&apiResp)
	depart, arrival := maasTimeParam(req.Date, req.Time, req.ArriveBy, time.Now())
	r.SetQueryParam("depart", depart)
	r.SetQueryParam("arrival", arrival)
	resp, err := r.Get("/routing")
	if err != nil {
		return nil, err
	}
	if !resp.IsSuccess() {
		return nil, fmt.Errorf("TDX MaaS HTTP %d for %s: %s",
			resp.StatusCode(), resp.Request.URL, strings.TrimSpace(resp.String()))
	}
	return convert(ctx, s.db, s.osrmClient, &apiResp), nil
}

type maasSectionRef struct {
	index  int32
	source tdxSection
	target *pb.Section
	route  *pb.Route
}

func convert(ctx context.Context, db maasDB, osrmClient *resty.Client, api *tdxAPIResponse) *pb.MaasPlanResponse {
	out := &pb.MaasPlanResponse{}
	refs := make([]maasSectionRef, 0)
	for _, route := range api.Data.Routes {
		pbRoute := &pb.Route{
			TravelTime: route.TravelTime,
			StartTime:  route.StartTime,
			EndTime:    route.EndTime,
			Transfers:  route.Transfers,
		}
		for _, sec := range route.Sections {
			pbSec := convertSection(sec)
			pbRoute.Sections = append(pbRoute.Sections, pbSec)
			refs = append(refs, maasSectionRef{
				index: int32(len(refs)), source: sec, target: pbSec, route: pbRoute,
			})
		}
		out.Routes = append(out.Routes, pbRoute)
	}
	batchBusNotificationIdentities(ctx, db, refs)
	batchSectionFares(ctx, db, refs)
	enrichWalkSections(ctx, osrmClient, refs)
	return out
}

func convertSection(sec tdxSection) *pb.Section {
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
	return pbSec
}

func batchBusNotificationIdentities(ctx context.Context, db maasDB, refs []maasSectionRef) {
	if db == nil {
		return
	}
	var indices []int32
	var departures, arrivals, names, shortNames, numbers []string
	byIndex := make(map[int32]*pb.Section)
	for _, ref := range refs {
		if !isBusMode(ref.source.Transport.Mode) {
			continue
		}
		indices = append(indices, ref.index)
		departures = append(departures, ref.source.Departure.Place.Name)
		arrivals = append(arrivals, ref.source.Arrival.Place.Name)
		names = append(names, ref.source.Transport.Name)
		shortNames = append(shortNames, ref.source.Transport.ShortName)
		numbers = append(numbers, ref.source.Transport.Number)
		byIndex[ref.index] = ref.target
	}
	if len(indices) == 0 {
		return
	}
	rows, err := db.Query(ctx, `
		WITH input AS (
			SELECT *
			FROM unnest($1::integer[], $2::text[], $3::text[], $4::text[], $5::text[], $6::text[])
				AS request(section_index, departure_name, arrival_name, route_name, sub_route_name, route_number)
		), matches AS (
			SELECT request.section_index, b.sub_route_uid, b.direction,
				departure.stop_uid AS departure_stop_uid,
				arrival.stop_uid AS arrival_stop_uid,
				COUNT(*) OVER (PARTITION BY request.section_index) AS match_count,
				ROW_NUMBER() OVER (
					PARTITION BY request.section_index
					ORDER BY b.sub_route_uid, b.direction, departure.stop_uid, arrival.stop_uid
				) AS match_rank
			FROM input request
			JOIN bus_subroutes b ON true
			JOIN bus_station_stop_map departure
			  ON departure.sub_route_uid = b.sub_route_uid AND departure.direction = b.direction
			JOIN bus_station_stop_map arrival
			  ON arrival.sub_route_uid = b.sub_route_uid AND arrival.direction = b.direction
			WHERE departure.station_name = request.departure_name
			  AND arrival.station_name = request.arrival_name
			  AND arrival.stop_sequence > departure.stop_sequence
			  AND (
				(request.route_name <> '' AND (b.route_name = request.route_name OR b.sub_route_name = request.route_name))
				OR (request.sub_route_name <> '' AND (b.route_name = request.sub_route_name OR b.sub_route_name = request.sub_route_name))
				OR (request.route_number <> '' AND (b.route_name = request.route_number OR b.sub_route_name = request.route_number))
			  )
		)
		SELECT section_index, sub_route_uid, direction, departure_stop_uid, arrival_stop_uid, match_count
		FROM matches
		WHERE match_rank = 1`, indices, departures, arrivals, names, shortNames, numbers)
	if err != nil {
		return
	}
	defer rows.Close()
	for rows.Next() {
		var index, direction int32
		var routeKey, departureStopKey, arrivalStopKey string
		var matchCount int64
		if rows.Scan(&index, &routeKey, &direction, &departureStopKey, &arrivalStopKey, &matchCount) != nil {
			return
		}
		if target := byIndex[index]; target != nil && matchCount == 1 {
			target.NotificationIdentity = &pb.NotificationIdentity{
				RouteType: "bus", RouteKey: routeKey, Direction: fmt.Sprint(direction),
				DepartureStopKey: departureStopKey, ArrivalStopKey: arrivalStopKey, Supported: true,
			}
		}
	}
}

func batchSectionFares(ctx context.Context, db maasDB, refs []maasSectionRef) {
	if db == nil {
		return
	}
	var indices []int32
	var modes, departures, arrivals []string
	byIndex := make(map[int32]maasSectionRef)
	for _, ref := range refs {
		mode := ref.source.Transport.Mode
		if !isMetroMode(mode) && !isRailMode(mode) && !isThsrMode(mode) {
			continue
		}
		indices = append(indices, ref.index)
		modes = append(modes, strings.ToLower(mode))
		departures = append(departures, ref.source.Departure.Place.Name)
		arrivals = append(arrivals, ref.source.Arrival.Place.Name)
		byIndex[ref.index] = ref
	}
	if len(indices) == 0 {
		return
	}
	rows, err := db.Query(ctx, `
		WITH input AS (
			SELECT *
			FROM unnest($1::integer[], $2::text[], $3::text[], $4::text[])
				AS request(section_index, mode, departure_name, arrival_name)
		), fare_matches AS (
			SELECT request.section_index, m.fare_nt AS fare
			FROM input request
			JOIN mrt_station origin ON origin.name = request.departure_name
			JOIN mrt_station destination ON destination.name = request.arrival_name AND destination.system = origin.system
			JOIN mrt_journey_matrix m ON m.from_station_id = origin.station_id
				AND m.to_station_id = destination.station_id AND m.system = origin.system
			WHERE request.mode IN ('subway', 'metro', 'mrt')
			UNION ALL
			SELECT request.section_index, f.price
			FROM input request
			JOIN thsr_stations origin ON origin.name = request.departure_name
			JOIN thsr_stations destination ON destination.name = request.arrival_name
			JOIN thsr_fares f ON f.origin_station_id = origin.station_id AND f.destination_station_id = destination.station_id
			WHERE request.mode IN ('thsr', 'hsr') AND f.ticket_type = 1 AND f.fare_class = 1
			UNION ALL
			SELECT request.section_index, f.price
			FROM input request
			JOIN tra_stations origin ON origin.name = request.departure_name
			JOIN tra_stations destination ON destination.name = request.arrival_name
			JOIN tra_fares f ON f.origin_station_id = origin.station_id AND f.destination_station_id = destination.station_id
			WHERE request.mode IN ('rail', 'tra', 'train')
		)
		SELECT section_index, MIN(fare)::integer AS fare
		FROM fare_matches
		WHERE fare > 0
		GROUP BY section_index`, indices, modes, departures, arrivals)
	if err != nil {
		return
	}
	defer rows.Close()
	fares := make(map[int32]int32, len(byIndex))
	for rows.Next() {
		var index, fare int32
		if rows.Scan(&index, &fare) != nil {
			return
		}
		if _, ok := byIndex[index]; !ok || fare <= 0 {
			continue
		}
		if current, ok := fares[index]; !ok || fare < current {
			fares[index] = fare
		}
	}
	for index, fare := range fares {
		ref := byIndex[index]
		ref.target.Fare = fare
		ref.route.TotalFare += fare
	}
}

// enrichWalkSections treats OSRM as optional enrichment: cancellation, timeout,
// and routing failures leave the TDX duration and empty geometry untouched. The
// indexed section references preserve response order while errgroup bounds the
// number of concurrent OSRM requests.
func enrichWalkSections(ctx context.Context, osrmClient *resty.Client, refs []maasSectionRef) {
	if osrmClient == nil {
		return
	}
	group, groupCtx := errgroup.WithContext(ctx)
	group.SetLimit(maasOSRMConcurrency)
	for _, ref := range refs {
		if !isWalkSection(ref.source) {
			continue
		}
		ref := ref
		group.Go(func() error {
			if err := groupCtx.Err(); err != nil {
				return err
			}
			secs, path, steps, ok := walkRoute(groupCtx, osrmClient, ref.target.Departure.Location, ref.target.Arrival.Location)
			if ok {
				ref.target.TravelSummary.Duration = secs
				ref.target.WalkPath = path
				ref.target.WalkSteps = steps
			}
			return nil
		})
	}
	_ = group.Wait()
}

// isWalkSection reports whether a section is a pedestrian leg. Keyed off the
// section type: live TDX MaaS responses emit type "pedestrian" with mode
// "pedestrian" (not the documented "WALK"), and walk legs still carry a
// transport block, so the type field is the reliable discriminator — mirrors
// the app's isWalk. The legacy ""/"walk" modes are kept for older payloads.
func isWalkSection(sec tdxSection) bool {
	return strings.EqualFold(sec.Type, "pedestrian") ||
		sec.Transport.Mode == "" || strings.EqualFold(sec.Transport.Mode, "walk")
}

// osrmRouteResponse is the subset of the OSRM /route/v1/foot response the
// planner consumes: total duration, the geojson geometry, and the per-leg
// turn-by-turn steps.
type osrmRouteResponse struct {
	Code   string `json:"code"`
	Routes []struct {
		Duration float64 `json:"duration"`
		Geometry struct {
			Coordinates [][]float64 `json:"coordinates"`
		} `json:"geometry"`
		Legs []struct {
			Steps []struct {
				Distance float64 `json:"distance"`
				Duration float64 `json:"duration"`
				Name     string  `json:"name"`
				Maneuver struct {
					Type     string    `json:"type"`
					Modifier string    `json:"modifier"`
					Location []float64 `json:"location"`
				} `json:"maneuver"`
			} `json:"steps"`
		} `json:"legs"`
	} `json:"routes"`
}

// walkRoute resolves the OSRM foot route between two points for a walk section.
// It returns the real travel time (seconds), the route geometry, and the
// turn-by-turn steps from a single /route call. ok is false when either point
// lacks coordinates or OSRM returns no usable route, so the caller keeps the
// fixed TDX estimate and leaves the path and steps empty.
func walkRoute(ctx context.Context, osrmClient *resty.Client, from, to *pb.Location) (int64, []*pb.Location, []*pb.WalkStep, bool) {
	if osrmClient == nil || from == nil || to == nil {
		return 0, nil, nil, false
	}
	if (from.Lat == 0 && from.Lng == 0) || (to.Lat == 0 && to.Lng == 0) {
		return 0, nil, nil, false
	}
	coords := fmt.Sprintf("%f,%f;%f,%f", from.Lng, from.Lat, to.Lng, to.Lat)
	var out osrmRouteResponse
	resp, err := osrmClient.R().
		SetContext(ctx).
		SetQueryParam("steps", "true").
		SetQueryParam("geometries", "geojson").
		SetQueryParam("overview", "full").
		SetResult(&out).
		Get(fmt.Sprintf("http://osrm:5000/route/v1/foot/%s", coords))
	if err != nil || !resp.IsSuccess() || out.Code != "Ok" || len(out.Routes) == 0 {
		return 0, nil, nil, false
	}
	route := out.Routes[0]
	path := make([]*pb.Location, 0, len(route.Geometry.Coordinates))
	for _, c := range route.Geometry.Coordinates {
		if len(c) < 2 {
			continue
		}
		// geojson coordinates are [lng, lat].
		path = append(path, &pb.Location{Lng: c[0], Lat: c[1]})
	}
	var steps []*pb.WalkStep
	for _, leg := range route.Legs {
		for _, st := range leg.Steps {
			step := &pb.WalkStep{
				Instruction:     walkInstruction(st.Maneuver.Type, st.Maneuver.Modifier, st.Name),
				ManeuverType:    st.Maneuver.Type,
				Modifier:        st.Maneuver.Modifier,
				DistanceMeters:  st.Distance,
				DurationSeconds: int64(st.Duration),
			}
			if len(st.Maneuver.Location) >= 2 {
				step.Location = &pb.Location{Lng: st.Maneuver.Location[0], Lat: st.Maneuver.Location[1]}
			}
			steps = append(steps, step)
		}
	}
	return int64(route.Duration), path, steps, true
}

// walkInstruction composes a Traditional Chinese turn-by-turn sentence from one
// OSRM maneuver. Taiwan OSM street names are already Chinese, so the street
// name (when present) is used verbatim. Unknown maneuver types fall back to a
// generic "continue straight" sentence so navigation never shows an empty line.
func walkInstruction(maneuverType, modifier, name string) string {
	switch maneuverType {
	case "arrive":
		return "抵達目的地"
	case "depart":
		if name != "" {
			return fmt.Sprintf("沿%s出發", name)
		}
		return "開始步行"
	}
	turn := map[string]string{
		"left": "左轉", "right": "右轉",
		"slight left": "稍向左", "slight right": "稍向右",
		"sharp left": "向左急轉", "sharp right": "向右急轉",
		"uturn": "迴轉",
	}[modifier]
	switch {
	case turn != "" && name != "":
		return fmt.Sprintf("%s進入%s", turn, name)
	case turn != "":
		return turn
	case name != "":
		return fmt.Sprintf("沿%s直走", name)
	default:
		return "繼續直走"
	}
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
