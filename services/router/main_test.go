package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/getsentry/sentry-go"
	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5"
	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/peer"
	"google.golang.org/grpc/status"
)

func TestUsableBusEtaPayloadRejectsEmptyPayload(t *testing.T) {
	if usableBusEtaPayload(nil) {
		t.Fatal("nil payload should not be sent")
	}
	if usableBusEtaPayload([]byte{}) {
		t.Fatal("empty payload should not be sent")
	}
	if !usableBusEtaPayload([]byte{1}) {
		t.Fatal("non-empty payload should be sent")
	}
}

func TestGrpcStatusFor(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want codes.Code
	}{
		{"pgx no rows", pgx.ErrNoRows, codes.NotFound},
		{"redis nil", redis.Nil, codes.NotFound},
		{"obs not found", obs.NotFound(errors.New("missing")), codes.NotFound},
		{"other", errors.New("boom"), codes.Internal},
	}
	for _, tc := range cases {
		if got := status.Code(grpcStatusFor(tc.err, "not found")); got != tc.want {
			t.Fatalf("%s got %v want %v", tc.name, got, tc.want)
		}
	}
}

type limiterTestAddr string

func (a limiterTestAddr) Network() string { return "tcp" }
func (a limiterTestAddr) String() string  { return string(a) }

func limiterContext(address string) context.Context {
	return peer.NewContext(context.Background(), &peer.Peer{Addr: limiterTestAddr(address)})
}

type coordinatorEventLog struct {
	mu     sync.Mutex
	events []string
}

func (l *coordinatorEventLog) add(event string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.events = append(l.events, event)
}

func (l *coordinatorEventLog) snapshot() []string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return append([]string(nil), l.events...)
}

type blockingFakeGRPCServer struct {
	events         *coordinatorEventLog
	started        chan struct{}
	serveResult    chan error
	handlerRelease chan struct{}
	handlerDone    chan struct{}
	stopOnce       sync.Once
	forceStop      chan struct{}
	forceOnce      sync.Once
}

func newBlockingFakeGRPCServer(events *coordinatorEventLog) *blockingFakeGRPCServer {
	server := &blockingFakeGRPCServer{
		events: events, started: make(chan struct{}), serveResult: make(chan error, 1),
		handlerRelease: make(chan struct{}), handlerDone: make(chan struct{}),
	}
	go func() {
		<-server.handlerRelease
		events.add("grpc handler done")
		close(server.handlerDone)
	}()
	return server
}

func (s *blockingFakeGRPCServer) Serve(net.Listener) error {
	close(s.started)
	err := <-s.serveResult
	s.events.add("grpc serve returned")
	return err
}

func (s *blockingFakeGRPCServer) GracefulStop() {
	s.events.add("grpc stop")
	if s.forceStop != nil {
		<-s.forceStop
		return
	}
	s.stopOnce.Do(func() { close(s.handlerRelease) })
	<-s.handlerDone
	select {
	case s.serveResult <- nil:
	default:
	}
}

func (s *blockingFakeGRPCServer) Stop() {
	s.events.add("grpc force stop")
	if s.forceStop != nil {
		s.forceOnce.Do(func() { close(s.forceStop) })
	}
	s.stopOnce.Do(func() { close(s.handlerRelease) })
	<-s.handlerDone
	select {
	case s.serveResult <- nil:
	default:
	}
}

type blockingFakeHTTPServer struct {
	events         *coordinatorEventLog
	started        chan struct{}
	serveResult    chan error
	handlerRelease chan struct{}
	handlerDone    chan struct{}
	stopOnce       sync.Once
	shutdownErr    error
}

func newBlockingFakeHTTPServer(events *coordinatorEventLog) *blockingFakeHTTPServer {
	server := &blockingFakeHTTPServer{
		events: events, started: make(chan struct{}), serveResult: make(chan error, 1),
		handlerRelease: make(chan struct{}), handlerDone: make(chan struct{}),
	}
	go func() {
		<-server.handlerRelease
		events.add("http handler done")
		close(server.handlerDone)
	}()
	return server
}

