package main

// Per-caller request rate limiting, and the generic gRPC interceptors that
// spend from it. The buckets are in-process: the router runs as a single
// replica, so a shared store would add a dependency for no extra accuracy.

import (
	"context"
	"net"
	"sync"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/peer"
	"google.golang.org/grpc/status"
)

type RateLimiter struct {
	mu          sync.Mutex
	buckets     map[string]rateBucket
	nextCleanup time.Time
	now         func() time.Time
}

type rateBucket struct {
	count     int
	expiresAt time.Time
}

func NewRateLimiter() *RateLimiter {
	return &RateLimiter{
		buckets: make(map[string]rateBucket, 128),
		now:     time.Now,
	}
}

func (r *RateLimiter) allow(scope, caller string, limit int, window time.Duration) bool {
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
func RateLimitInterceptor(rl *RateLimiter, limit int, window time.Duration) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
		if !AllowRequest(ctx, rl, info.FullMethod, limit, window) {
			return nil, status.Error(codes.ResourceExhausted, "rate limit exceeded")
		}
		return handler(ctx, req)
	}
}
func RateLimitStreamInterceptor(rl *RateLimiter, limit int, window time.Duration) grpc.StreamServerInterceptor {
	return func(srv any, ss grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) error {
		if !AllowRequest(ss.Context(), rl, info.FullMethod, limit, window) {
			return status.Error(codes.ResourceExhausted, "rate limit exceeded")
		}
		return handler(srv, ss)
	}
}
func AllowRequest(ctx context.Context, rl *RateLimiter, scope string, limit int, window time.Duration) bool {
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
