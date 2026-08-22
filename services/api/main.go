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
	"github.com/jackc/pgx/v5/pgxpool"
	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/alert"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/cache"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/feedback"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/firebase"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/installid"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/livestream"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/maas"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/metro"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/nearby"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/rail"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/ratelimit"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/transit"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
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

// logPoolStats logs the DB pool's stats once a minute until stop is closed.
func logPoolStats(pool *pgxpool.Pool, stop <-chan struct{}) {
	t := time.NewTicker(1 * time.Minute)
	defer t.Stop()
	for {
		select {
		case <-t.C:
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
		case <-stop:
			return
		}
	}
}

func installationRateLimitInterceptor(rl *ratelimit.Limiter, limit int, window time.Duration) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
		if !strings.HasPrefix(info.FullMethod, "/Firebase_Service/") {
			return handler(ctx, req)
		}
		installID, ok := installid.CallerID(ctx)
		if ok && !rl.Allow(info.FullMethod, "install:"+installID, limit, window) {
			return nil, status.Error(codes.ResourceExhausted, "installation rate limit exceeded")
		}
		return handler(ctx, req)
	}
}

func productionUnaryInterceptors(
	appCheckVerifier firebase.AppCheckVerifier,
	enforceAppCheck bool,
	maasRL *ratelimit.Limiter,
) []grpc.UnaryServerInterceptor {
	return []grpc.UnaryServerInterceptor{
		obs.UnaryInterceptor(),
		ratelimit.UnaryInterceptor(ratelimit.New(), 30, time.Second),
		maas.MaasResourceInterceptor(maasRL, maas.DefaultMaasResourceConfig),
		firebase.AppCheckUnaryInterceptor(appCheckVerifier, enforceAppCheck),
		installationRateLimitInterceptor(ratelimit.New(), 30, time.Second),
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
		return _oops.With("result_name", result.name).Errorf("server stopped unexpectedly")
	}
	return _oops.With("result_name", result.name).Wrapf(result.err, "server failed")
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
			return _oops.Wrapf(err, "HTTP configuration failed before startup")
		}
		rc := shared.ConnectRedis()
		runtime.addCleanup(func() {
			if err := rc.Close(); err != nil {
				zap.S().Errorw("failed", "component", "redis", "action", "close", "event", "failed", "err", err)
			}
		})
		live := livestream.NewLiveHubWithQueueSize(
			livestream.NewRedisLiveSource(rc),
			int(shared.EnvInt32("ROUTER_MAX_LIVE_STREAMS", 2000)),
			int(shared.EnvInt32("ROUTER_LIVE_SUBSCRIBER_QUEUE", livestream.DefaultSubscriberQueueSize)),
		)
		db := shared.ConnectDB("ROUTER_DB_MAX_CONNS", 20)
		runtime.addCleanup(db.Close)
		poolStatsStop := make(chan struct{})
		poolStatsDone := make(chan struct{})
		go func() {
			defer close(poolStatsDone)
			logPoolStats(db, poolStatsStop)
		}()
		runtime.addCleanup(func() {
			close(poolStatsStop)
			<-poolStatsDone
		})
		// MaaS route planning is the router's sole, deliberate TDX carve-out: it is a
		// request/response proxy, not cacheable live data, so it stays on the read
		// path (ADR-0005 amendment). Every other live TDX fetch, including the THSR
		// seat refresh, runs in services/worker. This client exists only for MaaS.
		tdx := shared.NewTDXClient(shared.TDXConfig{
			Store:  shared.RedisTDXStore{RC: rc},
			IMSKey: shared.TDXLegacyIMSKey,
		})
		httpConfig.booking = rail.NewBookingProxy(tdx)
		// Same client the live streams use: the GBFS station_status feed reads the
		// bike availability keys bikeEta writes, so it needs no cache of its own.
		httpConfig.redis = rc
		maasCache := maas.NewRedisMaasCache(rc.Options())
		runtime.addCleanup(func() {
			if err := maasCache.Close(); err != nil {
				zap.S().Errorw("failed", "component", "maas", "action", "cache_close", "event", "failed", "err", err)
			}
		})
		lis, err := net.Listen("tcp", "0.0.0.0:50051")
		if err != nil {
			return _oops.Wrapf(err, "listen for gRPC")
		}
		runtime.addCleanup(func() { _ = lis.Close() })
		// The planner health monitor has to exist before prepareHTTPServer,
		// which takes httpConfig by value: assigning it afterwards would leave
		// /api/planner reporting a monitor the HTTP router never received.
		// Started here for the same reason -- Start runs one check
		// synchronously, so the first request already has a real verdict
		// rather than the monitor's optimistic default.
		motisBaseURL := maas.MotisBaseURLFromEnv()
		var plannerMonitor *maas.PlannerHealthMonitor
		if httpConfig.MotisEnabled {
			plannerMonitor = maas.NewPlannerHealthMonitor(maas.NewMotisHealthClient(motisBaseURL))
			healthCtx, stopHealth := context.WithCancel(context.Background())
			runtime.addCleanup(stopHealth)
			plannerMonitor.Start(healthCtx)
		}
		httpConfig.plannerHealth = plannerMonitor
		httpRuntime, err := prepareHTTPServer(db, live, httpConfig, loadOrGenerateKey, net.Listen)
		if err != nil {
			return err
		}
		runtime.addCleanup(func() { _ = httpRuntime.listener.Close() })
		rl := ratelimit.New()
		tlsCredentials, err := firebase.GRPCTLSCredentialsFromEnv()
		if err != nil {
			return _oops.Wrapf(err, "gRPC TLS initialization failed")
		}
		appCheckVerifier, enforceAppCheck, err := firebase.FirebaseAppCheckFromEnv(context.Background())
		if err != nil {
			return _oops.Wrapf(err, "initialize Firebase Admin")
		}
		// One limiter across both chains so the TDX quota is spent per caller,
		// not per method (see _maasQuotaScope).
		maasRL := ratelimit.New()
		serverOptions := []grpc.ServerOption{
			// Stop is the bounded GracefulStop fallback. Waiting for handlers here
			// keeps backend ownership valid until canceled RPC handlers return.
			grpc.WaitForHandlers(true),
			grpc.ChainUnaryInterceptor(productionUnaryInterceptors(appCheckVerifier, enforceAppCheck, maasRL)...),
			grpc.ChainStreamInterceptor(
				obs.StreamInterceptor(),
				ratelimit.StreamInterceptor(rl, 30, time.Second),
				maas.MaasResourceStreamInterceptor(maasRL, maas.DefaultMaasResourceConfig),
				firebase.AppCheckStreamInterceptor(appCheckVerifier, enforceAppCheck),
			),
		}
		if tlsCredentials != nil {
			serverOptions = append(serverOptions, grpc.Creds(tlsCredentials))
		}
		grpcServer := grpc.NewServer(serverOptions...)
		pb.RegisterBus_Route_ServiceServer(grpcServer, transit.NewBusRouteServer(db, rc, cache.NewTTLCache(), live))
		pb.RegisterBus_Station_ServiceServer(grpcServer, transit.NewBusStationServer(db, rc, live))
		pb.RegisterBike_ServiceServer(grpcServer, transit.NewBikeServer(db, rc, cache.NewTTLCache(), live))
		pb.RegisterMrt_ServiceServer(grpcServer, metro.NewMrtServer(
			db, rc, live,
			firebase.NewFirebaseStore(db),
			shared.NewTRTCTrainInfoClient(os.Getenv("TRTC_USERNAME"), os.Getenv("TRTC_PASSWORD")),
			time.Now,
		))
		pb.RegisterThsrTimetableServiceServer(grpcServer, rail.NewThsrServer(db, rc, live))
		pb.RegisterTRATimetableServiceServer(grpcServer, rail.NewTraTimetableServer(db, rc, live))
		pb.RegisterTRA_DetainServiceServer(grpcServer, rail.NewTraDetainServer(db, rc, live))
		pb.RegisterThsr_DetainServiceServer(grpcServer, rail.NewThsrDetainServer(db, rc, live))
		nearbyRouter := nearby.NewMotisWalkingRouter(resty.New().SetTimeout(5*time.Second), motisBaseURL)
		pb.RegisterNear_Station_ServiceServer(grpcServer, transit.NewNearServer(nearby.NewNearbyDiscovery(nearby.NewPostgresNearbyStore(db), nearbyRouter)))
		pb.RegisterAlert_ServiceServer(grpcServer, alert.NewAlertServer(live))
		// MAAS_BACKEND is the manual kill switch (ADR-0022). Selecting tdx leaves
		// the MOTIS client unbuilt, which is what makes the switch total: there
		// is no path that reaches MOTIS while the switch says otherwise.
		maasWorkConfig := maas.DefaultMaasSharedWorkConfig
		if httpConfig.MotisEnabled {
			maasWorkConfig.Motis = maas.NewMotisClient(motisBaseURL)
			// The same monitor /api/planner reports, so the backend the app is
			// told about is the backend that answers its next plan request.
			maasWorkConfig.Health = plannerMonitor
		}
		zap.S().Infow("planner selected",
			"component", "maas",
			"action", "startup",
			"backend", maas.BackendName(maasWorkConfig.Motis != nil),
			"motis_base_url", motisBaseURL,
		)
		maasServer := maas.NewMaasServerWithCache(maasCache, db, tdx, maasWorkConfig)
		// Registered after rc/db/maasCache's cleanups above, so in cleanup's
		// LIFO order maas.MaasServer.Close runs first: every shared singleflight
		// flight is canceled and joined before those backends close under it.
		runtime.addCleanup(maasServer.Close)
		pb.RegisterMaasServiceServer(grpcServer, maasServer)
		pb.RegisterFirebase_ServiceServer(grpcServer,
			firebase.NewFirebaseServer(firebase.NewFirebaseStore(db), time.Now, live))
		pb.RegisterFeedback_ServiceServer(grpcServer, feedback.NewFeedbackServer(
			feedback.NewFeedbackStore(db),
			firebase.NewFirebaseStore(db),
			feedback.NewFeedbackNotifier(),
		))
		zap.S().Infow("gRPC server is running", "port", 50051)
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
