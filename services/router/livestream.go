package main

import (
	"context"
	"errors"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// LiveSource is the seam between live-stream handlers and Redis. Two adapters
// satisfy it: redisLiveSource in production and fakeLiveSource in tests.
type LiveSource interface {
	// get returns the current payload for key; ok=false when the key is
	// missing or the read failed.
	get(ctx context.Context, key string) ([]byte, bool)
	// scanKeys returns every key matching pattern; best-effort, a failed
	// scan returns what was collected so far.
	scanKeys(ctx context.Context, pattern string) []string
	// subscribe returns a channel of live payloads for channel and a close
	// func the caller must invoke. A closed payload channel means the
	// subscription died. ctx covers establishing the subscription only: the
	// returned channel outlives it and is torn down through the close func.
	subscribe(ctx context.Context, channel string) (<-chan []byte, func(), error)
}

// LiveStreamSpec describes one gRPC live stream: which channel to follow,
// which keys seed a new subscriber, and which payloads are worth sending.
type LiveStreamSpec struct {
	channel  string
	seedKeys []string
	seedScan string            // optional SCAN pattern; matches seed in key order returned
	usable   func([]byte) bool // nil means non-empty
}

var errLiveSourceClosed = errors.New("live source subscription closed")

// liveSourceCloseCause is implemented by sources that can explain a
// specific, reconnectable reason a subscription channel closed — e.g. a
// per-subscriber overflow eviction — distinct from the generic upstream
// disconnect reported as errLiveSourceClosed.
type liveSourceCloseCause interface {
	subscriptionCloseCause(ch <-chan []byte) error
}

// StreamLive runs a live stream to completion: subscribe first (so nothing
// published during seeding is lost), seed from current values, then forward
// updates until ctx is done, send fails, or the subscription closes.
// Payloads failing usable are skipped everywhere, seed and live alike.
func StreamLive(ctx context.Context, src LiveSource, spec LiveStreamSpec, send func([]byte) error) error {
	usable := spec.usable
	if usable == nil {
		usable = func(b []byte) bool { return len(b) > 0 }
	}

	ch, closeSub, err := src.subscribe(ctx, spec.channel)
	if err != nil {
		return err
	}
	defer closeSub()
	// Every return past this point ends an established stream (client
	// disconnect, upstream close, or send failure); a subscribe failure above
	// never started one, so it is not counted here.
	defer obs.IncStreamDisconnect()

	keys := spec.seedKeys
	if spec.seedScan != "" {
		keys = append(keys, src.scanKeys(ctx, spec.seedScan)...)
	}
	for _, k := range keys {
		val, ok := src.get(ctx, k)
		if !ok || !usable(val) {
			continue
		}
		if err := send(val); err != nil {
			return err
		}
	}

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case val, ok := <-ch:
			if !ok {
				if withCause, hasCause := src.(liveSourceCloseCause); hasCause {
					if cause := withCause.subscriptionCloseCause(ch); cause != nil {
						return cause
					}
				}
				zap.S().Infow("source closed",
					"component", "grpc",
					"action", "live_stream",
					"event", "source_closed",
					"channel", spec.channel,
				)
				return errLiveSourceClosed
			}
			if !usable(val) {
				continue
			}
			if err := send(val); err != nil {
				return err
			}
		}
	}
}

// RedisLiveSource adapts *redis.Client to the liveSource seam.
type RedisLiveSource struct {
	rc *redis.Client
}

func (r RedisLiveSource) get(ctx context.Context, key string) ([]byte, bool) {
	val, err := r.rc.Get(ctx, key).Bytes()
	if err != nil {
		// redis.Nil means the key is simply absent -- expected traffic, not a
		// Redis health signal -- so only a real failure counts here.
		if !errors.Is(err, redis.Nil) {
			obs.IncRedisError()
		}
		return nil, false
	}
	return val, true
}

func (r RedisLiveSource) scanKeys(ctx context.Context, pattern string) []string {
	var out []string
	var cursor uint64
	for {
		keys, next, err := r.rc.Scan(ctx, cursor, pattern, 20).Result()
		if err != nil {
			obs.IncRedisError()
			return out
		}
		out = append(out, keys...)
		cursor = next
		if cursor == 0 {
			return out
		}
	}
}

func (r RedisLiveSource) subscribe(ctx context.Context, channel string) (<-chan []byte, func(), error) {
	sub := r.rc.Subscribe(ctx, channel)
	out := make(chan []byte)
	done := make(chan struct{})
	go func() {
		defer close(out)
		in := sub.Channel()
		for {
			select {
			case <-done:
				return
			case msg, ok := <-in:
				if !ok {
					return
				}
				select {
				case out <- []byte(msg.Payload):
				case <-done:
					return
				}
			}
		}
	}()
	return out, func() {
		close(done)
		_ = sub.Close()
	}, nil
}
