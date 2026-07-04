package main

import (
	"context"
	"fmt"
	"time"

	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
)

// traFare serves a TRA fare from Redis, falling back to the loaded env schema on
// a cache miss. Per ADR-0005 the router no longer fetches from TDX: if the loaded
// tables have no rows for the request (e.g. a date beyond the landed window), it
// returns codes.NotFound rather than triggering a fetch.
func (s *Tra_TimetableServer) traFare(ctx context.Context, in *pb.AskRoute) (*pb.Resp_Data, error) {
	log.Infof("[gRPC] action=tra_fare event=call origin=%s dest=%s", in.OriginStationId, in.DestinationStationId)
	key := fmt.Sprintf("TRA_Fare:%s:%s", in.OriginStationId, in.DestinationStationId)
	if b, err := s.rc.Get(key).Bytes(); err == nil {
		return &pb.Resp_Data{Data: b}, nil
	}
	b, err := traFarePayload(ctx, s.db, in.OriginStationId, in.DestinationStationId)
	if err != nil {
		log.Infof("[gRPC] action=tra_fare event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "fare not found")
	}
	if len(b) == 0 {
		return nil, status.Error(codes.NotFound, "fare not found")
	}
	if err := s.rc.Set(key, b, 8*time.Hour).Err(); err != nil {
		log.Infof("[gRPC] action=tra_fare event=cache_error error=%v", err)
	}
	return &pb.Resp_Data{Data: b}, nil
}

// thsrFare serves a THSR fare from Redis, falling back to the loaded env schema
// on a cache miss. Per ADR-0005 the router no longer fetches from TDX: an empty
// result returns codes.NotFound.
func (s *ThsrServer) thsrFare(ctx context.Context, in *pb.AskRoute) (*pb.Resp_Data, error) {
	log.Infof("[gRPC] action=thsr_fare event=call origin=%s dest=%s", in.OriginStationId, in.DestinationStationId)
	key := fmt.Sprintf("THSR_Fare:%s:%s", in.OriginStationId, in.DestinationStationId)
	if b, err := s.rc.Get(key).Bytes(); err == nil {
		return &pb.Resp_Data{Data: b}, nil
	}
	items, err := queryThsrFares(ctx, s.db, in.OriginStationId, in.DestinationStationId)
	if err != nil {
		log.Infof("[gRPC] action=thsr_fare event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "fare not found")
	}
	if len(items) == 0 {
		return nil, status.Error(codes.NotFound, "fare not found")
	}
	b, err := proto.Marshal(&pb.ThsaFares{Items: items})
	if err != nil {
		log.Infof("[gRPC] action=thsr_fare event=marshal_error error=%v", err)
		return nil, grpcStatusFor(err, "fare not found")
	}
	if err := s.rc.Set(key, b, 1*time.Hour).Err(); err != nil {
		log.Infof("[gRPC] action=thsr_fare event=cache_error error=%v", err)
	}
	return &pb.Resp_Data{Data: b}, nil
}

// traTimetable serves a TRA origin/destination timetable from Redis, falling back
// to the loaded env schema on a cache miss. Per ADR-0005 the router no longer
// fetches from TDX: an empty result returns codes.NotFound.
func (s *Tra_TimetableServer) traTimetable(ctx context.Context, in *pb.AskRoute) (*pb.Resp_Data, error) {
	log.Infof("[gRPC] action=tra_timetable event=call origin=%s dest=%s", in.OriginStationId, in.DestinationStationId)
	da, _ := time.Parse(time.RFC3339, in.Date)
	key := fmt.Sprintf("TRA_timetable:%s:%s:%s", da.Format(time.DateOnly), in.OriginStationId, in.DestinationStationId)
	if b, err := s.rc.Get(key).Bytes(); err == nil {
		return &pb.Resp_Data{Data: b}, nil
	}
	b, n, err := traTimetablePayload(ctx, s.db, in.OriginStationId, in.DestinationStationId, da)
	if err != nil {
		log.Infof("[gRPC] action=tra_timetable event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "timetable not found")
	}
	if n == 0 {
		return nil, status.Error(codes.NotFound, "timetable not found")
	}
	if err := s.rc.Set(key, b, 1*time.Hour).Err(); err != nil {
		log.Infof("[gRPC] action=tra_timetable event=cache_error error=%v", err)
	}
	return &pb.Resp_Data{Data: b}, nil
}

// thsrTimetable serves a THSR origin/destination timetable from Redis, falling
// back to the loaded env schema on a cache miss. Per ADR-0005 the router no
// longer fetches from TDX: an empty result returns codes.NotFound.
func (s *ThsrServer) thsrTimetable(ctx context.Context, in *pb.AskRoute) (*pb.Resp_Data, error) {
	log.Infof("[gRPC] action=thsr_timetable event=call origin=%s dest=%s", in.OriginStationId, in.DestinationStationId)
	da, _ := time.Parse(time.RFC3339, in.Date)
	key := fmt.Sprintf("THSR_timetable:%s:%s:%s", in.Date, in.OriginStationId, in.DestinationStationId)
	if b, err := s.rc.Get(key).Bytes(); err == nil {
		return &pb.Resp_Data{Data: b}, nil
	}
	b, n, err := thsrTimetablePayload(ctx, s.db, in.OriginStationId, in.DestinationStationId, da)
	if err != nil {
		log.Infof("[gRPC] action=thsr_timetable event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "timetable not found")
	}
	if n == 0 {
		return nil, status.Error(codes.NotFound, "timetable not found")
	}
	if err := s.rc.Set(key, b, 1*time.Hour).Err(); err != nil {
		log.Infof("[gRPC] action=thsr_timetable event=cache_error error=%v", err)
	}
	return &pb.Resp_Data{Data: b}, nil
}

// traStops serves a TRA train's stop times from Redis, falling back to the loaded
// env schema on a cache miss. Per ADR-0005 the router no longer fetches from TDX:
// an empty result returns codes.NotFound.
func (s *Tra_DetainServer) traStops(ctx context.Context, in *pb.AskDetain) (*pb.Resp_Data, error) {
	log.Infof("[gRPC] action=tra_stops event=call train=%s", in.Trainno)
	key := fmt.Sprintf("TRA_Stoptimes:%s:%s", in.Date, in.Trainno)
	if b, err := s.rc.Get(key).Bytes(); err == nil {
		return &pb.Resp_Data{Data: b}, nil
	}
	da, _ := time.Parse(time.RFC3339, in.Date)
	b, n, err := traStoptimesPayload(ctx, s.db, in.Trainno, da.Format(time.DateOnly))
	if err != nil {
		log.Infof("[gRPC] action=tra_stops event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "stops not found")
	}
	if n == 0 {
		return nil, status.Error(codes.NotFound, "stops not found")
	}
	if err := s.rc.Set(key, b, 1*time.Hour).Err(); err != nil {
		log.Infof("[gRPC] action=tra_stops event=cache_error error=%v", err)
	}
	return &pb.Resp_Data{Data: b}, nil
}

// thsrStops serves a THSR train's stop times from Redis, falling back to the
// loaded env schema on a cache miss. Per ADR-0005 the router no longer fetches
// from TDX: an empty result returns codes.NotFound.
func (s *Thsr_DetainServer) thsrStops(ctx context.Context, in *pb.ThsrAskDetain) (*pb.Resp_Data, error) {
	log.Infof("[gRPC] action=thsr_stops event=call train=%s", in.Trainno)
	key := fmt.Sprintf("THSR_Stoptimes:%s:%s", in.Date, in.Trainno)
	if b, err := s.rc.Get(key).Bytes(); err == nil {
		return &pb.Resp_Data{Data: b}, nil
	}
	da, _ := time.Parse(time.RFC3339, in.Date)
	b, n, err := thsrStoptimesPayload(ctx, s.db, in.Trainno, da.Format(time.DateOnly))
	if err != nil {
		log.Infof("[gRPC] action=thsr_stops event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "stops not found")
	}
	if n == 0 {
		return nil, status.Error(codes.NotFound, "stops not found")
	}
	if err := s.rc.Set(key, b, 1*time.Hour).Err(); err != nil {
		log.Infof("[gRPC] action=thsr_stops event=cache_error error=%v", err)
	}
	return &pb.Resp_Data{Data: b}, nil
}