func (s *blockingFakeHTTPServer) Serve(net.Listener) error {
	close(s.started)
	err := <-s.serveResult
	s.events.add("http serve returned")
	return err
}

func (s *blockingFakeHTTPServer) Shutdown(ctx context.Context) error {
	s.events.add("http stop")
	if s.shutdownErr != nil {
		return s.shutdownErr
	}
	select {
	case s.serveResult <- http.ErrServerClosed:
	default:
	}
	s.stopOnce.Do(func() { close(s.handlerRelease) })
	select {
	case <-s.handlerDone:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (s *blockingFakeHTTPServer) Close() error {
	s.events.add("http force close")
	select {
	case s.serveResult <- http.ErrServerClosed:
	default:
	}
	s.stopOnce.Do(func() { close(s.handlerRelease) })
	<-s.handlerDone
	return nil
}

func eventIndex(events []string, target string) int {
	for index, event := range events {
		if event == target {
			return index
		}
	}
	return -1
}

func assertEventBefore(t *testing.T, events []string, earlier, later string) {
	t.Helper()
	earlierIndex, laterIndex := eventIndex(events, earlier), eventIndex(events, later)
	if earlierIndex < 0 || laterIndex < 0 || earlierIndex >= laterIndex {
		t.Fatalf("event order %q before %q not satisfied: %v", earlier, later, events)
	}
}

func TestServerCoordinatorStopsHandlersBeforeBackendCleanup(t *testing.T) {
	for _, failingServer := range []string{"grpc", "http"} {
		t.Run(failingServer+" failure", func(t *testing.T) {
			wantErr := errors.New(failingServer + " failed")
			var capturedErr error
			events := &coordinatorEventLog{}
			grpcServer := newBlockingFakeGRPCServer(events)
			httpServer := newBlockingFakeHTTPServer(events)
			runtime := &routerRuntime{}
			err := runtime.run(func() error {
				runtime.addCleanup(func() { events.add("sentry flush") })
				runtime.addCleanup(func() { events.add("backend cleanup") })
				go func() {
					<-grpcServer.started
					<-httpServer.started
					if failingServer == "grpc" {
						grpcServer.serveResult <- wantErr
					} else {
						httpServer.serveResult <- wantErr
					}
				}()
				coordinator := serverCoordinator{
					grpcServer: grpcServer, httpServer: httpServer,
					shutdownTimeout: time.Second,
					capture: func(err error) {
						capturedErr = err
						events.add("capture")
					},
				}
				return coordinator.serve(nil, nil)
			})
			if !errors.Is(err, wantErr) {
				t.Fatalf("coordinator error = %v, want wrapped %v", err, wantErr)
			}
			if !errors.Is(capturedErr, wantErr) {
				t.Fatalf("captured error = %v, want wrapped %v", capturedErr, wantErr)
			}
			got := events.snapshot()
			assertEventBefore(t, got, "grpc stop", "grpc handler done")
			assertEventBefore(t, got, "http stop", "http handler done")
			assertEventBefore(t, got, "grpc handler done", "backend cleanup")
			assertEventBefore(t, got, "http handler done", "backend cleanup")
			assertEventBefore(t, got, "grpc serve returned", "backend cleanup")
			assertEventBefore(t, got, "http serve returned", "backend cleanup")
			assertEventBefore(t, got, "capture", "backend cleanup")
			assertEventBefore(t, got, "backend cleanup", "sentry flush")
		})
	}
}

func TestServerCoordinatorUsesForcedShutdownFallbacks(t *testing.T) {
	for _, fallback := range []string{"grpc stop", "http close"} {
		t.Run(fallback, func(t *testing.T) {
			events := &coordinatorEventLog{}
			grpcServer := newBlockingFakeGRPCServer(events)
			httpServer := newBlockingFakeHTTPServer(events)
			if fallback == "grpc stop" {
				grpcServer.forceStop = make(chan struct{})
			} else {
				httpServer.shutdownErr = errors.New("shutdown timed out")
			}
			go func() {
				<-grpcServer.started
				<-httpServer.started
				if fallback == "grpc stop" {
					httpServer.serveResult <- errors.New("HTTP failed")
				} else {
					grpcServer.serveResult <- errors.New("gRPC failed")
				}
			}()
			coordinator := serverCoordinator{
				grpcServer: grpcServer, httpServer: httpServer,
				shutdownTimeout: 5 * time.Millisecond,
			}
			done := make(chan error, 1)
			go func() { done <- coordinator.serve(nil, nil) }()
			select {
			case err := <-done:
				if err == nil {
					t.Fatal("coordinator returned nil after serve failure")
				}
			case <-time.After(time.Second):
				t.Fatal("forced shutdown fallback did not terminate coordinator")
			}
			got := events.snapshot()
			if fallback == "grpc stop" {
				assertEventBefore(t, got, "grpc stop", "grpc force stop")
				assertEventBefore(t, got, "grpc force stop", "grpc handler done")
			} else {
				assertEventBefore(t, got, "http stop", "http force close")
				assertEventBefore(t, got, "http force close", "http handler done")
			}
		})
	}
}

func TestServerCoordinatorShutsDownOnSignal(t *testing.T) {
	events := &coordinatorEventLog{}
	grpcServer := newBlockingFakeGRPCServer(events)
	httpServer := newBlockingFakeHTTPServer(events)
	shutdown := make(chan os.Signal, 1)
	var capturedErr error
	captureCalled := false
	coordinator := serverCoordinator{
		grpcServer: grpcServer, httpServer: httpServer,
		shutdownTimeout: time.Second,
		shutdown:        shutdown,
		capture: func(err error) {
			capturedErr = err
			captureCalled = true
			events.add("capture")
		},
	}
	done := make(chan error, 1)
	go func() { done <- coordinator.serve(nil, nil) }()
	<-grpcServer.started
	<-httpServer.started
	shutdown <- syscall.SIGTERM

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("coordinator error = %v, want nil for signal-triggered shutdown", err)
		}
	case <-time.After(time.Second):
		t.Fatal("signal did not trigger coordinated shutdown")
	}
	if !captureCalled {
		t.Fatal("capture was not invoked on signal-triggered shutdown")
	}
	if capturedErr != nil {
		t.Fatalf("captured error = %v, want nil", capturedErr)
	}
	got := events.snapshot()
	assertEventBefore(t, got, "grpc stop", "grpc handler done")
	assertEventBefore(t, got, "http stop", "http handler done")
	if count := 0; true {
		for _, event := range got {
			if event == "grpc stop" {
				count++
			}
		}
		if count != 1 {
			t.Fatalf("grpc stop invoked %d times, want exactly once", count)
		}
	}
}

