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
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
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
	live  liveSource
}

// BusStationserver serves station-group bus queries: group membership from
// PostgreSQL and per-station live ETA streamed from Redis Pub/Sub.
type BusStationserver struct {
	pb.UnimplementedBus_Station_ServiceServer
	mu   sync.Mutex
	db   *pgxpool.Pool
	rc   *redis.Client
	live liveSource
}

// BikeServer serves bike-share station static data from PostgreSQL (memoized in
// cache) and live availability streamed from Redis Pub/Sub.
type BikeServer struct {
	pb.UnimplementedBike_ServiceServer
	mu    sync.Mutex
	db    *pgxpool.Pool
	rc    *redis.Client
	cache *ttlCache
	live  liveSource
}

// MrtServer streams metro arrival boards from Redis. It seeds each stream by
// scanning the current mrt_live keys before subscribing to live updates.
type MrtServer struct {
	pb.UnimplementedMrt_ServiceServer
	mu   sync.Mutex
	rc   *redis.Client
	db   *pgxpool.Pool
	live liveSource
}

// ThsrServer serves high-speed-rail fares, timetables, and available-seat
// streams. Every path is a pure read: fare/timetable results are cached in Redis
// and, on a miss, read from the loaded env schema, and AvailableSeats streams the
// seat snapshots the functions THSR-seats live job refreshes into Redis. No TDX
// fetch (ADR-0005), so the server holds no TDX client.
type ThsrServer struct {
	pb.UnimplementedThsrTimetableServiceServer
	mu   sync.Mutex
	db   *pgxpool.Pool
	rc   *redis.Client
	live liveSource
}

// Tra_TimetableServer serves TRA fares and timetables and streams system-wide
// delays. Fare/timetable lookups are Redis-cached and, on a miss, read from the
// loaded env schema; empty results return NotFound (no TDX fetch, ADR-0005).
type Tra_TimetableServer struct {
	pb.UnimplementedTRATimetableServiceServer
	mu   sync.Mutex
	db   *pgxpool.Pool
	rc   *redis.Client
	live liveSource
}

// Tra_DetainServer serves per-train TRA stop times and streams per-train delay
// updates. Stop times are Redis-cached and, on a miss, read from the loaded env
// schema; empty results return NotFound (no TDX fetch, ADR-0005).
type Tra_DetainServer struct {
	pb.UnimplementedTRA_DetainServiceServer
	mu   sync.Mutex
	db   *pgxpool.Pool
	rc   *redis.Client
	live liveSource
}

// Thsr_DetainServer serves per-train THSR stop times. Stop times are Redis-cached
// and, on a miss, read from the loaded env schema; empty results return NotFound
// (no TDX fetch, ADR-0005).
type Thsr_DetainServer struct {
	pb.UnimplementedThsr_DetainServiceServer
	mu   sync.Mutex
	db   *pgxpool.Pool
	rc   *redis.Client
	live liveSource
}

// Near_Server streams results from the nearby discovery module.
type Near_Server struct {
	pb.UnimplementedNear_Station_ServiceServer
	discovery *nearbyDiscovery
}

type rateLimiter struct {
	mu          sync.Mutex
	buckets     map[string]rateBucket
	nextCleanup time.Time
	now         func() time.Time
}

type rateBucket struct {
	count     int
	expiresAt time.Time
}

func newRateLimiter() *rateLimiter {
	return &rateLimiter{
		buckets: make(map[string]rateBucket, 128),
		now:     time.Now,
	}
}

