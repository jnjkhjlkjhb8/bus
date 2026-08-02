package main

import (
	"context"
	"errors"
	"io"
	"strconv"
	"strings"
	"sync"
	"time"

	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"golang.org/x/sync/errgroup"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
)

// Static implements the Bus_Route_Service Static RPC by delegating to
// BusRouteStatic.
func (s *BusRouteserver) Static(ctx context.Context, in *pb.Bus_Ask_Route) (*pb.Resp_BusStatic, error) {
	return s.BusRouteStatic(ctx, in)
}

// Daily implements the Daily RPC, returning the cached daily timetable payload
// produced by BusDailytable wrapped in the RPC's response type.
func (s *BusRouteserver) Daily(ctx context.Context, in *pb.Bus_Ask_Route) (*pb.Resp_BusDailyTimetable, error) {
	return s.BusDailytable(ctx, in)
}

// Eta implements the Bus_Route_Service Eta streaming RPC by delegating to
// BusRouteEta.
func (s *BusRouteserver) Eta(in *pb.Bus_Ask_Route, stream pb.Bus_Route_Service_EtaServer) error {
	return s.BusRouteEta(in, stream)
}

// BusRouteStatic returns the pre-serialized static payload for a bus route.
// The requested sub-route UID is used as-is: canonical subroute identity is
// produced at the 03:30 load (ADR-0006), so requests arrive already canonical
// and the router does no normalization. Results are memoized in the in-process
// cache for an hour; a missing row maps to NotFound via grpcStatusFor.
func (s *BusRouteserver) BusRouteStatic(ctx context.Context, in *pb.Bus_Ask_Route) (*pb.Resp_BusStatic, error) {
	log.Infof("call bus_static %s", in.SubRouteUID)
	route := in.SubRouteUID
	if s.cache != nil {
		if data, ok := s.cache.get("bus_static:" + route); ok {
			sub, err := DecodePayload(data, &pb.BusSubroute{})
			if err != nil {
				return nil, err
			}
			return &pb.Resp_BusStatic{Data: sub}, nil
		}
	}
	data, err := BusStaticPayload(ctx, s.db, route)
	if err != nil {
		log.Errorf("[gRPC] action=bus_static event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "route not found")
	}
	if s.cache != nil {
		s.cache.set("bus_static:"+route, data, time.Hour)
	}
	sub, err := DecodePayload(data, &pb.BusSubroute{})
	if err != nil {
		return nil, err
	}
	return &pb.Resp_BusStatic{Data: sub}, nil
}

// BusRouteEta streams live ETA for a bus route. It subscribes to the route's
// Redis channel first, then sends the current cached value (if any) so a new
// client sees state immediately, and forwards each published update until the
// client disconnects. Payloads failing usableBusEtaPayload are skipped.
func (s *BusRouteserver) BusRouteEta(in *pb.Bus_Ask_Route, stream pb.Bus_Route_Service_EtaServer) error {
	log.Infof("call Bus_route_eta %s", in.SubRouteUID)
	key := shared.BusRouteEtaKey(in.SubRouteUID)
	return StreamLive(stream.Context(), s.live, LiveStreamSpec{
		channel:  key,
		seedKeys: []string{key},
		usable:   usableBusEtaPayload,
	}, func(data []byte) error {
		arrival, err := DecodePayload(data, &pb.Bus_RouteArrival{})
		if err != nil {
			return err
		}
		return stream.Send(&pb.Resp_BusEta{Data: arrival})
	})
}

// streamBusStationEta streams live ETA for a station group. The request carries
// the group_uid and, optionally, its city; when the city is omitted it is looked
// up from bus_station_groups. It returns InvalidArgument when neither a city nor
// a resolvable group_uid is available. Like BusRouteEta it seeds the stream from
// the cached value, then forwards Redis Pub/Sub updates, skipping empty payloads.
// It lives as a free function over the query seam rather than as a method on
// either bus server, so it carries no server state beyond db and rc.
func streamBusStationEta(db CoreDB, live LiveSource, in *pb.Bus_Ask_StationGroup, stream pb.Bus_Station_Service_EtaServer) error {
	log.Infof("call Bus_station_eta %s:%s", in.City, in.GroupUid)
	groupUID := in.GroupUid
	if groupUID == "" {
		return status.Error(codes.InvalidArgument, "station eta key must include group_uid")
	}
	city := in.City
	if city == "" && db != nil {
		if dbCity, err := BusStationGroupCity(stream.Context(), db, groupUID); err == nil {
			city = dbCity
		}
	}
	if city == "" {
		return status.Error(codes.InvalidArgument, "station eta key must include city or known group_uid")
	}
	key := shared.BusStationEtaKey(city, groupUID)
	return StreamLive(stream.Context(), live, LiveStreamSpec{
		channel:  key,
		seedKeys: []string{key},
		usable:   usableBusEtaPayload,
	}, func(data []byte) error {
		arrival, err := DecodePayload(data, &pb.Bus_StationArrival{})
		if err != nil {
			return err
		}
		return stream.Send(&pb.Resp_BusStationEta{Data: arrival})
	})
}

// BusDailytable returns the daily timetable payload cached in Redis for a route.
// The sub-route UID is used as-is: canonical subroute identity is produced at
// the 03:30 load (ADR-0006), so requests arrive already canonical. A missing key
// maps to NotFound via grpcStatusFor.
func (s *BusRouteserver) BusDailytable(ctx context.Context, in *pb.Bus_Ask_Route) (*pb.Resp_BusDailyTimetable, error) {
	log.Infof("call Bus_dailytable %s", in.SubRouteUID)
	route := in.SubRouteUID
	val, err := s.rc.Get(ctx, shared.BusDailyTimetableKey(route)).Result()
	if err != nil {
		log.Errorf("[gRPC] action=bus_dailytable event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "timetable not found")
	}
	tt, err := DecodePayload([]byte(val), &pb.Bus_DailyTimetables{})
	if err != nil {
		return nil, err
	}
	return &pb.Resp_BusDailyTimetable{Data: tt}, nil
}

// Eta implements the Bus_Station_Service Eta streaming RPC by delegating to the
// shared streamBusStationEta helper.
func (s *BusStationserver) Eta(in *pb.Bus_Ask_StationGroup, stream pb.Bus_Station_Service_EtaServer) error {
	return streamBusStationEta(s.db, s.live, in, stream)
}

// Group returns a station group and its member stops from PostgreSQL. It
// returns InvalidArgument for an empty group_uid, NotFound when the group does
// not exist, and Internal for a transient query failure.
func (s *BusStationserver) Group(ctx context.Context, in *pb.Bus_Ask_StationGroup) (*pb.Bus_StationGroup, error) {
	groupUID := in.GroupUid
	if groupUID == "" {
		return nil, status.Error(codes.InvalidArgument, "group_uid required")
	}
	header, err := BusStationGroupHeader(ctx, s.db, groupUID)
	if err != nil {
		log.Errorf("[gRPC] action=bus_station_group event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "station group not found")
	}
	members, err := BusStationGroupMembers(ctx, s.db, groupUID)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "station group members: %v", err)
	}
	return &pb.Bus_StationGroup{
		GroupUid:    groupUID,
		GroupName:   header.GroupName,
		City:        header.City,
		PositionLon: header.Lon,
		PositionLat: header.Lat,
		Members:     members,
	}, nil
}

// Static implements the Bike_Service Static RPC by delegating to BikeStatic.
func (s *BikeServer) Static(ctx context.Context, in *pb.BikeRequest) (*pb.BikeStatic, error) {
	return s.BikeStatic(ctx, in)
}

// Eta implements the Bike_Service Eta streaming RPC by delegating to bikeEta.
func (s *BikeServer) Eta(in *pb.BikeRequest, stream pb.Bike_Service_EtaServer) error {
	return s.bikeEta(in, stream)
}

// BikeStatic returns static data for a bike station from PostgreSQL. Results are
// cached in-process for an hour as the marshaled protobuf; a corrupt cache entry
// that fails to unmarshal is ignored and re-fetched. A missing station maps to
// NotFound via grpcStatusFor.
func (s *BikeServer) BikeStatic(ctx context.Context, in *pb.BikeRequest) (*pb.BikeStatic, error) {
	log.Infof("call bike_static %s", in.StationUID)
	if s.cache != nil {
		if data, ok := s.cache.get("bike_static:" + in.StationUID); ok {
			var resp pb.BikeStatic
			if proto.Unmarshal(data, &resp) == nil {
				return &resp, nil
			}
		}
	}
	row, err := BikeStaticData(ctx, s.db, in.StationUID)
	if err != nil {
		log.Errorf("[gRPC] action=bike_static event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "bike station not found")
	}
	resp := &pb.BikeStatic{
		StationUID:  in.StationUID,
		Name:        row.Name,
		Capacity:    row.Capacity,
		ServiceType: row.ServiceType,
		Address:     row.Address,
	}
	// Left empty when the station landed without a point, so a client reads a
	// missing coordinate as missing rather than as the origin off West Africa.
	if row.Lat != nil && row.Lon != nil {
		resp.Lat = strconv.FormatFloat(*row.Lat, 'f', 6, 64)
		resp.Lon = strconv.FormatFloat(*row.Lon, 'f', 6, 64)
	}
	if s.cache != nil {
		if data, err := proto.Marshal(resp); err == nil {
			s.cache.set("bike_static:"+in.StationUID, data, time.Hour)
		}
	}
	return resp, nil
}

// bikeEta streams live availability for a bike station. It subscribes to the
// station's Redis channel first, seeds a new client from the cached value, then
// forwards published updates until the client disconnects. Empty payloads are
// skipped, so a client with no cached value receives no seed frame.
func (s *BikeServer) bikeEta(in *pb.BikeRequest, stream pb.Bike_Service_EtaServer) error {
	log.Infof("call bike_eta %s", in.StationUID)
	key := shared.BikeAvailabilityKey(in.StationUID)
	return StreamLive(stream.Context(), s.live, LiveStreamSpec{
		channel:  key,
		seedKeys: []string{key},
	}, func(data []byte) error {
		eta, err := DecodePayload(data, &pb.BikeEta{})
		if err != nil {
			return err
		}
		return stream.Send(&pb.Resp_BikeEta{Data: eta})
	})
}

// Eta implements the Mrt_Service Eta streaming RPC by delegating to MrtEta.
func (s *MrtServer) Eta(in *pb.AskMrt, stream pb.Mrt_Service_EtaServer) error {
	return s.MrtEta(in, stream)
}

// MrtEta streams metro arrivals for a station. Per-line arrivals are stored
// under separate mrt_live:<system>:<station>:<line> keys, so the stream first
// SCANs and sends the current value of every matching key to seed client state,
// then subscribes to the station channel and forwards live updates until the
// client disconnects.
//
// A transfer station reaches TDX as several station IDs (松江南京 is both G15 and
// O08), and the app merges them into one UI station whose ID joins the parts with
// "_". No TDX station ID contains an underscore, so a StationID is split back into
// its parts and each is streamed concurrently onto the one gRPC stream: a merged
// ID would otherwise seed and subscribe to a keyspace nothing ever writes, and the
// client would sit on an empty stream forever.
func (s *MrtServer) MrtEta(in *pb.AskMrt, stream pb.Mrt_Service_EtaServer) error {
	log.Infof("call Mrt_eta %s %s", in.System, in.StationID)

	// stream.Send is not safe for concurrent use, so the per-station streams
	// serialize their sends through one mutex.
	var mu sync.Mutex
	send := func(data []byte) error {
		live, err := DecodePayload(data, &pb.MrtLive{})
		if err != nil {
			return err
		}
		mu.Lock()
		defer mu.Unlock()
		return stream.Send(&pb.Resp_MrtEta{Data: live})
	}

	g, ctx := errgroup.WithContext(stream.Context())
	for _, station := range strings.Split(in.StationID, "_") {
		if station == "" {
			continue
		}
		g.Go(func() error {
			return StreamLive(ctx, s.live, LiveStreamSpec{
				channel:  shared.MrtLiveChannel(in.System, station),
				seedScan: shared.MrtLiveSeedPattern(in.System, station),
			}, send)
		})
	}
	return g.Wait()
}

// Delay implements the TRATimetableService Delay streaming RPC. The request
// carries no fields; it streams the system-wide TRA delay board via traDelay.
func (s *TraTimetableServer) Delay(_ *pb.AskRoute, stream pb.TRATimetableService_DelayServer) error {
	return s.traDelay(stream)
}

// Fare returns the adult TRA fares between two stations, one item per train
// class (see traAdultTicketTypes) priciest first, because a TRA fare depends on
// the class of train taken — the caller matches the item to its train rather
// than quoting a single price for the pair. This RPC reuses AskStaiton to carry
// the pair: StationId is the origin and Date is the destination station ID. It
// returns InvalidArgument when either is empty and NotFound when no fare exists.
func (s *TraTimetableServer) Fare(ctx context.Context, in *pb.AskStaiton) (*pb.TraFareItems, error) {
	if in.StationId == "" || in.Date == "" {
		return nil, status.Error(codes.InvalidArgument, "origin and destination are required")
	}
	req := &pb.AskRoute{
		OriginStationId:      in.StationId,
		DestinationStationId: in.Date,
	}
	resp, err := s.traFare(ctx, req)
	if err != nil {
		return nil, err
	}
	items := &pb.TraFareItems{}
	if err := proto.Unmarshal(resp.Data, items); err != nil {
		return nil, status.Errorf(codes.Internal, "decode fare: %v", err)
	}
	if len(items.Items) == 0 {
		return nil, status.Error(codes.NotFound, "fare not found")
	}
	return items, nil
}

// Timetable returns the TRA timetable between two stations for the requested
// date. It decodes the cached payload from traTimetable and returns NotFound
// when the decoded set is empty.
func (s *TraTimetableServer) Timetable(ctx context.Context, in *pb.AskRoute) (*pb.TraTimetables, error) {
	resp, err := s.traTimetable(ctx, in)
	if err != nil {
		return nil, err
	}
	items := &pb.TraTimetables{}
	if err := proto.Unmarshal(resp.Data, items); err != nil {
		return nil, status.Errorf(codes.Internal, "decode timetable: %v", err)
	}
	if len(items.Items) == 0 {
		return nil, status.Error(codes.NotFound, "timetable not found")
	}
	return items, nil
}

// traDelay streams the system-wide TRA delay board. It subscribes to the delay
// channel first, seeds a new client from the cached value, then forwards
// published updates until the client disconnects. An empty cached value is
// skipped rather than sent as a seed frame.
func (s *TraTimetableServer) traDelay(stream pb.TRATimetableService_DelayServer) error {
	log.Infof("call tra_delay")
	return StreamLive(stream.Context(), s.live, LiveStreamSpec{
		channel:  shared.TraDelayAllKey,
		seedKeys: []string{shared.TraDelayAllKey},
	}, func(data []byte) error {
		delays, err := DecodePayload(data, &pb.TraDelays{})
		if err != nil {
			return err
		}
		return stream.Send(&pb.RespTraDelay{Data: delays})
	})
}

// Delay implements the TRA_DetainService Delay streaming RPC, streaming delay
// updates for the single train identified by in.Trainno via traDdelay.
func (s *TraDetainServer) Delay(in *pb.AskDetain, stream pb.TRA_DetainService_DelayServer) error {
	return s.traDdelay(in, stream)
}

// Stops returns the stop times for one TRA train, decoding the cached payload
// produced by traStops.
func (s *TraDetainServer) Stops(ctx context.Context, in *pb.AskDetain) (*pb.TraStoptimes, error) {
	resp, err := s.traStops(ctx, in)
	if err != nil {
		return nil, err
	}
	items := &pb.TraStoptimes{}
	if err := proto.Unmarshal(resp.Data, items); err != nil {
		return nil, status.Errorf(codes.Internal, "decode stops: %v", err)
	}
	return items, nil
}

// traDdelay streams delay updates for the single train identified by in.Trainno.
// It subscribes to the train's Redis channel first, seeds a new client from the
// cached value, then forwards published updates until the client disconnects. An
// empty cached value is skipped rather than sent as a seed frame.
func (s *TraDetainServer) traDdelay(in *pb.AskDetain, stream pb.TRA_DetainService_DelayServer) error {
	log.Infof("call tra_delay %s", in.Trainno)
	// The realtime TRA job sets and publishes this key per train (traEta), so a
	// train absent from the current delay feed simply has no cached value and
	// the stream stays silent until one lands.
	key := shared.TraDelayTrainChannel(in.Trainno)
	return StreamLive(stream.Context(), s.live, LiveStreamSpec{
		channel:  key,
		seedKeys: []string{key},
	}, func(data []byte) error {
		delays, err := DecodePayload(data, &pb.TraDelays{})
		if err != nil {
			return err
		}
		return stream.Send(&pb.RespTraDelay{Data: delays})
	})
}

// Fare returns every THSR fare between two stations, one item per fare class
// (全票/半票) × cabin class (標準/商務/自由座), decoding the cached payload from
// thsrFare. The app picks the row matching the rider's 票種 preference and seat,
// so quoting a single row here would erase both axes. It returns NotFound when
// no fare exists.
func (s *ThsrServer) Fare(ctx context.Context, in *pb.Ask_Thsr) (*pb.ThsaFares, error) {
	req := &pb.AskRoute{
		OriginStationId:      in.OriginStationId,
		DestinationStationId: in.DestinationStationId,
	}
	resp, err := s.thsrFare(ctx, req)
	if err != nil {
		return nil, err
	}
	items := &pb.ThsaFares{}
	if err := proto.Unmarshal(resp.Data, items); err != nil {
		return nil, status.Errorf(codes.Internal, "decode fare: %v", err)
	}
	if len(items.Items) == 0 {
		return nil, status.Error(codes.NotFound, "fare not found")
	}
	return items, nil
}

// AvailableSeats streams THSR available-seat status for a date via the shared
// streamLive seam: it subscribes first, then seeds the client by SCANning the
// per-train thsr_seats:<date>:<train> keys, and forwards live updates until the
// client disconnects. The functions THSR-seats live job owns the refresh from
// TDX (ADR-0005 amendment), so the router only reads. The channel is the
// per-date thsr_seats:<date>:* string used as an opaque literal — both the
// functions writer and this reader derive it from shared.ThsrSeatsPattern, so a
// plain SUBSCRIBE/PUBLISH match with no pattern semantics. in.Date is parsed and
// reduced to a date so the seed and subscribe target the keys the job writes.
func (s *ThsrServer) AvailableSeats(in *pb.Ask_Thsr, stream grpc.ServerStreamingServer[pb.RespThsrSeats]) error {
	log.Infof("[gRPC] action=thsr_available_seats date=%s", in.Date)
	date := parseRailDate(in.Date).Format(time.DateOnly)
	return StreamLive(stream.Context(), s.live, LiveStreamSpec{
		channel:  shared.ThsrSeatsPattern(date),
		seedScan: shared.ThsrSeatsPattern(date),
	}, func(data []byte) error {
		seats, err := DecodePayload(data, &pb.ThsrAvailableSeats{})
		if err != nil {
			return err
		}
		return stream.Send(&pb.RespThsrSeats{Data: seats})
	})
}

// Timetable returns the THSR timetable between two stations for a date,
// decoding the cached payload produced by thsrTimetable.
func (s *ThsrServer) Timetable(ctx context.Context, in *pb.Ask_Thsr) (*pb.ThsrTimetables, error) {
	req := &pb.AskRoute{
		Date:                 in.Date,
		OriginStationId:      in.OriginStationId,
		DestinationStationId: in.DestinationStationId,
	}
	resp, err := s.thsrTimetable(ctx, req)
	if err != nil {
		return nil, err
	}
	items := &pb.ThsrTimetables{}
	if err := proto.Unmarshal(resp.Data, items); err != nil {
		return nil, status.Errorf(codes.Internal, "decode timetable: %v", err)
	}
	return items, nil
}

// Stops returns the stop times for one THSR train, decoding the cached payload
// produced by thsrStops.
func (s *ThsrDetainServer) Stops(ctx context.Context, in *pb.ThsrAskDetain) (*pb.ThsrStoptimes, error) {
	resp, err := s.thsrStops(ctx, in)
	if err != nil {
		return nil, err
	}
	items := &pb.ThsrStoptimes{}
	if err := proto.Unmarshal(resp.Data, items); err != nil {
		return nil, status.Errorf(codes.Internal, "decode stops: %v", err)
	}
	return items, nil
}

// Near implements the Near_Station_Service Near bidirectional RPC by delegating
// to FindNear.
func (s *NearServer) Near(stream pb.Near_Station_Service_NearServer) error {
	return s.FindNear(stream)
}

// latestNearRequest drains the request stream into a single-slot channel: a
// request that arrives while another is being computed replaces whatever is
// waiting behind it rather than queueing. A client panning the map is answered
// for where it stopped, and the intermediate viewports cost nothing.
//
// Callers must read the returned error only after the channel is closed; the
// close is what publishes it.
func latestNearRequest(stream pb.Near_Station_Service_NearServer) (<-chan *pb.Ask_Near, *error) {
	requests := make(chan *pb.Ask_Near, 1)
	var recvErr error
	go func() {
		defer close(requests)
		for {
			in, err := stream.Recv()
			if err != nil {
				if !errors.Is(err, io.EOF) {
					recvErr = err
				}
				return
			}
			// Sole producer, so the slot cannot refill between the drain and
			// the send and the send cannot block.
			select {
			case <-requests:
			default:
			}
			requests <- in
		}
	}()
	return requests, &recvErr
}

// FindNear is a bidirectional stream: for each location the client sends, it
// replies with nearby stations of every mode. Responses are not one-per-request
// — a viewport superseded before it was picked up is dropped, so a client must
// treat every response as "the newest answer" rather than the answer to a
// specific request it sent. It returns nil on client EOF.
func (s *NearServer) FindNear(stream pb.Near_Station_Service_NearServer) error {
	ctx := stream.Context()
	requests, recvErr := latestNearRequest(stream)
	for {
		var in *pb.Ask_Near
		select {
		case <-ctx.Done():
			return ctx.Err()
		case next, ok := <-requests:
			if !ok {
				return *recvErr
			}
			in = next
		}
		lon := in.PositionLon
		lat := in.PositionLat
		r := in.Radius
		log.Infof("[gRPC] received location: lon=%f lat=%f radius=%d", lon, lat, r)
		started := time.Now()
		resp, err := s.discovery.Discover(ctx, NearbyQuery{
			Origin: GeoPoint{Lon: lon, Lat: lat}, RadiusMeters: int(r),
		})
		// Server-side cost of one nearby query, so a slow first paint can be
		// attributed to the router or ruled out without a second round of logs.
		log.Infof("[NEAR] action=discover event=done elapsed_ms=%d", time.Since(started).Milliseconds())
		if err != nil {
			// A rejected query is the caller's bug, not the router's: it logs at
			// Warn so a stale client sending an out-of-range radius does not
			// raise a server-side error issue. The client clamps before sending
			// (kNearbyMaxRadiusMeters), so this only fires for old builds.
			if errors.Is(err, ErrInvalidNearbyQuery) {
				log.Warnf("[gRPC] action=nearby_discovery event=invalid error=%v", err)
				return status.Error(codes.InvalidArgument, err.Error())
			}
			log.Errorf("[gRPC] action=nearby_discovery failed error=%v", err)
			if errors.Is(err, ErrNearbyUnavailable) {
				return status.Error(codes.Unavailable, "nearby discovery unavailable")
			}
			return err
		}
		if err := stream.Send(resp); err != nil {
			log.Errorf("[gRPC] action=send_newdata failed error=%v", err)
			return err
		}
		log.Infof("[gRPC] action=send_newdata event=success")
	}
}