func TestServerCoordinatorSignalAndServeErrorShutDownExactlyOnce(t *testing.T) {
	// A signal and a Serve failure can race in production (e.g. SIGTERM
	// arrives right as a listener dies). The coordinator must run the
	// coordinated stop path exactly once regardless of which fires first.
	events := &coordinatorEventLog{}
	grpcServer := newBlockingFakeGRPCServer(events)
	httpServer := newBlockingFakeHTTPServer(events)
	shutdown := make(chan os.Signal, 1)
	coordinator := serverCoordinator{
		grpcServer: grpcServer, httpServer: httpServer,
		shutdownTimeout: time.Second,
		shutdown:        shutdown,
	}
	done := make(chan error, 1)
	go func() { done <- coordinator.serve(nil, nil) }()
	<-grpcServer.started
	<-httpServer.started

	// Fire the signal and a Serve failure concurrently.
	go func() { shutdown <- syscall.SIGTERM }()
	go func() { grpcServer.serveResult <- errors.New("gRPC failed") }()

	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("coordinator did not terminate under a signal/serve-error race")
	}
	got := events.snapshot()
	stopCount, httpStopCount := 0, 0
	for _, event := range got {
		if event == "grpc stop" {
			stopCount++
		}
		if event == "http stop" {
			httpStopCount++
		}
	}
	if stopCount != 1 {
		t.Fatalf("grpc stop invoked %d times, want exactly once", stopCount)
	}
	if httpStopCount != 1 {
		t.Fatalf("http stop invoked %d times, want exactly once", httpStopCount)
	}
}