func (r *rateLimiter) allow(scope, caller string, limit int, window time.Duration) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	now := r.now()
	if r.nextCleanup.IsZero() || !now.Before(r.nextCleanup) {
		r.nextCleanup = time.Time{}
		for key, bucket := range r.buckets {
			if !now.Before(bucket.expiresAt) {
				delete(r.buckets, key)
				continue
			}
			if r.nextCleanup.IsZero() || bucket.expiresAt.Before(r.nextCleanup) {
				r.nextCleanup = bucket.expiresAt
			}
		}
	}
	key := scope + "\x00" + caller
	bucket, ok := r.buckets[key]
	if !ok || !now.Before(bucket.expiresAt) {
		bucket = rateBucket{expiresAt: now.Add(window)}
	}
	if r.nextCleanup.IsZero() || bucket.expiresAt.Before(r.nextCleanup) {
		r.nextCleanup = bucket.expiresAt
	}
	if bucket.count >= limit {
		return false
	}
	bucket.count++
	r.buckets[key] = bucket
	return true
}
func rateLimitInterceptor(rl *rateLimiter, limit int, window time.Duration) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		if !allowRequest(ctx, rl, info.FullMethod, limit, window) {
			return nil, status.Error(codes.ResourceExhausted, "rate limit exceeded")
		}
		return handler(ctx, req)
	}
}
func rateLimitStreamInterceptor(rl *rateLimiter, limit int, window time.Duration) grpc.StreamServerInterceptor {
	return func(srv interface{}, ss grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) error {
		if !allowRequest(ss.Context(), rl, info.FullMethod, limit, window) {
			return status.Error(codes.ResourceExhausted, "rate limit exceeded")
		}
		return handler(srv, ss)
	}
}
func allowRequest(ctx context.Context, rl *rateLimiter, scope string, limit int, window time.Duration) bool {
	peerInfo, ok := peer.FromContext(ctx)
	if !ok || peerInfo.Addr == nil {
		return true
	}
	addr := peerInfo.Addr.String()
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		host = addr
	}
	return rl.allow(scope, host, limit, window)
}

func installationRateLimitInterceptor(rl *rateLimiter, limit int, window time.Duration) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		if !strings.HasPrefix(info.FullMethod, "/Firebase_Service/") {
			return handler(ctx, req)
		}
		installID, ok := installationCallerID(ctx)
		if ok && !rl.allow(info.FullMethod, "install:"+installID, limit, window) {
			return nil, status.Error(codes.ResourceExhausted, "installation rate limit exceeded")
		}
		return handler(ctx, req)
	}
}

func productionUnaryInterceptors(appCheckVerifier appCheckVerifier, enforceAppCheck bool) []grpc.UnaryServerInterceptor {
	return []grpc.UnaryServerInterceptor{
		obs.UnaryInterceptor(),
		rateLimitInterceptor(newRateLimiter(), 30, time.Second),
		maasResourceInterceptor(newRateLimiter(), defaultMaasResourceConfig),
		appCheckUnaryInterceptor(appCheckVerifier, enforceAppCheck),
		installationRateLimitInterceptor(newRateLimiter(), 30, time.Second),
	}
}

type maasResourceConfig struct {
	RateLimit  int
	RateWindow time.Duration
}

var defaultMaasResourceConfig = maasResourceConfig{
	RateLimit:  5,
	RateWindow: time.Minute,
}

// maasResourceInterceptor contains the per-caller TDX quota independently from
// unrelated gRPC methods. Shared-work concurrency and deadlines belong to
// MaasServer so singleflight work retains them after an individual caller exits.
func maasResourceInterceptor(rl *rateLimiter, config maasResourceConfig) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		if info.FullMethod != pb.MaasService_Plan_FullMethodName {
			return handler(ctx, req)
		}
		if err := ctx.Err(); err != nil {
			return nil, status.FromContextError(err).Err()
		}
		if !allowRequest(ctx, rl, info.FullMethod, config.RateLimit, config.RateWindow) {
			return nil, status.Error(codes.ResourceExhausted, "MaaS rate limit exceeded")
		}
		if err := ctx.Err(); err != nil {
			return nil, status.FromContextError(err).Err()
		}
		return handler(ctx, req)
	}
}

type coordinatedGRPCServer interface {
	Serve(net.Listener) error
	GracefulStop()
	Stop()
}

