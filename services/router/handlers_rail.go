package main

import (
	"context"
	"fmt"
	"time"

	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
)

// parseRailDate parses the app's 'yyyy-MM-dd' date strings, accepting RFC3339
// too for any legacy caller. Returns the zero time only when neither parses.
func parseRailDate(s string) time.Time {
	if t, err := time.Parse(time.DateOnly, s); err == nil {
		return t
	}
	t, _ := time.Parse(time.RFC3339, s)
	return t
}

const (
	// A station board is a glance, not a timetable: enough rows to cover the
	// next stretch at a busy station without making the rider wait for a day.
	stationBoardDefaultLimit = 20
	stationBoardMaxLimit     = 50
)

func stationBoardLimit(requested int32) int {
	switch {
	case requested <= 0:
		return stationBoardDefaultLimit
	case requested > stationBoardMaxLimit:
		return stationBoardMaxLimit
	default:
		return int(requested)
	}
}

// departuresAfter keeps the departures at or after the `HH:mm:ss` bound, which
// compares chronologically as a string because the field is zero-padded. An
// empty bound keeps the whole day. It always returns a fresh slice: the input
// is usually the cached day, and the caller appends to the result.
func departuresAfter[T interface{ GetDepartureTime() string }](items []T, after string) []T {
	out := make([]T, 0, len(items))
	for _, item := range items {
		if after == "" || item.GetDepartureTime() >= after {
			out = append(out, item)
		}
	}
	return out
}

// stationBoardWindow cuts the rider's window out of one service day, reaching
// for nextDay only when that day runs out before the limit — at 23:50 the two
// departures left are not an answer. A nextDay that fails is reported but not
// fatal: a short board beats an error the rider cannot act on.
func stationBoardWindow[T interface{ GetDepartureTime() string }](
	day []T,
	after string,
	limit int,
	nextDay func() ([]T, error),
) ([]T, error) {
	items := departuresAfter(day, after)
	var topUpErr error
	if len(items) < limit {
		next, err := nextDay()
		if err != nil {
			topUpErr = err
		} else {
			items = append(items, next...)
		}
	}
	if len(items) > limit {
		items = items[:limit]
	}
	return items, topUpErr
}

// traStationBoardDay serves one station/date/direction board from Redis,
// falling back to the loaded env schema on a miss. The cache holds the whole
// service day, so riders arriving at the station a minute apart share one
// entry and the window is cut per request. An empty day is not cached: it
// usually means the date has not landed yet, and a 1h negative entry would
// keep serving nothing for an hour after the loader fixes that.
func (s *Tra_TimetableServer) traStationBoardDay(ctx context.Context, station string, day time.Time, direction int32) ([]*pb.TraStationDeparture, error) {
	key := fmt.Sprintf("TRA_StationBoard:%s:%s:%d", day.Format(time.DateOnly), station, direction)
	if b, err := s.rc.Get(key).Bytes(); err == nil {
		board := &pb.TraStationBoard{}
		if err := proto.Unmarshal(b, board); err == nil {
			return board.Items, nil
		}
	}
	items, err := traStationBoardPayload(ctx, s.db, station, day, direction)
	if err != nil || len(items) == 0 {
		return nil, err
	}
	b, err := proto.Marshal(&pb.TraStationBoard{Items: items})
	if err != nil {
		return nil, err
	}
	if err := s.rc.Set(key, b, 1*time.Hour).Err(); err != nil {
		log.Errorf("[gRPC] action=tra_station_board event=cache_error error=%v", err)
	}
	return items, nil
}

