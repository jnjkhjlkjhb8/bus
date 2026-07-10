package main

import (
	"context"
	"errors"

	"github.com/go-redis/redis"
)

// liveSource is the seam between live-stream handlers and Redis. Two adapters
// satisfy it: redisLiveSource in production and fakeLiveSource in tests.
type liveSource interface {
	// get returns the current payload for key; ok=false when the key is
	// missing or the read failed.
	get(key string) ([]byte, bool)
	// scanKeys returns every key matching pattern; best-effort, a failed
	// scan returns what was collected so far.
	scanKeys(pattern string) []string
	// subscribe returns a channel of live payloads for channel and a close
	// func the caller must invoke. A closed payload channel means the
	// subscription died.
	subscribe(channel string) (<-chan []byte, func(), error)
}

// liveStreamSpec describes one gRPC live stream: which channel to follow,
// which keys seed a new subscriber, and which payloads are worth sending.
type liveStreamSpec struct {
	channel  string
	seedKeys []string
	seedScan string            // optional SCAN pattern; matches seed in key order returned
	usable   func([]byte) bool // nil means non-empty
}

var errLiveSourceClosed = errors.New("live source subscription closed")

// streamLive runs a live stream to completion: subscribe first (so nothing
// published during seeding is lost), seed from current values, then forward
// updates until ctx is done, send fails, or the subscription closes.
// Payloads failing usable are skipped everywhere, seed and live alike.
func streamLive(ctx context.Context, src liveSource, spec liveStreamSpec, send func([]byte) error) error {
	usable := spec.usable
	if usable == nil {
		usable = func(b []byte) bool { return len(b) > 0 }
	}

	ch, closeSub, err := src.subscribe(spec.channel)
	if err != nil {
		return err
	}
	defer closeSub()

	keys := spec.seedKeys
	if spec.seedScan != "" {
		keys = append(keys, src.scanKeys(spec.seedScan)...)
	}
	for _, k := range keys {
		val, ok := src.get(k)
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
				log.Infof("[gRPC] action=live_stream event=source_closed channel=%s", spec.channel)
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

// redisLiveSource adapts *redis.Client to the liveSource seam.
type redisLiveSource struct {
	rc *redis.Client
}

func (r redisLiveSource) get(key string) ([]byte, bool) {
	val, err := r.rc.Get(key).Bytes()
	if err != nil {
		return nil, false
	}
	return val, true
}

func (r redisLiveSource) scanKeys(pattern string) []string {
	var out []string
	var cursor uint64
	for {
		keys, next, err := r.rc.Scan(cursor, pattern, 20).Result()
		if err != nil {
			return out
		}
		out = append(out, keys...)
		cursor = next
		if cursor == 0 {
			return out
		}
	}
}

func (r redisLiveSource) subscribe(channel string) (<-chan []byte, func(), error) {
	sub := r.rc.Subscribe(channel)
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