func TestRateLimitInterceptorScopesQuotaByMethodAndCaller(t *testing.T) {
	rl := newRateLimiter()
	interceptor := rateLimitInterceptor(rl, 1, time.Minute)
	handler := func(context.Context, interface{}) (interface{}, error) { return "ok", nil }
	ctx := limiterContext(net.JoinHostPort("203.0.113.10", "1234"))

	methodA := &grpc.UnaryServerInfo{FullMethod: "/Service/A"}
	methodB := &grpc.UnaryServerInfo{FullMethod: "/Service/B"}
	if _, err := interceptor(ctx, nil, methodA, handler); err != nil {
		t.Fatalf("first method A call failed: %v", err)
	}
	if _, err := interceptor(ctx, nil, methodB, handler); err != nil {
		t.Fatalf("method B consumed method A quota: %v", err)
	}
	if _, err := interceptor(ctx, nil, methodA, handler); status.Code(err) != codes.ResourceExhausted {
		t.Fatalf("second method A code = %v, want %v", status.Code(err), codes.ResourceExhausted)
	}
}

func TestRateLimiterExpiresBucketsIndependently(t *testing.T) {
	rl := newRateLimiter()
	now := time.Unix(1_800_000_000, 0)
	rl.now = func() time.Time { return now }
	interceptor := rateLimitInterceptor(rl, 1, 80*time.Millisecond)
	handler := func(context.Context, interface{}) (interface{}, error) { return "ok", nil }
	info := &grpc.UnaryServerInfo{FullMethod: "/Service/A"}
	callerA := limiterContext(net.JoinHostPort("203.0.113.11", "1234"))
	callerB := limiterContext(net.JoinHostPort("203.0.113.12", "1234"))

	if _, err := interceptor(callerA, nil, info, handler); err != nil {
		t.Fatal(err)
	}
	now = now.Add(50 * time.Millisecond)
	if _, err := interceptor(callerB, nil, info, handler); err != nil {
		t.Fatal(err)
	}
	now = now.Add(45 * time.Millisecond)
	if _, err := interceptor(callerB, nil, info, handler); status.Code(err) != codes.ResourceExhausted {
		t.Fatalf("caller B bucket was reset by caller A expiry: code=%v", status.Code(err))
	}
	if got := len(rl.buckets); got != 1 {
		t.Fatalf("expired buckets after cleanup = %d, want only caller B", got)
	}
	if _, err := interceptor(callerA, nil, info, handler); err != nil {
		t.Fatalf("expired caller A bucket was not renewed: %v", err)
	}
}

func TestRateLimiterCleanupHonorsShortestBucketWindow(t *testing.T) {
	rl := newRateLimiter()
	now := time.Unix(1_800_000_000, 0)
	rl.now = func() time.Time { return now }
	if !rl.allow("long", "caller", 1, time.Minute) || !rl.allow("short", "caller", 1, time.Second) {
		t.Fatal("initial requests were denied")
	}
	now = now.Add(2 * time.Second)
	_ = rl.allow("long", "caller", 1, time.Minute)
	if got := len(rl.buckets); got != 1 {
		t.Fatalf("expired short-window buckets after cleanup = %d, want only long-window bucket", got)
	}
}