type coordinatedHTTPServer interface {
	Serve(net.Listener) error
	Shutdown(context.Context) error
	Close() error
}

type serverCoordinator struct {
	grpcServer       coordinatedGRPCServer
	httpServer       coordinatedHTTPServer
	shutdownTimeout  time.Duration
	waitHTTPHandlers func()
	capture          func(error)
}

type serverResult struct {
	name string
	err  error
}

func (c serverCoordinator) serve(grpcListener, httpListener net.Listener) error {
	results := make(chan serverResult, 2)
	go func() {
		results <- serverResult{name: "gRPC", err: c.grpcServer.Serve(grpcListener)}
	}()
	go func() {
		results <- serverResult{name: "HTTP", err: c.httpServer.Serve(httpListener)}
	}()

	first := <-results
	serveErr := unexpectedServeError(first)
	c.stopServers()
	<-results // Both Serve goroutines must finish before backend cleanup.
	if c.capture != nil {
		c.capture(serveErr)
	}
	return serveErr
}

func unexpectedServeError(result serverResult) error {
	if result.err == nil || (result.name == "HTTP" && errors.Is(result.err, http.ErrServerClosed)) {
		return fmt.Errorf("%s server stopped unexpectedly", result.name)
	}
	return fmt.Errorf("%s server failed: %w", result.name, result.err)
}

func (c serverCoordinator) stopServers() {
	timeout := c.shutdownTimeout
	if timeout <= 0 {
		timeout = 5 * time.Second
	}
	var stopped sync.WaitGroup
	stopped.Add(2)
	go func() {
		defer stopped.Done()
		gracefulDone := make(chan struct{})
		go func() {
			c.grpcServer.GracefulStop()
			close(gracefulDone)
		}()
		select {
		case <-gracefulDone:
		case <-time.After(timeout):
			c.grpcServer.Stop()
			<-gracefulDone
		}
	}()
	go func() {
		defer stopped.Done()
		ctx, cancel := context.WithTimeout(context.Background(), timeout)
		defer cancel()
		if err := c.httpServer.Shutdown(ctx); err != nil {
			_ = c.httpServer.Close()
		}
		if c.waitHTTPHandlers != nil {
			c.waitHTTPHandlers()
		}
	}()
	stopped.Wait()
}

type routerRuntime struct {
	cleanups []func()
}

func (r *routerRuntime) addCleanup(cleanup func()) {
	r.cleanups = append(r.cleanups, cleanup)
}

func (r *routerRuntime) run(start func() error) error {
	defer func() {
		for index := len(r.cleanups) - 1; index >= 0; index-- {
			r.cleanups[index]()
		}
	}()
	return start()
}

