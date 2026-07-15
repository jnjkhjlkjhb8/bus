package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"testing"
	"time"

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
		RateLimit: 1, RateWindow: time.Minute, MaxConcurrent: 1, Timeout: time.Second,
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

func TestMaasResourceInterceptorBoundsConcurrency(t *testing.T) {
	interceptor := maasResourceInterceptor(newRateLimiter(), maasResourceConfig{
		RateLimit: 10, RateWindow: time.Minute, MaxConcurrent: 1, Timeout: time.Second,
	})
	info := &grpc.UnaryServerInfo{FullMethod: pb.MaasService_Plan_FullMethodName}
	started := make(chan struct{})
	release := make(chan struct{})
	firstDone := make(chan error, 1)
	go func() {
		_, err := interceptor(limiterContext(net.JoinHostPort("203.0.113.31", "1234")), nil, info,
			func(context.Context, interface{}) (interface{}, error) {
				close(started)
				<-release
				return "ok", nil
			})
		firstDone <- err
	}()
	<-started

	called := false
	_, err := interceptor(limiterContext(net.JoinHostPort("203.0.113.32", "1234")), nil, info,
		func(context.Context, interface{}) (interface{}, error) {
			called = true
			return "ok", nil
		})
	if status.Code(err) != codes.ResourceExhausted || called {
		t.Fatalf("concurrent MaaS request = (called=%v, code=%v), want rejected", called, status.Code(err))
	}
	close(release)
	if err := <-firstDone; err != nil {
		t.Fatalf("first MaaS request failed: %v", err)
	}
}

func TestMaasResourceInterceptorEnforcesDeadline(t *testing.T) {
	interceptor := maasResourceInterceptor(newRateLimiter(), maasResourceConfig{
		RateLimit: 10, RateWindow: time.Minute, MaxConcurrent: 1, Timeout: 20 * time.Millisecond,
	})
	info := &grpc.UnaryServerInfo{FullMethod: pb.MaasService_Plan_FullMethodName}
	started := time.Now()
	_, err := interceptor(limiterContext(net.JoinHostPort("203.0.113.33", "1234")), nil, info,
		func(ctx context.Context, _ interface{}) (interface{}, error) {
			<-ctx.Done()
			return nil, ctx.Err()
		})
	if status.Code(err) != codes.DeadlineExceeded {
		t.Fatalf("deadline code = %v, want %v (error=%v)", status.Code(err), codes.DeadlineExceeded, err)
	}
	if elapsed := time.Since(started); elapsed > 500*time.Millisecond {
		t.Fatalf("MaaS deadline took %v", elapsed)
	}
}
