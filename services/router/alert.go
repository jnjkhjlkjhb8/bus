package main

import (
	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"google.golang.org/grpc"
	"google.golang.org/protobuf/encoding/protojson"

	"go.uber.org/zap"
)

// AlertServer streams service alerts that the functions/MQTT subscriber
// publishes into Redis. Each alert channel is also mirrored to a plain Redis
// key holding the latest payload, so a new subscriber can be sent the current
// state before live updates begin.
type AlertServer struct {
	pb.UnimplementedAlert_ServiceServer
	live LiveSource
}

// BusNews streams bus service-news alerts for the requested city. The city is
// interpolated into the Redis channel name, so an empty city subscribes to a
// channel that never receives messages.
func (s *AlertServer) BusNews(in *pb.Alert_Bus_Ask, stream grpc.ServerStreamingServer[pb.Alert_Msg]) error {
	key := shared.AlertBusNewsChannel(in.City)
	return streamAlert(s.live, key, stream)
}

// BusAlert streams bus service disruptions for the requested city. It is a
// separate channel from BusNews: TDX publishes advisories and disruptions on
// different topics, and each mirrors its own latest-payload key.
func (s *AlertServer) BusAlert(in *pb.Alert_Bus_Ask, stream grpc.ServerStreamingServer[pb.Alert_Msg]) error {
	return streamAlert(s.live, shared.AlertBusAlertChannel(in.City), stream)
}

// MetroAlert streams metro alerts for the requested rail system (e.g. TRTC,
// KRTC). The system code is interpolated into the Redis channel name.
func (s *AlertServer) MetroAlert(in *pb.Alert_Metro_Ask, stream grpc.ServerStreamingServer[pb.Alert_Msg]) error {
	key := shared.AlertMetroChannel(in.System)
	return streamAlert(s.live, key, stream)
}

// TraAlert streams TRA (conventional rail) alerts. The request carries no
// parameters; all TRA alerts share one channel.
func (s *AlertServer) TraAlert(_ *pb.Alert_Ask, stream grpc.ServerStreamingServer[pb.Alert_Msg]) error {
	return streamAlert(s.live, shared.AlertTraChannel, stream)
}

// ThsrAlert streams THSR (high-speed rail) alerts. The request carries no
// parameters; all THSR alerts share one channel.
func (s *AlertServer) ThsrAlert(_ *pb.Alert_Ask, stream grpc.ServerStreamingServer[pb.Alert_Msg]) error {
	return streamAlert(s.live, shared.AlertThsrChannel, stream)
}

// streamAlert bridges one alert channel to a gRPC stream: the mirrored
// latest-payload key seeds new subscribers, then live updates follow. Unlike
// the old loop, client disconnect is noticed while idle.
//
// Payloads are the normalized snapshot the MQTT subscriber wrote as protojson;
// the router only re-types them. A snapshot that fails to decode is skipped
// rather than surfaced, since tearing down a live stream over one bad message
// would cost the rider every later alert too.
func streamAlert(live LiveSource, key string, stream grpc.ServerStreamingServer[pb.Alert_Msg]) error {
	return StreamLive(stream.Context(), live, LiveStreamSpec{
		channel:  key,
		seedKeys: []string{key},
	}, func(data []byte) error {
		var msg pb.Alert_Msg
		if err := protojson.Unmarshal(data, &msg); err != nil {
			zap.S().Warnw("decode failed",
				"component", "alert",
				"action", "stream",
				"event", "decode_failed",
				"channel", key,
				"err", err,
			)
			return nil
		}
		return stream.Send(&msg)
	})
}