func run() error {
	runtime := &routerRuntime{}
	return runtime.run(func() error {
		runtime.addCleanup(obs.Init("router"))
		httpConfig, err := httpServerConfigFromEnv()
		if err != nil {
			return fmt.Errorf("HTTP configuration failed before startup: %w", err)
		}
		rc := shared.ConnectRedis()
		runtime.addCleanup(func() {
			if err := rc.Close(); err != nil {
				log.Infof("[REDIS] action=close event=failed error=%v", err)
			}
		})
		live := newLiveHub(redisLiveSource{rc: rc}, int(shared.EnvInt32("ROUTER_MAX_LIVE_STREAMS", 2000)))
		db := shared.ConnectDB("ROUTER_DB_MAX_CONNS", 20)
		runtime.addCleanup(db.Close)
		go logPoolStats(db)
		// MaaS route planning is the router's sole, deliberate TDX carve-out: it is a
		// request/response proxy, not cacheable live data, so it stays on the read
		// path (ADR-0005 amendment). Every other formerly-live TDX fetch, including the
		// THSR seat refresh, now runs in services/functions. This client exists only
		// for MaaS.
		tdx := shared.NewTDXClient(shared.TDXConfig{
			Store:  shared.RedisTDXStore{RC: rc},
			IMSKey: shared.TDXLegacyIMSKey,
		})
		maasCache := newRedisMaasCache(rc.Options())
		runtime.addCleanup(func() {
			if err := maasCache.Close(); err != nil {
				log.Infof("[MAAS] action=cache_close event=failed error=%v", err)
			}
		})
		lis, err := net.Listen("tcp", "0.0.0.0:50051")
		if err != nil {
			return fmt.Errorf("listen for gRPC: %w", err)
		}
		runtime.addCleanup(func() { _ = lis.Close() })
		httpRuntime, err := prepareHTTPServer(db, live, httpConfig, loadOrGenerateKey, net.Listen)
		if err != nil {
			return err
		}
		runtime.addCleanup(func() { _ = httpRuntime.listener.Close() })
		rl := newRateLimiter()
		tlsCredentials, err := firebaseTLSCredentialsFromEnv()
		if err != nil {
			return fmt.Errorf("gRPC TLS initialization failed: %w", err)
		}
		appCheckVerifier, enforceAppCheck, err := firebaseAppCheckFromEnv(context.Background())
		if err != nil {
			return fmt.Errorf("Firebase Admin initialization failed: %w", err)
		}
		serverOptions := []grpc.ServerOption{
			// Stop is the bounded GracefulStop fallback. Waiting for handlers here
			// keeps backend ownership valid until canceled RPC handlers return.
			grpc.WaitForHandlers(true),
			grpc.ChainUnaryInterceptor(productionUnaryInterceptors(appCheckVerifier, enforceAppCheck)...),
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
		pb.RegisterBus_Route_ServiceServer(grpcServer, &BusRouteserver{db: db, rc: rc, cache: newTTLCache(), live: live})
		pb.RegisterBus_Station_ServiceServer(grpcServer, &BusStationserver{db: db, rc: rc, live: live})
		pb.RegisterBike_ServiceServer(grpcServer, &BikeServer{db: db, rc: rc, cache: newTTLCache(), live: live})
		pb.RegisterMrt_ServiceServer(grpcServer, &MrtServer{db: db, rc: rc, live: live})
		pb.RegisterThsrTimetableServiceServer(grpcServer, &ThsrServer{db: db, rc: rc, live: live})
		pb.RegisterTRATimetableServiceServer(grpcServer, &Tra_TimetableServer{db: db, rc: rc, live: live})
		pb.RegisterTRA_DetainServiceServer(grpcServer, &Tra_DetainServer{db: db, rc: rc, live: live})
		pb.RegisterThsr_DetainServiceServer(grpcServer, &Thsr_DetainServer{db: db, rc: rc, live: live})
		nearbyRouter := newOSRMWalkingRouter(resty.New().SetTimeout(5*time.Second), "http://osrm:5000")
		pb.RegisterNear_Station_ServiceServer(grpcServer, &Near_Server{discovery: newNearbyDiscovery(newPostgresNearbyStore(db), nearbyRouter)})
		pb.RegisterAlert_ServiceServer(grpcServer, &AlertServer{live: live})
		pb.RegisterMaasServiceServer(grpcServer, newMaasServerWithCache(maasCache, db, tdx, defaultMaasSharedWorkConfig))
		pb.RegisterFirebase_ServiceServer(grpcServer, &FirebaseServer{store: newFirebaseStore(db), now: time.Now})
		log.Infof("gRPC server is running on port %d", 50051)
		log.Infof("[HTTP] server running on 0.0.0.0:8080")
		coordinator := serverCoordinator{
			grpcServer:       grpcServer,
			httpServer:       httpRuntime.server,
			waitHTTPHandlers: httpRuntime.handlers.stopAndWait,
			shutdownTimeout:  5 * time.Second,
			capture: func(err error) {
				obs.Capture("router-serve", err)
			},
		}
		return coordinator.serve(lis, httpRuntime.listener)
	})
}

func main() {
	if err := run(); err != nil {
		log.Errorf("router exited with error: %v", err)
		os.Exit(1)
	}
}