func TestRateLimitInterceptorAlwaysUsesPeerIPForFirebasePreAuth(t *testing.T) {
	rl := newRateLimiter()
	interceptor := rateLimitInterceptor(rl, 1, time.Minute)
	handler := func(context.Context, interface{}) (interface{}, error) { return "ok", nil }
	info := &grpc.UnaryServerInfo{FullMethod: "/Firebase_Service/upsertDevice"}
	sharedPeer := &peer.Peer{Addr: limiterTestAddr(net.JoinHostPort("203.0.113.20", "1234"))}
	installContext := func(installID string) context.Context {
		ctx := metadata.NewIncomingContext(context.Background(), metadata.Pairs(installIDMetadataKey, installID))
		return peer.NewContext(ctx, sharedPeer)
	}

	if _, err := interceptor(installContext("install-a"), nil, info, handler); err != nil {
		t.Fatal(err)
	}
	if _, err := interceptor(installContext("install-b"), nil, info, handler); status.Code(err) != codes.ResourceExhausted {
		t.Fatalf("rotated unverified install ID bypassed peer-IP quota: code=%v", status.Code(err))
	}
}

func TestInstallationRateLimitSeparatesVerifiedInstallations(t *testing.T) {
	interceptor := installationRateLimitInterceptor(newRateLimiter(), 1, time.Minute)
	handler := func(context.Context, interface{}) (interface{}, error) { return "ok", nil }
	info := &grpc.UnaryServerInfo{FullMethod: pb.Firebase_Service_UpsertDevice_FullMethodName}
	requestContext := func(installID string) context.Context {
		return metadata.NewIncomingContext(context.Background(), metadata.Pairs(installIDMetadataKey, installID))
	}
	if _, err := interceptor(requestContext("install-a"), nil, info, handler); err != nil {
		t.Fatal(err)
	}
	if _, err := interceptor(requestContext("install-b"), nil, info, handler); err != nil {
		t.Fatalf("verified installation fairness bucket leaked across IDs: %v", err)
	}
	if _, err := interceptor(requestContext("install-a"), nil, info, handler); status.Code(err) != codes.ResourceExhausted {
		t.Fatalf("second install-a call code = %v", status.Code(err))
	}
}

func invokeUnaryChain(interceptors []grpc.UnaryServerInterceptor, ctx context.Context, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
	chained := handler
	for index := len(interceptors) - 1; index >= 0; index-- {
		current := interceptors[index]
		next := chained
		chained = func(ctx context.Context, req interface{}) (interface{}, error) {
			return current(ctx, req, info, next)
		}
	}
	return chained(ctx, nil)
}

func TestProductionFirebaseUnaryChainBoundsRotatingInstallIDsByPeer(t *testing.T) {
	interceptors := productionUnaryInterceptors(fakeAppCheckVerifier{}, true)
	info := &grpc.UnaryServerInfo{FullMethod: pb.Firebase_Service_UpsertDevice_FullMethodName}
	handlerCalls := 0
	handler := func(context.Context, interface{}) (interface{}, error) {
		handlerCalls++
		return "ok", nil
	}
	for requestNumber := 1; requestNumber <= 31; requestNumber++ {
		ctx := metadata.NewIncomingContext(context.Background(), metadata.Pairs(
			appCheckMetadataKey, "valid",
			installIDMetadataKey, fmt.Sprintf("rotated-%d", requestNumber),
		))
		ctx = peer.NewContext(ctx, &peer.Peer{Addr: limiterTestAddr(net.JoinHostPort("203.0.113.25", "1234"))})
		_, err := invokeUnaryChain(interceptors, ctx, info, handler)
		if requestNumber <= 30 && err != nil {
			t.Fatalf("request %d failed early: %v", requestNumber, err)
		}
		if requestNumber == 31 && status.Code(err) != codes.ResourceExhausted {
			t.Fatalf("rotating IDs request 31 code = %v, want %v", status.Code(err), codes.ResourceExhausted)
		}
	}
	if handlerCalls != 30 {
		t.Fatalf("handler calls = %d, want 30", handlerCalls)
	}
}

