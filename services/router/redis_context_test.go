package main

import (
	"context"
	"testing"
	"time"

	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	redis "github.com/redis/go-redis/v9"
)

// contextGovernedRedisOptions mirrors what shared.ConnectRedis builds, with the
// socket timeouts disabled so the context is the *only* thing that can unblock a
// command. ContextTimeoutEnabled is the load-bearing setting: without it go-redis
// applies socket deadlines alone and ignores the context entirely.
func contextGovernedRedisOptions(addr string) *redis.Options {
	return &redis.Options{
		Network: "tcp", Addr: addr,
		MaxRetries:  -1,
		DialTimeout: time.Second,
		// -1 disables the socket deadlines, so a parked server would hang this
		// call forever if cancellation were not wired through.
		ReadTimeout: -1, WriteTimeout: -1,
		PoolSize: 1, PoolTimeout: time.Second,
		Protocol:              2,
		ContextTimeoutEnabled: true,
	}
}

// TestDailyBoundsRedisReadByContextDeadline is the regression test for the v6→v9
// migration. It exercises the whole request chain — the Daily RPC, the
// BusDailytable handler it delegates to, and the Redis GET underneath — against
// a server that accepts the GET and then never answers.
//
// Under go-redis v6 this could not pass: WithContext stored the context but
// nothing on the command path ever read it, so the only escape from a parked
// read was a socket timeout, and those are disabled here.
//
// Note what this does and does not assert. go-redis v9 maps a context *deadline*
// onto the socket deadline; it does not watch Done, so cancelling a
// deadline-less context will not interrupt a command already in flight. A
// deadline is therefore the guarantee callers actually have, and the one worth
// pinning down.
func TestDailyBoundsRedisReadByContextDeadline(t *testing.T) {
	endpoint := startBlockingRedisEndpoint(t, "get")
	client := redis.NewClient(contextGovernedRedisOptions(endpoint.address))
	defer func() { _ = client.Close() }()

	server := &BusRouteserver{rc: client}
	ctx, cancel := context.WithTimeout(context.Background(), 250*time.Millisecond)
	defer cancel()

	done := make(chan error, 1)
	go func() {
		_, err := server.Daily(ctx, &pb.Bus_Ask_Route{SubRouteUID: "KHH1"})
		done <- err
	}()

	select {
	case <-endpoint.commandStarted:
	case err := <-done:
		t.Fatalf("Daily returned %v before the Redis read was even issued", err)
	case <-time.After(2 * time.Second):
		t.Fatal("Redis GET was never issued")
	}

	// The read is now parked server-side with the socket deadlines disabled, so
	// only the context deadline can end it.
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("Daily returned a nil error for a read that was never answered")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("the context deadline did not bound the Redis read: the request context is not reaching go-redis")
	}
}

// TestDailyFailsFastOnAlreadyCancelledContext covers the other half: a context
// that is already done before the call must not reach Redis at all.
func TestDailyFailsFastOnAlreadyCancelledContext(t *testing.T) {
	endpoint := startBlockingRedisEndpoint(t, "get")
	client := redis.NewClient(contextGovernedRedisOptions(endpoint.address))
	defer func() { _ = client.Close() }()

	server := &BusRouteserver{rc: client}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	done := make(chan error, 1)
	go func() {
		_, err := server.Daily(ctx, &pb.Bus_Ask_Route{SubRouteUID: "KHH1"})
		done <- err
	}()

	select {
	case err := <-done:
		if err == nil {
			t.Fatal("Daily returned a nil error for an already-cancelled context")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("Daily blocked on Redis despite an already-cancelled context")
	}
}
