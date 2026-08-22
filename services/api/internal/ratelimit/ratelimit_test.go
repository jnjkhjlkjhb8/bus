package ratelimit

import (
	"context"
	"net"
	"testing"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/peer"
	"google.golang.org/grpc/status"
)

type limiterTestAddr string

func (a limiterTestAddr) Network() string { return "tcp" }
func (a limiterTestAddr) String() string  { return string(a) }

func limiterContext(address string) context.Context {
	return peer.NewContext(context.Background(), &peer.Peer{Addr: limiterTestAddr(address)})
}

func TestRateLimiterExpiresBucketsIndependently(t *testing.T) {
	rl := New()
	now := time.Unix(1_800_000_000, 0)
	rl.now = func() time.Time { return now }
	interceptor := UnaryInterceptor(rl, 1, 80*time.Millisecond)
	handler := func(context.Context, any) (any, error) { return "ok", nil }
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
	rl := New()
	now := time.Unix(1_800_000_000, 0)
	rl.now = func() time.Time { return now }
	if !rl.Allow("long", "caller", 1, time.Minute) || !rl.Allow("short", "caller", 1, time.Second) {
		t.Fatal("initial requests were denied")
	}
	now = now.Add(2 * time.Second)
	_ = rl.Allow("long", "caller", 1, time.Minute)
	if got := len(rl.buckets); got != 1 {
		t.Fatalf("expired short-window buckets after cleanup = %d, want only long-window bucket", got)
	}
}