func TestRateLimitInterceptorIgnoresInstallationMetadataOutsideFirebase(t *testing.T) {
	rl := newRateLimiter()
	interceptor := rateLimitInterceptor(rl, 1, time.Minute)
	handler := func(context.Context, interface{}) (interface{}, error) { return "ok", nil }
	info := &grpc.UnaryServerInfo{FullMethod: pb.MaasService_Plan_FullMethodName}
	sharedPeer := &peer.Peer{Addr: limiterTestAddr(net.JoinHostPort("203.0.113.21", "1234"))}
	requestContext := func(spoofedInstallID string) context.Context {
		ctx := metadata.NewIncomingContext(context.Background(), metadata.Pairs(installIDMetadataKey, spoofedInstallID))
		return peer.NewContext(ctx, sharedPeer)
	}

	if _, err := interceptor(requestContext("spoof-a"), nil, info, handler); err != nil {
		t.Fatal(err)
	}
	if _, err := interceptor(requestContext("spoof-b"), nil, info, handler); status.Code(err) != codes.ResourceExhausted {
		t.Fatalf("spoofed install ID bypassed non-Firebase IP quota: code=%v", status.Code(err))
	}
}

func TestMaasResourceInterceptorHasDedicatedRateLimit(t *testing.T) {
	interceptor := maasResourceInterceptor(newRateLimiter(), maasResourceConfig{
		RateLimit: 1, RateWindow: time.Minute,
	})
	handler := func(context.Context, interface{}) (interface{}, error) { return "ok", nil }
	ctx := limiterContext(net.JoinHostPort("203.0.113.30", "1234"))
	other := &grpc.UnaryServerInfo{FullMethod: "/OtherService/read"}
	maas := &grpc.UnaryServerInfo{FullMethod: pb.MaasService_Plan_FullMethodName}

	for range 2 {
		if _, err := interceptor(ctx, nil, other, handler); err != nil {
			t.Fatalf("non-MaaS method was limited by MaaS bucket: %v", err)
		}
	}
	if _, err := interceptor(ctx, nil, maas, handler); err != nil {
		t.Fatalf("first MaaS request failed: %v", err)
	}
	if _, err := interceptor(ctx, nil, maas, handler); status.Code(err) != codes.ResourceExhausted {
		t.Fatalf("second MaaS request code = %v, want %v", status.Code(err), codes.ResourceExhausted)
	}
}

// TestReportProcessFailureBypassesSentryAfterFlush covers the final line
// main() prints when run() fails. By that point Init's deferred cleanup has
// already flushed the Sentry client (obs.Init's cleanup, which flushes
// Sentry, runs last among runtime.run's cleanups — see
// TestServerCoordinatorStopsHandlersBeforeBackendCleanup for the ordering),
// so routing this message through log.Errorf/slog would silently enqueue an
// event nothing ever flushes. reportProcessFailure must write directly to
// the given writer and never touch Sentry.
func TestReportProcessFailureBypassesSentryAfterFlush(t *testing.T) {
	previousClient := sentry.CurrentHub().Client()
	t.Setenv("SENTRY_DSN", "https://key@example.com/1")
	flush := obs.Init("router-test")
	defer func() {
		flush()
		sentry.CurrentHub().BindClient(previousClient)
	}()

	options := sentry.CurrentHub().Client().Options()
	transport := &sentry.MockTransport{}
	options.Transport = transport
	client, err := sentry.NewClient(options)
	if err != nil {
		t.Fatal(err)
	}
	sentry.CurrentHub().BindClient(client)

	// Simulate run() returning after Sentry has already been flushed.
	flush()

	var buf bytes.Buffer
	serveErr := errors.New("gRPC server failed: listen closed")
	reportProcessFailure(&buf, serveErr)

	if got := buf.String(); !strings.Contains(got, serveErr.Error()) {
		t.Fatalf("process-failure output = %q, want it to contain %q", got, serveErr.Error())
	}
	if got := len(transport.Events()); got != 0 {
		t.Fatalf("reportProcessFailure enqueued %d Sentry event(s) after flush, want 0", got)
	}
}
