package main

import (
	"github.com/go-redis/redis"
	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/grpc"
)

// AlertServer streams service alerts that the functions/MQTT subscriber
// publishes into Redis. Each alert channel is also mirrored to a plain Redis
// key holding the latest payload, so a new subscriber can be sent the current
// state before live updates begin.
type AlertServer struct {
	pb.UnimplementedAlert_ServiceServer
	rc *redis.Client
}

// BusNews streams bus service-news alerts for the requested city. The city is
// interpolated into the Redis channel name, so an empty city subscribes to a
// channel that never receives messages.
func (s *AlertServer) BusNews(in *pb.Alert_Bus_Ask, stream grpc.ServerStreamingServer[pb.Alert_Msg]) error {
	key := shared.AlertBusNewsChannel(in.City)
	return streamAlert(s.rc, key, stream)
}

// MetroAlert streams metro alerts for the requested rail system (e.g. TRTC,
// KRTC). The system code is interpolated into the Redis channel name.
func (s *AlertServer) MetroAlert(in *pb.Alert_Metro_Ask, stream grpc.ServerStreamingServer[pb.Alert_Msg]) error {
	key := shared.AlertMetroChannel(in.System)
	return streamAlert(s.rc, key, stream)
}

// TraAlert streams TRA (conventional rail) alerts. The request carries no
// parameters; all TRA alerts share one channel.
func (s *AlertServer) TraAlert(_ *pb.Alert_Ask, stream grpc.ServerStreamingServer[pb.Alert_Msg]) error {
	return streamAlert(s.rc, shared.AlertTraChannel, stream)
}

// ThsrAlert streams THSR (high-speed rail) alerts. The request carries no
// parameters; all THSR alerts share one channel.
func (s *AlertServer) ThsrAlert(_ *pb.Alert_Ask, stream grpc.ServerStreamingServer[pb.Alert_Msg]) error {
	return streamAlert(s.rc, shared.AlertThsrChannel, stream)
}

// streamAlert bridges one alert channel to a gRPC stream: the mirrored
// latest-payload key seeds new subscribers, then live updates follow. Unlike
// the old loop, client disconnect is noticed while idle.
func streamAlert(rc *redis.Client, key string, stream grpc.ServerStreamingServer[pb.Alert_Msg]) error {
	return streamLive(stream.Context(), redisLiveSource{rc}, liveStreamSpec{
		channel:  key,
		seedKeys: []string{key},
	}, func(data []byte) error {
		return stream.Send(&pb.Alert_Msg{Data: data})
	})
}
