// Package main runs the router process: a gRPC server on :50051 and an HTTP
// server on :8080. Static queries (bus/bike/MRT/TRA/THSR stops and timetables)
// are served from PostgreSQL on Azure; realtime ETA and alert streams are fanned
// out from Redis Pub/Sub. It also serves nearby-station search, TDX MaaS route
// planning, and Firebase device/reminder registration. main() wires every gRPC
// service, the rate limiter, and optional Firebase App Check onto one server.
package main

import (
	"context"
	"errors"
	"net"
	"sync"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/peer"
	"google.golang.org/grpc/status"
)

func usableBusEtaPayload(data []byte) bool {
	return len(data) > 0
}

func grpcStatusFor(err error, notFoundMsg string) error {
	if errors.Is(err, pgx.ErrNoRows) || errors.Is(err, redis.Nil) || errors.Is(err, obs.ErrNotFound) {
		return status.Error(codes.NotFound, notFoundMsg)
	}
	return status.Error(codes.Internal, "internal error")
}

func logPoolStats(pool *pgxpool.Pool) {
	t := time.NewTicker(1 * time.Minute)
	for range t.C {
		s := pool.Stat()
		log.Infof("[DB] action=pool_stat total=%d acquired=%d idle=%d empty_acquires=%d max=%d",
			s.TotalConns(), s.AcquiredConns(), s.IdleConns(), s.EmptyAcquireCount(), s.MaxConns())
	}
}

// BusRouteserver serves per-route bus queries: static route data from
// PostgreSQL (memoized in cache) and live ETA streamed from Redis Pub/Sub.
type BusRouteserver struct {
	pb.UnimplementedBus_Route_ServiceServer
	mu    sync.Mutex
	db    *pgxpool.Pool
	rc    *redis.Client
	cache *ttlCache
}

// BusStationserver serves station-group bus queries: group membership from
// PostgreSQL and per-station live ETA streamed from Redis Pub/Sub.
type BusStationserver struct {
	pb.UnimplementedBus_Station_ServiceServer
	mu sync.Mutex
	db *pgxpool.Pool
	rc *redis.Client
}

// BikeServer serves bike-share station static data from PostgreSQL (memoized in
// cache) and live availability streamed from Redis Pub/Sub.
type BikeServer struct {
	pb.UnimplementedBike_ServiceServer
	mu    sync.Mutex
	db    *pgxpool.Pool
	rc    *redis.Client
	cache *ttlCache
}

// MrtServer streams metro arrival boards from Redis. It seeds each stream by
// scanning the current mrt_live keys before subscribing to live updates.
type MrtServer struct {
	pb.UnimplementedMrt_ServiceServer
	mu sync.Mutex
	rc *redis.Client
	db *pgxpool.Pool
}

// ThsrServer serves high-speed-rail fares, timetables, and available-seat
// streams. Fare/timetable results are cached in Redis and, on a miss, read from
// the loaded env schema (no TDX fetch, ADR-0005). The resty client remains only
// for the realtime AvailableSeats refresh.
type ThsrServer struct {
	pb.UnimplementedThsrTimetableServiceServer
	mu     sync.Mutex
	db     *pgxpool.Pool
	client *resty.Client
	rc     *redis.Client
}

// Tra_StationServer streams the live arrival board for a TRA station from Redis
// Pub/Sub.
type Tra_StationServer struct {
	pb.UnimplementedTRAStationServiceServer
	mu sync.Mutex
	db *pgxpool.Pool
	rc *redis.Client
}

// Tra_TimetableServer serves TRA fares and timetables and streams system-wide
// delays. Fare/timetable lookups are Redis-cached and, on a miss, read from the
// loaded env schema; empty results return NotFound (no TDX fetch, ADR-0005).
type Tra_TimetableServer struct {
	pb.UnimplementedTRATimetableServiceServer
	mu sync.Mutex
	db *pgxpool.Pool
	rc *redis.Client
}

// Tra_DetainServer serves per-train TRA stop times and streams per-train delay
// updates. Stop times are Redis-cached and, on a miss, read from the loaded env
// schema; empty results return NotFound (no TDX fetch, ADR-0005).
type Tra_DetainServer struct {
	pb.UnimplementedTRA_DetainServiceServer
	mu sync.Mutex
	db *pgxpool.Pool
	rc *redis.Client
}

// Thsr_DetainServer serves per-train THSR stop times. Stop times are Redis-cached
// and, on a miss, read from the loaded env schema; empty results return NotFound
// (no TDX fetch, ADR-0005).
type Thsr_DetainServer struct {
	pb.UnimplementedThsr_DetainServiceServer
	mu sync.Mutex
	db *pgxpool.Pool
	rc *redis.Client
}

// Near_Server answers nearby-station queries. It runs PostGIS radius queries
// against PostgreSQL and refines walking time/distance through the OSRM foot
// profile via osrmClient, falling back to geodesic estimates when OSRM is
// unavailable.
type Near_Server struct {
	pb.UnimplementedNear_Station_ServiceServer
	mu         sync.Mutex
	db         *pgxpool.Pool
	osrmClient *resty.Client
}

type rateLimiter struct {
	mu       sync.Mutex
	counts   map[string]int
	windowAt time.Time
}

func newRateLimiter() *rateLimiter {
	return &rateLimiter{
		counts:   make(map[string]int, 128),
		windowAt: time.Now(),
	}
}

