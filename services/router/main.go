// Package main runs the router process: a gRPC server on :50051 and an HTTP
// server on :8080. Static queries (bus/bike/MRT/TRA/THSR stops and timetables)
// are served from PostgreSQL; realtime ETA and alert streams are fanned
// out from Redis Pub/Sub. It also serves nearby-station search, TDX MaaS route
// planning, and Firebase device/reminder registration. main() wires every gRPC
// service, the rate limiter, and optional Firebase App Check onto one server.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	// Registers the gzip compressor. grpc-go answers a request in whatever
	// encoding the request arrived in (server.go: RecvCompress), so this import
	// is what lets the app's gzipped requests come back gzipped — bus route
	// static payloads carry verbatim TDX fare JSON, which compresses ~25x.
	_ "google.golang.org/grpc/encoding/gzip"
	"google.golang.org/grpc/status"
)

func usableBusEtaPayload(data []byte) bool {
	return len(data) > 0
}

// grpcStatusFor is the shared choke point for every bus/bike/rail read
// handler's DB (and cache) lookup failure (handlers_core.go, handlers_rail.go),
// so it doubles as the single place to tally router_db_errors_total: a
// not-found result is expected traffic and excluded, everything else here is
// a genuine backing-store failure.
func grpcStatusFor(err error, notFoundMsg string) error {
	if errors.Is(err, pgx.ErrNoRows) || errors.Is(err, redis.Nil) || errors.Is(err, obs.ErrNotFound) {
		return status.Error(codes.NotFound, notFoundMsg)
	}
	obs.IncDBError()
	return status.Error(codes.Internal, "internal error")
}

func logPoolStats(pool *pgxpool.Pool) {
	t := time.NewTicker(1 * time.Minute)
	for range t.C {
		s := pool.Stat()
		zap.S().Infow("log",
			"component", "db",
			"action", "pool_stat",
			"total", s.TotalConns(),
			"acquired", s.AcquiredConns(),
			"idle", s.IdleConns(),
			"empty_acquires", s.EmptyAcquireCount(),
			"max", s.MaxConns(),
		)
	}
}

// BusRouteserver serves per-route bus queries: static route data from
// PostgreSQL (memoized in cache) and live ETA streamed from Redis Pub/Sub.
type BusRouteserver struct {
	pb.UnimplementedBus_Route_ServiceServer
	db    *pgxpool.Pool
	rc    *redis.Client
	cache *TTLCache
	live  LiveSource
}

// BusStationserver serves station-group bus queries: group membership from
// PostgreSQL and per-station live ETA streamed from Redis Pub/Sub.
type BusStationserver struct {
	pb.UnimplementedBus_Station_ServiceServer
	db   *pgxpool.Pool
	rc   *redis.Client
	live LiveSource
}

// BikeServer serves bike-share station static data from PostgreSQL (memoized in
// cache) and live availability streamed from Redis Pub/Sub.
type BikeServer struct {
	pb.UnimplementedBike_ServiceServer
	db    *pgxpool.Pool
	rc    *redis.Client
	cache *TTLCache
	live  LiveSource
}

// MrtServer streams metro arrival boards from Redis and hosts the metro
// alight-reminder session RPCs (ADR-0015). It seeds each arrival stream by
// scanning the current mrt_live keys before subscribing to live updates. store
// persists sessions in the shared reminders table, trtc verifies a car binding
// at creation, and now is an injectable clock for tests.
type MrtServer struct {
	pb.UnimplementedMrt_ServiceServer
	rc    *redis.Client
	db    *pgxpool.Pool
	live  LiveSource
	store mrtTrackStore
	trtc  mrtTrainInfo
	now   func() time.Time
}

// ThsrServer serves high-speed-rail fares, timetables, and available-seat
// streams. Every path is a pure read: fare/timetable results are cached in Redis
// and, on a miss, read from the loaded env schema, and AvailableSeats streams the
// seat snapshots the functions THSR-seats live job refreshes into Redis. No TDX
// fetch (ADR-0005), so the server holds no TDX client.
type ThsrServer struct {
	pb.UnimplementedThsrTimetableServiceServer
	db   *pgxpool.Pool
	rc   *redis.Client
	live LiveSource
}

// TraTimetableServer serves TRA fares and timetables and streams system-wide
// delays. Fare/timetable lookups are Redis-cached and, on a miss, read from the
// loaded env schema; empty results return NotFound (no TDX fetch, ADR-0005).
type TraTimetableServer struct {
	pb.UnimplementedTRATimetableServiceServer
	db   *pgxpool.Pool
	rc   *redis.Client
	live LiveSource
}

// TraDetainServer serves per-train TRA stop times and streams per-train delay
// updates. Stop times are Redis-cached and, on a miss, read from the loaded env
// schema; empty results return NotFound (no TDX fetch, ADR-0005).
type TraDetainServer struct {
	pb.UnimplementedTRA_DetainServiceServer
	db   *pgxpool.Pool
	rc   *redis.Client
	live LiveSource
}

