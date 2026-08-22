// Package metro serves metro arrival boards and the alight-reminder session
// RPCs (ADR-0015). Arrival boards are seeded by scanning the current mrt_live
// keys and then streamed from Redis Pub/Sub; reminder sessions persist in the
// shared reminders table.
package metro

import (
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/livestream"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
	"golang.org/x/sync/errgroup"
)

// MrtServer streams metro arrival boards from Redis and hosts the metro
// alight-reminder session RPCs (ADR-0015). It seeds each arrival stream by
// scanning the current mrt_live keys before subscribing to live updates. store
// persists sessions in the shared reminders table, trtc verifies a car binding
// at creation, and now is an injectable clock for tests.
type MrtServer struct {
	pb.UnimplementedMrt_ServiceServer

	rc    *redis.Client
	db    *pgxpool.Pool
	live  livestream.LiveSource
	store mrtTrackStore
	trtc  mrtTrainInfo
	now   func() time.Time
}

// NewMrtServer wires the metro read path and the reminder session store.
func NewMrtServer(db *pgxpool.Pool, rc *redis.Client, live livestream.LiveSource, store mrtTrackStore, trtc mrtTrainInfo, now func() time.Time) *MrtServer {
	return &MrtServer{db: db, rc: rc, live: live, store: store, trtc: trtc, now: now}
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
	zap.S().Infow("call", "component", "grpc", "action", "mrt_eta", "event", "call", "system", in.System, "station_id", in.StationID)

	// stream.Send is not safe for concurrent use, so the per-station streams
	// serialize their sends through one mutex.
	var mu sync.Mutex
	send := func(data []byte) error {
		live, err := livestream.DecodePayload(data, &pb.MrtLive{})
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
			return livestream.StreamLive(ctx, s.live, livestream.LiveStreamSpec{
				Channel:  shared.MrtLiveChannel(in.System, station),
				SeedScan: shared.MrtLiveSeedPattern(in.System, station),
			}, send)
		})
	}
	return g.Wait()
}