func (r *rateLimiter) allow(ip string, limit int, window time.Duration) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	now := time.Now()
	if now.Sub(r.windowAt) >= window {
		r.windowAt = now
		for k := range r.counts {
			delete(r.counts, k)
		}
	}
	r.counts[ip]++
	return r.counts[ip] <= limit
}
func rateLimitInterceptor(rl *rateLimiter, limit int, window time.Duration) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		if !allowRequest(ctx, rl, limit, window) {
			return nil, status.Error(codes.ResourceExhausted, "rate limit exceeded")
		}
		return handler(ctx, req)
	}
}
func rateLimitStreamInterceptor(rl *rateLimiter, limit int, window time.Duration) grpc.StreamServerInterceptor {
	return func(srv interface{}, ss grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) error {
		if !allowRequest(ss.Context(), rl, limit, window) {
			return status.Error(codes.ResourceExhausted, "rate limit exceeded")
		}
		return handler(srv, ss)
	}
}
func allowRequest(ctx context.Context, rl *rateLimiter, limit int, window time.Duration) bool {
	peerInfo, ok := peer.FromContext(ctx)
	if !ok || peerInfo.Addr == nil {
		return true
	}
	addr := peerInfo.Addr.String()
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		host = addr
	}
	return rl.allow(host, limit, window)
}

func main() {
	defer obs.Init("router")()
	rc := shared.ConnectRedis()
	db := shared.ConnectDB("ROUTER_DB_MAX_CONNS", 20)
	go logPoolStats(db)
	c := resty.New()
	defer func(rc *redis.Client) {
		err := rc.Close()
		if err != nil {
			log.Infof("[REDIS] action=close event=failed error=%v", err)
		}
	}(rc)
	defer db.Close()
	c.SetBaseURL("https://tdx.transportdata.tw/api/basic").
		SetHeader("Content-Type", "application/json").
		SetHeader("Content-Encoding", "br,gzip").
		SetDoNotParseResponse(true).
		SetRetryCount(5).
		SetRetryWaitTime(1 * time.Second).
		SetRetryMaxWaitTime(5 * time.Second).
		AddRetryCondition(
			func(r *resty.Response, err error) bool {
				if err != nil {
					return true
				}
				if r.StatusCode() == 401 {
					rc.Del("TDX_Token")
					return true
				}
				return r.StatusCode() == 429
			},
		).
		OnBeforeRequest(func(_ *resty.Client, req *resty.Request) error {
			req.SetAuthToken(getToken(rc))
			return nil
		})
	lis, err := net.Listen("tcp", "0.0.0.0:50051")
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
	rl := newRateLimiter()
	tlsCredentials, err := firebaseTLSCredentialsFromEnv()
	if err != nil {
		log.Fatalf("gRPC TLS initialization failed: %v", err)
	}
	appCheckVerifier, enforceAppCheck, err := firebaseAppCheckFromEnv(context.Background())
	if err != nil {
		log.Fatalf("Firebase Admin initialization failed: %v", err)
	}
	serverOptions := []grpc.ServerOption{
		grpc.ChainUnaryInterceptor(
			obs.UnaryInterceptor(),
			rateLimitInterceptor(rl, 30, time.Second),
			appCheckUnaryInterceptor(appCheckVerifier, enforceAppCheck),
		),
		grpc.ChainStreamInterceptor(
			obs.StreamInterceptor(),
			rateLimitStreamInterceptor(rl, 30, time.Second),
			appCheckStreamInterceptor(appCheckVerifier, enforceAppCheck),
		),
	}
	if tlsCredentials != nil {
		serverOptions = append(serverOptions, grpc.Creds(tlsCredentials))
	}
	grpcServer := grpc.NewServer(serverOptions...)
	pb.RegisterBus_Route_ServiceServer(grpcServer, &BusRouteserver{db: db, rc: rc, cache: newTTLCache()})
	pb.RegisterBus_Station_ServiceServer(grpcServer, &BusStationserver{db: db, rc: rc})
	pb.RegisterBike_ServiceServer(grpcServer, &BikeServer{db: db, rc: rc, cache: newTTLCache()})
	pb.RegisterMrt_ServiceServer(grpcServer, &MrtServer{db: db, rc: rc})
	pb.RegisterThsrTimetableServiceServer(grpcServer, &ThsrServer{db: db, client: c, rc: rc})
	pb.RegisterTRAStationServiceServer(grpcServer, &Tra_StationServer{db: db, rc: rc})
	pb.RegisterTRATimetableServiceServer(grpcServer, &Tra_TimetableServer{db: db, rc: rc})
	pb.RegisterTRA_DetainServiceServer(grpcServer, &Tra_DetainServer{db: db, rc: rc})
	pb.RegisterThsr_DetainServiceServer(grpcServer, &Thsr_DetainServer{db: db, rc: rc})
	pb.RegisterNear_Station_ServiceServer(grpcServer, &Near_Server{db: db, osrmClient: resty.New().SetTimeout(5 * time.Second)})
	pb.RegisterAlert_ServiceServer(grpcServer, &AlertServer{rc: rc})
	pb.RegisterMaasServiceServer(grpcServer, newMaasServer(rc, db, func() string { return getToken(rc) }))
	pb.RegisterFirebase_ServiceServer(grpcServer, &FirebaseServer{store: newFirebaseStore(db), now: time.Now})
	go startHTTPServer(db)
	log.Infof("gRPC server is running on port %d", 50051)
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