// StationBoard returns the next departures from one TRA station in one
// direction. When the requested day is nearly out of trains it tops the list up
// from the next service date: at 23:50 the two departures left are not an
// answer. Every row carries its own TrainDate, so the app can tell the days
// apart. An empty result is NotFound (ADR-0005); it never fetches from TDX.
func (s *Tra_TimetableServer) StationBoard(ctx context.Context, in *pb.AskStationBoard) (*pb.TraStationBoard, error) {
	log.Infof("[gRPC] action=tra_station_board event=call station=%s direction=%d", in.StationId, in.Direction)
	if in.StationId == "" {
		return nil, status.Error(codes.InvalidArgument, "station is required")
	}
	day := parseRailDate(in.Date)
	if day.IsZero() {
		return nil, status.Error(codes.InvalidArgument, "date is required")
	}
	limit := stationBoardLimit(in.Limit)
	today, err := s.traStationBoardDay(ctx, in.StationId, day, in.Direction)
	if err != nil {
		log.Errorf("[gRPC] action=tra_station_board event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "station board not found")
	}
	items, topUpErr := stationBoardWindow(today, in.After, limit, func() ([]*pb.TraStationDeparture, error) {
		return s.traStationBoardDay(ctx, in.StationId, day.AddDate(0, 0, 1), in.Direction)
	})
	if topUpErr != nil {
		log.Errorf("[gRPC] action=tra_station_board event=topup_failed error=%v", topUpErr)
	}
	// NotFound means the day is not landed, not "no trains left": a landed day
	// whose remaining departures have all gone is a real answer of zero, and
	// the app tells the rider the day is over rather than that it is broken.
	if len(today) == 0 && len(items) == 0 {
		return nil, status.Error(codes.NotFound, "station board not found")
	}
	return &pb.TraStationBoard{Items: items}, nil
}

// thsrStationBoardDay is traStationBoardDay's THSR half; see it for why the
// whole day is cached and why an empty day is not.
func (s *ThsrServer) thsrStationBoardDay(ctx context.Context, station string, day time.Time, direction int32) ([]*pb.ThsrStationDeparture, error) {
	key := fmt.Sprintf("THSR_StationBoard:%s:%s:%d", day.Format(time.DateOnly), station, direction)
	if b, err := s.rc.Get(key).Bytes(); err == nil {
		board := &pb.ThsrStationBoard{}
		if err := proto.Unmarshal(b, board); err == nil {
			return board.Items, nil
		}
	}
	items, err := thsrStationBoardPayload(ctx, s.db, station, day, direction)
	if err != nil || len(items) == 0 {
		return nil, err
	}
	b, err := proto.Marshal(&pb.ThsrStationBoard{Items: items})
	if err != nil {
		return nil, err
	}
	if err := s.rc.Set(key, b, 1*time.Hour).Err(); err != nil {
		log.Errorf("[gRPC] action=thsr_station_board event=cache_error error=%v", err)
	}
	return items, nil
}

// StationBoard returns the next departures from one THSR station in one
// direction, with the same next-day top-up as the TRA board.
func (s *ThsrServer) StationBoard(ctx context.Context, in *pb.ThsrAskStationBoard) (*pb.ThsrStationBoard, error) {
	log.Infof("[gRPC] action=thsr_station_board event=call station=%s direction=%d", in.StationId, in.Direction)
	if in.StationId == "" {
		return nil, status.Error(codes.InvalidArgument, "station is required")
	}
	day := parseRailDate(in.Date)
	if day.IsZero() {
		return nil, status.Error(codes.InvalidArgument, "date is required")
	}
	limit := stationBoardLimit(in.Limit)
	today, err := s.thsrStationBoardDay(ctx, in.StationId, day, in.Direction)
	if err != nil {
		log.Errorf("[gRPC] action=thsr_station_board event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "station board not found")
	}
	items, topUpErr := stationBoardWindow(today, in.After, limit, func() ([]*pb.ThsrStationDeparture, error) {
		return s.thsrStationBoardDay(ctx, in.StationId, day.AddDate(0, 0, 1), in.Direction)
	})
	if topUpErr != nil {
		log.Errorf("[gRPC] action=thsr_station_board event=topup_failed error=%v", topUpErr)
	}
	// See the TRA board: NotFound is "not landed", an empty board is "the day
	// is over".
	if len(today) == 0 && len(items) == 0 {
		return nil, status.Error(codes.NotFound, "station board not found")
	}
	return &pb.ThsrStationBoard{Items: items}, nil
}

// traFare serves a TRA fare from Redis, falling back to the loaded env schema on
// a cache miss. Per ADR-0005 the router no longer fetches from TDX: if the loaded
// tables have no rows for the request (e.g. a date beyond the landed window), it
// returns codes.NotFound rather than triggering a fetch.
func (s *Tra_TimetableServer) traFare(ctx context.Context, in *pb.AskRoute) (*pb.Resp_Data, error) {
	log.Infof("[gRPC] action=tra_fare event=call origin=%s dest=%s", in.OriginStationId, in.DestinationStationId)
	// Key version (:v2) bumped when the payload widened from adult-only to every
	// 票種; without it the deploy would serve adult-only sets for a further 8h.
	key := fmt.Sprintf("TRA_Fare:v2:%s:%s", in.OriginStationId, in.DestinationStationId)
	if b, err := s.rc.Get(key).Bytes(); err == nil {
		return &pb.Resp_Data{Data: b}, nil
	}
	b, err := traFarePayload(ctx, s.db, in.OriginStationId, in.DestinationStationId)
	if err != nil {
		log.Errorf("[gRPC] action=tra_fare event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "fare not found")
	}
	if len(b) == 0 {
		return nil, status.Error(codes.NotFound, "fare not found")
	}
	if err := s.rc.Set(key, b, 8*time.Hour).Err(); err != nil {
		log.Errorf("[gRPC] action=tra_fare event=cache_error error=%v", err)
	}
	return &pb.Resp_Data{Data: b}, nil
}

// thsrFare serves a THSR fare from Redis, falling back to the loaded env schema
// on a cache miss. Per ADR-0005 the router no longer fetches from TDX: an empty
// result returns codes.NotFound.
func (s *ThsrServer) thsrFare(ctx context.Context, in *pb.AskRoute) (*pb.Resp_Data, error) {
	log.Infof("[gRPC] action=thsr_fare event=call origin=%s dest=%s", in.OriginStationId, in.DestinationStationId)
	// Key version (:v2) bumped for the same reason as TRA_Fare: the payload now
	// carries every fare class and cabin class, not just the standard adult seat.
	key := fmt.Sprintf("THSR_Fare:v2:%s:%s", in.OriginStationId, in.DestinationStationId)
	if b, err := s.rc.Get(key).Bytes(); err == nil {
		return &pb.Resp_Data{Data: b}, nil
	}
	items, err := queryThsrFares(ctx, s.db, in.OriginStationId, in.DestinationStationId)
	if err != nil {
		log.Errorf("[gRPC] action=thsr_fare event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "fare not found")
	}
	if len(items) == 0 {
		return nil, status.Error(codes.NotFound, "fare not found")
	}
	b, err := proto.Marshal(&pb.ThsaFares{Items: items})
	if err != nil {
		log.Errorf("[gRPC] action=thsr_fare event=marshal_error error=%v", err)
		return nil, grpcStatusFor(err, "fare not found")
	}
	if err := s.rc.Set(key, b, 1*time.Hour).Err(); err != nil {
		log.Errorf("[gRPC] action=thsr_fare event=cache_error error=%v", err)
	}
	return &pb.Resp_Data{Data: b}, nil
}

// traTimetable serves a TRA origin/destination timetable from Redis, falling back
// to the loaded env schema on a cache miss. Per ADR-0005 the router no longer
// fetches from TDX: an empty result returns codes.NotFound.
func (s *Tra_TimetableServer) traTimetable(ctx context.Context, in *pb.AskRoute) (*pb.Resp_Data, error) {
	log.Infof("[gRPC] action=tra_timetable event=call origin=%s dest=%s", in.OriginStationId, in.DestinationStationId)
	da := parseRailDate(in.Date)
	key := fmt.Sprintf("TRA_timetable:%s:%s:%s", da.Format(time.DateOnly), in.OriginStationId, in.DestinationStationId)
	if b, err := s.rc.Get(key).Bytes(); err == nil {
		return &pb.Resp_Data{Data: b}, nil
	}
	b, n, err := traTimetablePayload(ctx, s.db, in.OriginStationId, in.DestinationStationId, da)
	if err != nil {
		log.Errorf("[gRPC] action=tra_timetable event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "timetable not found")
	}
	if n == 0 {
		return nil, status.Error(codes.NotFound, "timetable not found")
	}
	if err := s.rc.Set(key, b, 1*time.Hour).Err(); err != nil {
		log.Errorf("[gRPC] action=tra_timetable event=cache_error error=%v", err)
	}
	return &pb.Resp_Data{Data: b}, nil
}

// thsrTimetable serves a THSR origin/destination timetable from Redis, falling
// back to the loaded env schema on a cache miss. Per ADR-0005 the router no
// longer fetches from TDX: an empty result returns codes.NotFound.
func (s *ThsrServer) thsrTimetable(ctx context.Context, in *pb.AskRoute) (*pb.Resp_Data, error) {
	log.Infof("[gRPC] action=thsr_timetable event=call origin=%s dest=%s", in.OriginStationId, in.DestinationStationId)
	da := parseRailDate(in.Date)
	key := fmt.Sprintf("THSR_timetable:%s:%s:%s", in.Date, in.OriginStationId, in.DestinationStationId)
	if b, err := s.rc.Get(key).Bytes(); err == nil {
		return &pb.Resp_Data{Data: b}, nil
	}
	b, n, err := thsrTimetablePayload(ctx, s.db, in.OriginStationId, in.DestinationStationId, da)
	if err != nil {
		log.Errorf("[gRPC] action=thsr_timetable event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "timetable not found")
	}
	if n == 0 {
		return nil, status.Error(codes.NotFound, "timetable not found")
	}
	if err := s.rc.Set(key, b, 1*time.Hour).Err(); err != nil {
		log.Errorf("[gRPC] action=thsr_timetable event=cache_error error=%v", err)
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
	da := parseRailDate(in.Date)
	b, n, err := traStoptimesPayload(ctx, s.db, in.Trainno, da.Format(time.DateOnly))
	if err != nil {
		log.Errorf("[gRPC] action=tra_stops event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "stops not found")
	}
	if n == 0 {
		return nil, status.Error(codes.NotFound, "stops not found")
	}
	if err := s.rc.Set(key, b, 1*time.Hour).Err(); err != nil {
		log.Errorf("[gRPC] action=tra_stops event=cache_error error=%v", err)
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
	da := parseRailDate(in.Date)
	b, n, err := thsrStoptimesPayload(ctx, s.db, in.Trainno, da.Format(time.DateOnly))
	if err != nil {
		log.Errorf("[gRPC] action=thsr_stops event=query_failed error=%v", err)
		return nil, grpcStatusFor(err, "stops not found")
	}
	if n == 0 {
		return nil, status.Error(codes.NotFound, "stops not found")
	}
	if err := s.rc.Set(key, b, 1*time.Hour).Err(); err != nil {
		log.Errorf("[gRPC] action=thsr_stops event=cache_error error=%v", err)
	}
	return &pb.Resp_Data{Data: b}, nil
}