// ThsrDetainServer serves per-train THSR stop times. Stop times are Redis-cached
// and, on a miss, read from the loaded env schema; empty results return NotFound
// (no TDX fetch, ADR-0005).
type ThsrDetainServer struct {
	pb.UnimplementedThsr_DetainServiceServer
	db   *pgxpool.Pool
	rc   *redis.Client
	live LiveSource
}

// NearServer streams results from the nearby discovery module.
type NearServer struct {
	pb.UnimplementedNear_Station_ServiceServer
	discovery *NearbyDiscovery
}

func installationRateLimitInterceptor(rl *RateLimiter, limit int, window time.Duration) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
		if !strings.HasPrefix(info.FullMethod, "/Firebase_Service/") {
			return handler(ctx, req)
		}
		installID, ok := InstallationCallerID(ctx)
		if ok && !rl.allow(info.FullMethod, "install:"+installID, limit, window) {
			return nil, status.Error(codes.ResourceExhausted, "installation rate limit exceeded")
		}
		return handler(ctx, req)
	}
}

func productionUnaryInterceptors(
	appCheckVerifier AppCheckVerifier,
	enforceAppCheck bool,
	maasRL *RateLimiter,
) []grpc.UnaryServerInterceptor {
	return []grpc.UnaryServerInterceptor{
		obs.UnaryInterceptor(),
		RateLimitInterceptor(NewRateLimiter(), 30, time.Second),
		MaasResourceInterceptor(maasRL, DefaultMaasResourceConfig),
		AppCheckUnaryInterceptor(appCheckVerifier, enforceAppCheck),
		installationRateLimitInterceptor(NewRateLimiter(), 30, time.Second),
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
	// shutdown, when set, carries OS signals (SIGINT/SIGTERM) that should
	// trigger the same coordinated stop path as a Serve failure. Injectable
	// for tests; nil disables signal-triggered shutdown (select on a nil
	// channel blocks forever, so it never wins the race below).
	shutdown <-chan os.Signal
}

type serverResult struct {
	name string
	err  error
}

// serve runs both servers and blocks until either one exits unexpectedly or
// a shutdown signal arrives, whichever happens first. Exactly one of those
// two events drives stopServers: the select below is atomic, so a signal
// racing a Serve failure resolves to a single winner and stopServers runs
// exactly once either way.
func (c serverCoordinator) serve(grpcListener, httpListener net.Listener) error {
	results := make(chan serverResult, 2)
	go func() {
		results <- serverResult{name: "gRPC", err: c.grpcServer.Serve(grpcListener)}
	}()
	go func() {
		results <- serverResult{name: "HTTP", err: c.httpServer.Serve(httpListener)}
	}()

	var serveErr error
	select {
	case first := <-results:
		serveErr = unexpectedServeError(first)
		c.stopServers()
		<-results // Both Serve goroutines must finish before backend cleanup.
	case <-c.shutdown:
		zap.S().Infow("signal received", "component", "router", "action", "shutdown", "event", "signal_received")
		c.stopServers()
		<-results // Both Serve goroutines must finish before backend cleanup.
		<-results
	}
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
		shutdownSignal := make(chan os.Signal, 1)
		signal.Notify(shutdownSignal, syscall.SIGINT, syscall.SIGTERM)
		runtime.addCleanup(func() { signal.Stop(shutdownSignal) })
		httpConfig, err := httpServerConfigFromEnv()
		if err != nil {
			return fmt.Errorf("HTTP configuration failed before startup: %w", err)
		}
		rc := shared.ConnectRedis()
		runtime.addCleanup(func() {
			if err := rc.Close(); err != nil {
				zap.S().Errorw("failed", "component", "redis", "action", "close", "event", "failed", "err", err)
			}
		})
		live := NewLiveHubWithQueueSize(
			RedisLiveSource{rc: rc},
			int(shared.EnvInt32("ROUTER_MAX_LIVE_STREAMS", 2000)),
			int(shared.EnvInt32("ROUTER_LIVE_SUBSCRIBER_QUEUE", DefaultSubscriberQueueSize)),
		)
		db := shared.ConnectDB("ROUTER_DB_MAX_CONNS", 20)
		runtime.addCleanup(db.Close)
		go logPoolStats(db)
		// MaaS route planning is the router's sole, deliberate TDX carve-out: it is a
		// request/response proxy, not cacheable live data, so it stays on the read
		// path (ADR-0005 amendment). Every other live TDX fetch, including the THSR
		// seat refresh, runs in services/functions. This client exists only for MaaS.
		tdx := shared.NewTDXClient(shared.TDXConfig{
			Store:  shared.RedisTDXStore{RC: rc},
			IMSKey: shared.TDXLegacyIMSKey,
		})
		httpConfig.booking = NewBookingProxy(tdx)
		// Same client the live streams use: the GBFS station_status feed reads the
		// bike availability keys bikeEta writes, so it needs no cache of its own.
		httpConfig.redis = rc
		maasCache := NewRedisMaasCache(rc.Options())
		runtime.addCleanup(func() {
			if err := maasCache.Close(); err != nil {
				zap.S().Errorw("failed", "component", "maas", "action", "cache_close", "event", "failed", "err", err)
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
		rl := NewRateLimiter()
		tlsCredentials, err := GRPCTLSCredentialsFromEnv()
		if err != nil {
			return fmt.Errorf("gRPC TLS initialization failed: %w", err)
		}
		appCheckVerifier, enforceAppCheck, err := FirebaseAppCheckFromEnv(context.Background())
		if err != nil {
			return fmt.Errorf("initialize Firebase Admin: %w", err)
		}
		// One limiter across both chains so the TDX quota is spent per caller,
		// not per method (see maasQuotaScope).
		maasRL := NewRateLimiter()
		serverOptions := []grpc.ServerOption{
			// Stop is the bounded GracefulStop fallback. Waiting for handlers here
			// keeps backend ownership valid until canceled RPC handlers return.
			grpc.WaitForHandlers(true),
			grpc.ChainUnaryInterceptor(productionUnaryInterceptors(appCheckVerifier, enforceAppCheck, maasRL)...),
			grpc.ChainStreamInterceptor(
				obs.StreamInterceptor(),
				RateLimitStreamInterceptor(rl, 30, time.Second),
				MaasResourceStreamInterceptor(maasRL, DefaultMaasResourceConfig),
				AppCheckStreamInterceptor(appCheckVerifier, enforceAppCheck),
			),
		}
		if tlsCredentials != nil {
			serverOptions = append(serverOptions, grpc.Creds(tlsCredentials))
		}
		grpcServer := grpc.NewServer(serverOptions...)
		pb.RegisterBus_Route_ServiceServer(grpcServer, &BusRouteserver{db: db, rc: rc, cache: NewTTLCache(), live: live})
		pb.RegisterBus_Station_ServiceServer(grpcServer, &BusStationserver{db: db, rc: rc, live: live})
		pb.RegisterBike_ServiceServer(grpcServer, &BikeServer{db: db, rc: rc, cache: NewTTLCache(), live: live})
		pb.RegisterMrt_ServiceServer(grpcServer, &MrtServer{
			db: db, rc: rc, live: live,
			store: NewFirebaseStore(db),
			trtc:  shared.NewTRTCTrainInfoClient(os.Getenv("TRTC_USERNAME"), os.Getenv("TRTC_PASSWORD")),
			now:   time.Now,
		})
		pb.RegisterThsrTimetableServiceServer(grpcServer, &ThsrServer{db: db, rc: rc, live: live})
		pb.RegisterTRATimetableServiceServer(grpcServer, &TraTimetableServer{db: db, rc: rc, live: live})
		pb.RegisterTRA_DetainServiceServer(grpcServer, &TraDetainServer{db: db, rc: rc, live: live})
		pb.RegisterThsr_DetainServiceServer(grpcServer, &ThsrDetainServer{db: db, rc: rc, live: live})
		nearbyRouter := NewOSRMWalkingRouter(resty.New().SetTimeout(5*time.Second), "http://osrm:5000")
		pb.RegisterNear_Station_ServiceServer(grpcServer, &NearServer{discovery: NewNearbyDiscovery(NewPostgresNearbyStore(db), nearbyRouter)})
		pb.RegisterAlert_ServiceServer(grpcServer, &AlertServer{live: live})
		maasServer := NewMaasServerWithCache(maasCache, db, tdx, DefaultMaasSharedWorkConfig)
		// Registered after rc/db/maasCache's cleanups above, so in cleanup's
		// LIFO order MaasServer.Close runs first: every shared singleflight
		// flight is canceled and joined before those backends close under it.
		runtime.addCleanup(maasServer.Close)
		pb.RegisterMaasServiceServer(grpcServer, maasServer)
		pb.RegisterFirebase_ServiceServer(grpcServer, &FirebaseServer{store: NewFirebaseStore(db), now: time.Now})
		pb.RegisterFeedback_ServiceServer(grpcServer, &FeedbackServer{
			store:    NewFeedbackStore(db),
			devices:  NewFirebaseStore(db),
			notifier: NewFeedbackNotifier(),
		})
		zap.S().Infow(fmt.Sprintf("gRPC server is running on port %d", 50051))
		zap.S().Infow("server running on 0.0.0.0:8080", "component", "http")
		coordinator := serverCoordinator{
			grpcServer:       grpcServer,
			httpServer:       httpRuntime.server,
			waitHTTPHandlers: httpRuntime.handlers.stopAndWait,
			shutdownTimeout:  5 * time.Second,
			shutdown:         shutdownSignal,
			capture: func(err error) {
				obs.Capture("router-serve", err)
			},
		}
		return coordinator.serve(lis, httpRuntime.listener)
	})
}

// reportProcessFailure writes the final process-failure message directly to
// w, bypassing the slog default logger. By the time run() returns, obs.Init's
// deferred cleanup has already flushed Sentry (it runs last among run's
// cleanups), so logging this line through log.Errorf/slog would route it
// through the Sentry-forwarding handler and silently enqueue an event nothing
// ever flushes.
func reportProcessFailure(w io.Writer, err error) {
	_, _ = fmt.Fprintf(w, "router exited with error: %v\n", err)
}

func main() {
	if err := run(); err != nil {
		reportProcessFailure(os.Stderr, err)
		os.Exit(1)
	}
}
