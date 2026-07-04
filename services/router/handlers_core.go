package main

import (
	"context"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/go-redis/redis"
	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
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
func (s *BusRouteserver) Daily(_ context.Context, in *pb.Bus_Ask_Route) (*pb.Resp_BusDailyTimetable, error) {
	resp, err := s.BusDailytable(in)
	if err != nil {
		return nil, err
	}
	return &pb.Resp_BusDailyTimetable{Data: resp.Data}, nil
}

// Eta implements the Bus_Route_Service Eta streaming RPC by delegating to
// BusRouteEta.
func (s *BusRouteserver) Eta(in *pb.Bus_Ask_Route, stream pb.Bus_Route_Service_EtaServer) error {
	return s.BusRouteEta(in, stream)
}

// BusRouteStatic returns the pre-serialized static payload for a bus route.
// The requested sub-route UID is normalized with makethatsame so THB direction
// variants collapse to one row. Results are memoized in the in-process cache for
// an hour; a missing row maps to NotFound via grpcStatusFor.
func (s *BusRouteserver) BusRouteStatic(ctx context.Context, in *pb.Bus_Ask_Route) (*pb.Resp_BusStatic, error) {
	log.Infof("call bus_static %s", in.SubRouteUID)
	route := makethatsame(in.SubRouteUID)
	if s.cache != nil {
		if data, ok := s.cache.get("bus_static:" + route); ok {
			return &pb.Resp_BusStatic{Data: data}, nil
		}
	}
	var data []byte
	err := s.db.QueryRow(ctx, `SELECT pb FROM bus_static WHERE sub_route_uid = $1;`, route).Scan(&data)
	if err != nil {
		log.Infof("[gRPC] action=bus_static event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "route not found")
	}
	if s.cache != nil {
		s.cache.set("bus_static:"+route, data, time.Hour)
	}
	return &pb.Resp_BusStatic{Data: data}, nil
}

// BusRouteEta streams live ETA for a bus route. It subscribes to the route's
// Redis channel first, then sends the current cached value (if any) so a new
// client sees state immediately, and forwards each published update until the
// client disconnects. Payloads failing usableBusEtaPayload are skipped.
func (s *BusRouteserver) BusRouteEta(in *pb.Bus_Ask_Route, stream pb.Bus_Route_Service_EtaServer) error {
	log.Infof("call Bus_route_eta %s", in.SubRouteUID)
	key := busRouteEtaKey(in.SubRouteUID)
	return streamLive(stream.Context(), redisLiveSource{s.rc}, liveStreamSpec{
		channel:  key,
		seedKeys: []string{key},
		usable:   usableBusEtaPayload,
	}, func(data []byte) error {
		return stream.Send(&pb.Resp_BusEta{Data: data})
	})
}

// BusStationEta streams live ETA for a station group. The request's SubRouteUID
// field carries a "city:group_uid" pair; when the city is omitted it is looked
// up from bus_station_groups. It returns InvalidArgument when neither a city nor
// a resolvable group_uid is available. Like BusRouteEta it seeds the stream from
// the cached value, then forwards Redis Pub/Sub updates, skipping empty payloads.
func (s *BusRouteserver) BusStationEta(in *pb.Bus_Ask_Route, stream pb.Bus_Station_Service_EtaServer) error {
	log.Infof("call Bus_station_eta %s", in.SubRouteUID)
	city, groupUID, ok := strings.Cut(in.SubRouteUID, ":")
	if !ok {
		groupUID = in.SubRouteUID
	}
	if groupUID == "" {
		return status.Error(codes.InvalidArgument, "station eta key must include group_uid")
	}
	if city == "" && s.db != nil {
		var dbCity string
		if err := s.db.QueryRow(stream.Context(), `SELECT city FROM bus_station_groups WHERE group_uid = $1`, groupUID).Scan(&dbCity); err == nil {
			city = dbCity
		}
	}
	if city == "" {
		return status.Error(codes.InvalidArgument, "station eta key must include city or known group_uid")
	}
	key := fmt.Sprintf("bus_eta_station:%s:%s", city, groupUID)
	return streamLive(stream.Context(), redisLiveSource{s.rc}, liveStreamSpec{
		channel:  key,
		seedKeys: []string{key},
		usable:   usableBusEtaPayload,
	}, func(data []byte) error {
		return stream.Send(&pb.Resp_BusEta{Data: data})
	})
}

// BusDailytable returns the daily timetable payload cached in Redis for a route.
// The sub-route UID is normalized with makethatsame; a missing key maps to
// NotFound via grpcStatusFor.
func (s *BusRouteserver) BusDailytable(in *pb.Bus_Ask_Route) (*pb.Resp_BusEta, error) {
	log.Infof("call Bus_route_eta %s", in.SubRouteUID)
	route := makethatsame(in.SubRouteUID)
	val, err := s.rc.Get(fmt.Sprintf("bus_daily_timetable:%s", route)).Result()
	if err != nil {
		log.Infof("[gRPC] action=bus_dailytable event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "timetable not found")
	}
	resp := &pb.Resp_BusEta{
		Data: []byte(val),
	}
	return resp, nil
}

// Eta implements the Bus_Station_Service Eta streaming RPC. The station-ETA
// logic lives on BusRouteserver, so it forwards to a transient BusRouteserver
// sharing this server's db and rc handles (no cache is needed for a stream).
func (s *BusStationserver) Eta(in *pb.Bus_Ask_Route, stream pb.Bus_Station_Service_EtaServer) error {
	return (&BusRouteserver{db: s.db, rc: s.rc}).BusStationEta(in, stream)
}

// Group returns a station group and its member stops from PostgreSQL. It
// returns InvalidArgument for an empty group_uid and NotFound when the group
// does not exist.
func (s *BusStationserver) Group(ctx context.Context, in *pb.Bus_Ask_Route) (*pb.Bus_StationGroup, error) {
	groupUID := in.SubRouteUID
	if groupUID == "" {
		return nil, status.Error(codes.InvalidArgument, "group_uid required")
	}
	resp := &pb.Bus_StationGroup{GroupUid: groupUID}
	err := s.db.QueryRow(ctx, `
		SELECT group_name, city, ST_X(position), ST_Y(position)
		FROM bus_station_groups
		WHERE group_uid = $1`, groupUID).Scan(&resp.GroupName, &resp.City, &resp.PositionLon, &resp.PositionLat)
	if err != nil {
		return nil, status.Errorf(codes.NotFound, "station group not found: %s", groupUID)
	}
	rows, err := s.db.Query(ctx, `
		SELECT station_uid, station_id, station_name, ST_X(position), ST_Y(position)
		FROM bus_station_group_members
		WHERE group_uid = $1
		ORDER BY station_id, station_uid`, groupUID)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "station group members: %v", err)
	}
	defer rows.Close()
	for rows.Next() {
		m := &pb.Bus_StationGroupMember{}
		if err := rows.Scan(&m.StationUid, &m.StationId, &m.StationName, &m.PositionLon, &m.PositionLat); err != nil {
			return nil, status.Errorf(codes.Internal, "scan station group member: %v", err)
		}
		resp.Members = append(resp.Members, m)
	}
	return resp, nil
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
	var name, address string
	var capacity, serviceType int32
	err := s.db.QueryRow(ctx, `SELECT name,capacity,service_type,address FROM bike_stations WHERE station_uid = $1;`, in.StationUID).Scan(&name, &capacity, &serviceType, &address)
	if err != nil {
		log.Infof("[gRPC] action=bike_static event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "bike station not found")
	}
	resp := &pb.BikeStatic{
		StationUID:  in.StationUID,
		Name:        name,
		Capacity:    capacity,
		ServiceType: serviceType,
		Address:     address,
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
	key := fmt.Sprintf("bike_availability:%s", in.StationUID)
	return streamLive(stream.Context(), redisLiveSource{s.rc}, liveStreamSpec{
		channel:  key,
		seedKeys: []string{key},
	}, func(data []byte) error {
		return stream.Send(&pb.Resp_BikeEta{Data: data})
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
func (s *MrtServer) MrtEta(in *pb.AskMrt, stream pb.Mrt_Service_EtaServer) error {
	log.Infof("call Mrt_eta %s %s", in.System, in.StationID)
	channel := fmt.Sprintf("mrt_live:%s:%s", in.System, in.StationID)
	return streamLive(stream.Context(), redisLiveSource{s.rc}, liveStreamSpec{
		channel:  channel,
		seedScan: channel + ":*",
	}, func(data []byte) error {
		return stream.Send(&pb.Resp_MrtEta{Data: data})
	})
}

// LiveBoard implements the TRAStationService LiveBoard streaming RPC by
// delegating to traLiveboard.
func (s *Tra_StationServer) LiveBoard(in *pb.AskStaiton, stream pb.TRAStationService_LiveBoardServer) error {
	return s.traLiveboard(in, stream)
}

// traLiveboard streams the TRA live board for a station. It subscribes to the
// station's Redis channel first, seeds a new client from the cached value, then
// forwards published updates until the client disconnects. An empty cached value
// is skipped rather than sent as a seed frame.
func (s *Tra_StationServer) traLiveboard(in *pb.AskStaiton, stream pb.TRAStationService_LiveBoardServer) error {
	log.Infof("call tra_liveboard %s", in.StationId)
	key := fmt.Sprintf("tra:liveboard:%s", in.StationId)
	return streamLive(stream.Context(), redisLiveSource{s.rc}, liveStreamSpec{
		channel:  key,
		seedKeys: []string{key},
	}, func(data []byte) error {
		return stream.Send(&pb.RespTraLiveBoard{Data: data})
	})
}

// Delay implements the TRATimetableService Delay streaming RPC. The request
// carries no fields; it streams the system-wide TRA delay board via traDelay.
func (s *Tra_TimetableServer) Delay(_ *pb.AskRoute, stream pb.TRATimetableService_DelayServer) error {
	return s.traDelay(stream)
}

// Fare returns the single lowest TRA fare item between two stations. This RPC
// reuses AskStaiton to carry the pair: StationId is the origin and Date is the
// destination station ID. It returns InvalidArgument when either is empty and
// NotFound when no fare exists.
func (s *Tra_TimetableServer) Fare(ctx context.Context, in *pb.AskStaiton) (*pb.TraFareItem, error) {
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
	return items.Items[0], nil
}

// Timetable returns the TRA timetable between two stations for the requested
// date. It decodes the cached payload from traTimetable and returns NotFound
// when the decoded set is empty.
func (s *Tra_TimetableServer) Timetable(ctx context.Context, in *pb.AskRoute) (*pb.TraTimetables, error) {
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
func (s *Tra_TimetableServer) traDelay(stream pb.TRATimetableService_DelayServer) error {
	log.Infof("call tra_delay")
	return streamLive(stream.Context(), redisLiveSource{s.rc}, liveStreamSpec{
		channel:  "tra:delay:all",
		seedKeys: []string{"tra:delay:all"},
	}, func(data []byte) error {
		return stream.Send(&pb.RespTraDelay{Data: data})
	})
}

// Delay implements the TRA_DetainService Delay streaming RPC, streaming delay
// updates for the single train identified by in.Trainno via traDdelay.
func (s *Tra_DetainServer) Delay(in *pb.AskDetain, stream pb.TRA_DetainService_DelayServer) error {
	return s.traDdelay(in, stream)
}

// Stops returns the stop times for one TRA train, decoding the cached payload
// produced by traStops.
func (s *Tra_DetainServer) Stops(ctx context.Context, in *pb.AskDetain) (*pb.TraStoptimes, error) {
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
func (s *Tra_DetainServer) traDdelay(in *pb.AskDetain, stream pb.TRA_DetainService_DelayServer) error {
	log.Infof("call tra_delay %s", in.Trainno)
	key := fmt.Sprintf("tra:delay:%s", in.Trainno)
	return streamLive(stream.Context(), redisLiveSource{s.rc}, liveStreamSpec{
		channel:  key,
		seedKeys: []string{key},
	}, func(data []byte) error {
		return stream.Send(&pb.RespTraDelay{Data: data})
	})
}

// Fare returns the single lowest THSR fare item between two stations, decoding
// the cached payload from thsrFare. It returns NotFound when no fare exists.
func (s *ThsrServer) Fare(ctx context.Context, in *pb.Ask_Thsr) (*pb.ThsaFare, error) {
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
	return items.Items[0], nil
}

// AvailableSeats streams THSR available-seat status for a date. Seat status per
// train is cached under thsr_seats:<date>:<train> keys, so it first SCANs and
// sends every existing key. When the scan completes with no more keys, it
// triggers get_thsr_availableseatstatus to refresh the cache from TDX, then
// PSubscribes and forwards live updates until the client disconnects. in.Date is
// parsed as RFC3339 and reduced to a date for the TDX refresh.
func (s *ThsrServer) AvailableSeats(in *pb.Ask_Thsr, stream grpc.ServerStreamingServer[pb.RespThsrSeats]) error {
	log.Infof("[gRPC] action=thsr_available_seats date=%s", in.Date)
	channel := fmt.Sprintf("thsr_seats:%s:*", in.Date)
	var cursor uint64
	for {
		if err := stream.Context().Err(); err != nil {
			return err
		}
		keys, next, err := s.rc.Scan(cursor, channel, 20).Result()
		if err != nil {
			break
		}
		for _, i := range keys {
			val, err := s.rc.Get(i).Bytes()
			if err != nil {
				continue
			}
			resp := &pb.RespThsrSeats{Data: val}
			if err = stream.Send(resp); err != nil {
				return err
			}
		}
		cursor = next
		if cursor == 0 {
			t, _ := time.Parse(time.RFC3339, in.Date)
			get_thsr_availableseatstatus(s.client, s.rc, t.Format(time.DateOnly))
			break
		}
	}
	sub := s.rc.PSubscribe(fmt.Sprintf("thsr_seats:%s:*", in.Date))
	defer func(sub *redis.PubSub) { _ = sub.Close() }(sub)
	for {
		select {
		case <-stream.Context().Done():
			return stream.Context().Err()
		default:
		}
		m, err := sub.ReceiveMessage()
		if err != nil {
			return err
		}
		resp := &pb.RespThsrSeats{Data: []byte(m.Payload)}
		if err = stream.Send(resp); err != nil {
			return err
		}
	}
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
func (s *Thsr_DetainServer) Stops(ctx context.Context, in *pb.ThsrAskDetain) (*pb.ThsrStoptimes, error) {
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
func (s *Near_Server) Near(stream pb.Near_Station_Service_NearServer) error {
	return s.FindNear(stream)
}

// FindNear is a bidirectional stream: for each location the client sends, it
// replies with nearby stations of every mode. It returns nil on client EOF.
// Note findnearstation takes (lat, lon), so the received lon/lat are passed in
// swapped order.
func (s *Near_Server) FindNear(stream pb.Near_Station_Service_NearServer) error {
	ctx := stream.Context()
	var l1, l2 float64
	var l3 int
	for {
		in, err := stream.Recv()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		lon := in.PositionLon
		lat := in.PositionLat
		r := in.Radius
		l1 = lon
		l2 = lat
		l3 = int(r)
		log.Infof("[gRPC] received location: lon=%f lat=%f radius=%d", lon, lat, r)
		resp, err := findnearstation(l2, l1, l3, ctx, s.db, s.osrmClient)
		if err != nil {
			log.Infof("[gRPC] action=findnearstation failed error=%v", err)
			return err
		}
		if err := stream.Send(resp); err != nil {
			log.Infof("[gRPC] action=send_newdata failed error=%v", err)
			return err
		}
		log.Infof("[gRPC] action=send_newdata event=success")
	}
}
