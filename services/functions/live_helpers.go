package main

import (
	"encoding/json"
	"time"

	"google.golang.org/protobuf/proto"
)

// decodeItems is the streaming decode skeleton the simple live jobs share: it
// guards the opening array token, then decodes each element into a T and hands
// it to fn. A per-element decode error skips that element (matching the jobs'
// `if err := dec.Decode(&x); err == nil` bodies); a missing opening token is
// returned so the caller can skip the whole feed as before.
func decodeItems[T any](dec *json.Decoder, fn func(T)) error {
	if _, err := dec.Token(); err != nil { // opening '['
		return err
	}
	for dec.More() {
		var v T
		if err := dec.Decode(&v); err != nil {
			continue
		}
		fn(v)
	}
	return nil
}

// publishProto is the decode-and-publish helper for the per-item-proto jobs: for
// each decoded T it maps to a Redis key, an optional publish channel, and a
// protobuf payload, then pipelines SET key=payload (ttl) and, when channel is
// non-empty, PUBLISH channel=payload. A mapping that reports ok=false or a
// payload that fails to marshal is skipped, exactly like the inline loops. It is
// built on decodeItems so it shares the same token guard and skip semantics.
func publishProto[T any](dec *json.Decoder, pipe livePipe, ttl time.Duration,
	mapItem func(T) (key, channel string, msg proto.Message, ok bool)) error {
	return decodeItems(dec, func(v T) {
		key, channel, msg, ok := mapItem(v)
		if !ok {
			return
		}
		pb, err := proto.Marshal(msg)
		if err != nil {
			return
		}
		pipe.Set(key, pb, ttl)
		if channel != "" {
			pipe.Publish(channel, string(pb))
		}
	})
}
