package main

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/go-redis/redis"
	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
)

func (s *Tra_TimetableServer) traFare(ctx context.Context, in *pb.AskRoute) (*pb.Resp_Data, error) {
	log.Infof("call tra fare")
	key := fmt.Sprintf("TRA_Fare:%s:%s", in.OriginStationId, in.DestinationStationId)
	val := s.rc.Get(key)
	if errors.Is(val.Err(), redis.Nil) {
		fetchOnce(key, func() {
			tra_price(ctx, in.OriginStationId, in.DestinationStationId, s.client, s.db, s.rc)
		})
		val = s.rc.Get(key)
	}
	if val.Err() != nil {
		log.Infof("[gRPC] action=tra_fare event=query_failed error=%v", val.Err())
		return nil, grpcStatusFor(val.Err(), "fare not found")
	}
	res, _ := val.Result()
	resp := &pb.Resp_Data{
		Data: []byte(res),
	}
	return resp, nil
}

func (s *ThsrServer) thsrFare(ctx context.Context, in *pb.AskRoute) (*pb.Resp_Data, error) {
	log.Infof("call thsr fare")
	key := fmt.Sprintf("THSR_Fare:%s:%s", in.OriginStationId, in.DestinationStationId)
	val := s.rc.Get(key)
	if errors.Is(val.Err(), redis.Nil) {
		fetchOnce(key, func() {
			thsr_price(ctx, in.OriginStationId, in.DestinationStationId, s.client, s.db, s.rc)
		})
		val = s.rc.Get(key)
	}
	if val.Err() != nil {
		log.Infof("[gRPC] action=thsr_fare event=query_failed error=%v", val.Err())
		return nil, grpcStatusFor(val.Err(), "fare not found")
	}
	res, _ := val.Result()
	resp := &pb.Resp_Data{
		Data: []byte(res),
	}
	return resp, nil
}

func (s *Tra_TimetableServer) traTimetable(ctx context.Context, in *pb.AskRoute) (*pb.Resp_Data, error) {
	log.Infof("call tra timetable %s %s", in.OriginStationId, in.DestinationStationId)
	da, _ := time.Parse(time.RFC3339, in.Date)
	key := fmt.Sprintf("TRA_timetable:%s:%s:%s", da.Format(time.DateOnly), in.OriginStationId, in.DestinationStationId)
	val := s.rc.Get(key)
	if errors.Is(val.Err(), redis.Nil) {
		t, _ := time.Parse(time.RFC3339, in.Date)
		fetchOnce(key, func() {
			tra_timetable(ctx, in.OriginStationId, in.DestinationStationId, t, s.client, s.db, s.rc)
		})
		val = s.rc.Get(key)
	}
	if val.Err() != nil {
		log.Infof("[gRPC] action=tra_timetable event=query_failed error=%v", val.Err())
		return nil, grpcStatusFor(val.Err(), "timetable not found")
	}
	res, _ := val.Result()
	resp := &pb.Resp_Data{
		Data: []byte(res),
	}
	return resp, nil
}

func (s *ThsrServer) thsrTimetable(ctx context.Context, in *pb.AskRoute) (*pb.Resp_Data, error) {
	log.Infof("call thsr timetable %s %s", in.OriginStationId, in.DestinationStationId)
	key := fmt.Sprintf("THSR_timetable:%s:%s:%s", in.Date, in.OriginStationId, in.DestinationStationId)
	val := s.rc.Get(key)
	if errors.Is(val.Err(), redis.Nil) {
		t, _ := time.Parse(time.RFC3339, in.Date)
		fetchOnce(key, func() {
			thsr_timetable(ctx, in.OriginStationId, in.DestinationStationId, t, s.client, s.db, s.rc)
		})
		val = s.rc.Get(key)
	}
	if val.Err() != nil {
		log.Infof("[gRPC] action=thsr_timetable event=query_failed error=%v", val.Err())
		return nil, grpcStatusFor(val.Err(), "timetable not found")
	}
	res, _ := val.Result()
	resp := &pb.Resp_Data{
		Data: []byte(res),
	}
	return resp, nil
}

func (s *Tra_DetainServer) traStops(ctx context.Context, in *pb.AskDetain) (*pb.Resp_Data, error) {
	log.Infof("call tra stops %s", in.Trainno)
	key := fmt.Sprintf("TRA_Stoptimes:%s:%s", in.Date, in.Trainno)
	val := s.rc.Get(key)
	if errors.Is(val.Err(), redis.Nil) {
		t, _ := time.Parse(time.RFC3339, in.Date)
		fetchOnce(key, func() {
			tra_stoptimes(ctx, in.Trainno, t, s.client, s.db, s.rc)
		})
		val = s.rc.Get(key)
	}
	if val.Err() != nil {
		log.Infof("[gRPC] action=stops event=query_failed error=%v", val.Err())
		return nil, grpcStatusFor(val.Err(), "stops not found")
	}
	res, _ := val.Result()
	resp := &pb.Resp_Data{
		Data: []byte(res),
	}
	return resp, nil
}

func (s *Thsr_DetainServer) thsrStops(ctx context.Context, in *pb.ThsrAskDetain) (*pb.Resp_Data, error) {
	log.Infof("call thsr stops %s", in.Trainno)
	key := fmt.Sprintf("THSR_Stoptimes:%s:%s", in.Date, in.Trainno)
	val := s.rc.Get(key)
	if errors.Is(val.Err(), redis.Nil) {
		t, _ := time.Parse(time.RFC3339, in.Date)
		fetchOnce(key, func() {
			thsr_stoptimes(ctx, in.Trainno, t, s.client, s.db, s.rc)
		})
		val = s.rc.Get(key)
	}
	if val.Err() != nil {
		log.Infof("[gRPC] action=stops event=query_failed error=%v", val.Err())
		return nil, grpcStatusFor(val.Err(), "stops not found")
	}
	res, _ := val.Result()
	resp := &pb.Resp_Data{
		Data: []byte(res),
	}
	return resp, nil
}
