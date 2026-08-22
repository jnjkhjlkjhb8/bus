package pipeline

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"time"

	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// LiveSource is the seam between a live job and TDX. The production adapter
// (RESTLiveSource) wraps the shared TDX client's Get; the test adapter
// (fakeLiveSource) serves committed fixture bytes. fetch mirrors Get's contract
// A Modified=false fetch is a 304 Not-Modified (cached live data still valid).
type LiveSource interface {
	Fetch(ctx context.Context, url, name string) (*shared.TDXFetch, error)
}

// LivePipe is the subset of go-redis pipeline operations live jobs use. It is
// the only write surface a LiveSpec's run closure touches, so the capture fake
// in tests can record every write without a real Redis.
type LivePipe interface {
	Set(key string, value any, ttl time.Duration)
	Publish(channel string, value any)
	HSet(key, field string, value any)
	Expire(key string, ttl time.Duration)
	ReplaceOwnedKeys(key string, members []string, ttl time.Duration)
	// Exec is the only method that touches the network: the others just buffer
	// commands, so the context that governs the round-trip belongs here.
	Exec(ctx context.Context) error
}

// LiveSink is the seam between a live job and Redis. The production adapter
// (RedisLiveSink) wraps *redis.Client; the test adapter (captureLiveSink)
// records every write. pipeline builds one buffered batch; refreshTTL re-arms
// the TTL on every key matching the given patterns (SCAN + EXPIRE), the
// operation the 304 path needs.
type LiveSink interface {
	Pipe() LivePipe
	RefreshTTL(ctx context.Context, patterns []TTLPattern) error
	RefreshOwnedTTL(ctx context.Context, key string, ttl time.Duration) error
	// getString and getHash close the read seam: two jobs need to read a value
	// back from Redis mid-tick (bus reads the cached weather snapshot for
	// prediction features; tra reads the delay hash to merge into the live board),
	// so those reads go through the sink instead of a raw *redis.Client capture.
	GetString(ctx context.Context, key string) (string, error)
	GetHash(ctx context.Context, key string) (map[string]string, error)
}

// TTLPattern pairs a Redis key glob with the TTL to re-arm on a 304
// Not-Modified. Per CONTEXT.md the cached arrival instants stay valid across a
// 304, so their snapshots must outlive the polling gap instead of expiring.
type TTLPattern struct {
	Pattern string
	TTL     time.Duration
}

// LiveSpec is one realtime dataset's recipe: its registry key, cron cadence, the
// key patterns+TTL to re-arm on a 304, and the transform. run receives a
// BoundFetch (a fetch wrapper that auto-refreshes ttlPatterns on a 304) and the
// sink, mirroring loadSpec.load receiving a decoder and db/rc. Transforms keep
// their existing bodies; the spec only injects the source and sink.
type LiveSpec struct {
	Key         string
	Cadence     string
	TTLPatterns func(fetchName string) []TTLPattern
	OwnedKey    func(fetchName string) string
	OwnedTTL    time.Duration
	Run         func(ctx context.Context, fetch BoundFetch, sink LiveSink) error
}

// BoundFetch is the fetch a LiveSpec's run closure calls. It is LiveSource.fetch
// pre-bound to one spec: on a 304 Not-Modified it refreshes that spec's
// ttlPatterns before returning, generalizing the bus-only 304→TTL rule to every
// live job; without it mrt/tra/bike would skip and let their snapshots expire.
// run still checks modified and returns on false; the TTL refresh has already
// happened by then.
type BoundFetch func(ctx context.Context, url, name string) (*shared.TDXFetch, error)

// BindFetch wraps src.fetch so a 304 for this spec re-arms its Redis TTLs
// through sink before the result is returned.
func BindFetch(src LiveSource, sink LiveSink, spec LiveSpec) BoundFetch {
	return func(ctx context.Context, url, name string) (*shared.TDXFetch, error) {
		fetch, err := src.Fetch(ctx, url, name)
		if err == nil && fetch != nil && !fetch.Modified && spec.OwnedKey != nil {
			if refreshErr := sink.RefreshOwnedTTL(ctx, spec.OwnedKey(name), spec.OwnedTTL); refreshErr != nil {
				invalidateErr := InvalidateTDXFetch(fetch)
				if invalidateErr != nil {
					invalidateErr = _oops.With("name", name).Wrapf(invalidateErr, "invalidate marker after owned-key refresh failure")
				}
				return nil, errors.Join(
					_oops.With("name", name).Wrapf(refreshErr, "refresh owned live keys"),
					invalidateErr,
				)
			}
		} else if err == nil && fetch != nil && !fetch.Modified && spec.TTLPatterns != nil {
			// 304 Not-Modified: the cached live data is still valid, so re-arm its
			// TTL instead of letting it expire mid-validity (CONTEXT.md).
			if refreshErr := sink.RefreshTTL(ctx, spec.TTLPatterns(name)); refreshErr != nil {
				return nil, _oops.With("name", name).Wrapf(refreshErr, "refresh live TTLs")
			}
		}
		return fetch, err
	}
}

// bufferedPrefix returns what the decoder has already buffered, capped so a
// megabyte of unexpected payload cannot reach the log through an error string.
func bufferedPrefix(dec *json.Decoder) string {
	const limit = 256
	buf := make([]byte, limit)
	n, _ := io.ReadFull(dec.Buffered(), buf)
	if n == limit {
		return string(buf[:n]) + "…"
	}
	return string(buf[:n])
}

// DecodeLiveItems strictly consumes one JSON array. Unlike the static-loader
// decoder, realtime snapshots must fail closed: skipping a malformed element
// and acknowledging the response would make the partial Redis snapshot look
// complete on the next conditional request.
func DecodeLiveItems[T any](dec *json.Decoder, fn func(T) error) error {
	opening, err := dec.Token()
	if err != nil {
		return err
	}
	if opening != json.Delim('[') {
		// The token alone ("{") does not say whether TDX wrapped the array in an
		// envelope or returned an error object, and the body is gone by the time
		// the error is read. Carry a bounded prefix of what is still buffered.
		return _oops.With("opening", opening).With("prefix", bufferedPrefix(dec)).Errorf("TDX payload is not a JSON array")
	}
	for dec.More() {
		var value T
		if err := dec.Decode(&value); err != nil {
			return err
		}
		if err := fn(value); err != nil {
			return err
		}
	}
	closing, err := dec.Token()
	if err != nil {
		return err
	}
	if closing != json.Delim(']') {
		return _oops.With("closing", closing).Errorf("TDX payload ends with, want array")
	}
	var trailing any
	if err := dec.Decode(&trailing); errors.Is(err, io.EOF) {
		return nil
	} else if err != nil {
		return _oops.Wrapf(err, "decode TDX payload trailer")
	}
	return errors.New("TDX payload contains trailing data")
}

// CommitTDXFetch acknowledges the conditional marker only after process has
// durably published the full snapshot. Close is attempted on every path and its
// error is joined with the primary processing or acknowledgement error.
func CommitTDXFetch(fetch *shared.TDXFetch, process func(*json.Decoder) error) error {
	if fetch == nil || !fetch.Modified || fetch.Decoder == nil {
		return errors.New("cannot commit an empty TDX fetch")
	}
	if fetch.Close == nil {
		return errors.New("cannot commit a TDX fetch without Close")
	}
	if err := process(fetch.Decoder); err != nil {
		closeErr := fetch.Close()
		if closeErr != nil {
			closeErr = _oops.Wrapf(closeErr, "close TDX fetch")
		}
		return errors.Join(err, closeErr)
	}
	if err := fetch.Close(); err != nil {
		return _oops.Wrapf(err, "close TDX fetch")
	}
	return AcknowledgeTDXFetch(fetch)
}

func AcknowledgeTDXFetch(fetch *shared.TDXFetch) error {
	if fetch == nil || fetch.Ack == nil {
		return errors.New("modified TDX fetch has no acknowledgement")
	}
	if err := fetch.Ack(); err != nil {
		return _oops.Wrapf(err, "acknowledge TDX fetch")
	}
	return nil
}

// RunLive executes the named live jobs once. keys selects registry entries by
// LiveSpec.key; an empty keys slice runs every registered job. Each job runs
// under its own isolation: a panic or error is logged and does not abort the
// others (mirrors runLoadSpecs' per-partition isolation).
func RunLive(ctx context.Context, src LiveSource, sink LiveSink, specs []LiveSpec, keys []string) {
	if len(keys) > 0 {
		want := map[string]bool{}
		for _, k := range keys {
			want[k] = true
		}
		filtered := specs[:0:0]
		for _, s := range specs {
			if want[s.Key] {
				filtered = append(filtered, s)
			}
		}
		specs = filtered
	}
	for _, spec := range specs {
		RunLiveSpec(ctx, src, sink, spec)
	}
}

// runLiveSpec runs one live job with panic recovery and start/complete
// logging. A failing job logs and returns so the runner can move to the next
// one.
func RunLiveSpec(ctx context.Context, src LiveSource, sink LiveSink, spec LiveSpec) {
	defer func() {
		if r := recover(); r != nil {
			zap.S().Errorw("panic",
				"component", "live",
				"action", "run",
				"event", "panic",
				"job", spec.Key,
				"recovered", r,
			)
		}
	}()
	zap.S().Infow("start", "component", "live", "action", "run", "event", "start", "job", spec.Key)
	fetch := BindFetch(src, sink, spec)
	if err := spec.Run(ctx, fetch, sink); err != nil {
		zap.S().Errorw("error", "component", "live", "action", "run", "event", "error", "job", spec.Key, "err", err)
		return
	}
	zap.S().Infow("complete", "component", "live", "action", "run", "event", "complete", "job", spec.Key)
}

// RESTLiveSource is the production LiveSource: it wraps the shared TDX client's
// streaming conditional GET, which fetches a TDX endpoint under an
// If-Modified-Since guard and streams the body.
type RESTLiveSource struct {
	tdx *shared.TDXClient
}

var _ LiveSource = RESTLiveSource{}

// fetch delegates to the shared TDX client's context-aware conditional Get.
func (s RESTLiveSource) Fetch(ctx context.Context, url, name string) (*shared.TDXFetch, error) {
	return s.tdx.Get(ctx, url, name)
}

// RedisLiveSink is the production LiveSink backed by *redis.Client. refreshTTL
// re-arms matching keys via SCAN + pipelined EXPIRE, shared by every live job's
// 304 path.
type RedisLiveSink struct {
	rc *redis.Client
}

var _ LiveSink = RedisLiveSink{}

func (s RedisLiveSink) Pipe() LivePipe {
	options := s.rc.Options()
	return &redisLivePipe{
		pipe: s.rc.TxPipeline(),
		finiteWait: options.DialTimeout > 0 && options.ReadTimeout > 0 &&
			options.WriteTimeout > 0 && options.PoolTimeout > 0,
	}
}

// getString reads a single string value, delegating to the underlying client so
// a missing key surfaces redis.Nil to the caller rather than a sink-specific
// error the jobs would each have to translate.
func (s RedisLiveSink) GetString(ctx context.Context, key string) (string, error) {
	return s.rc.Get(ctx, key).Result()
}

// getHash reads a whole hash, used by the tra job to merge cached per-train
// delays into the live board.
func (s RedisLiveSink) GetHash(ctx context.Context, key string) (map[string]string, error) {
	return s.rc.HGetAll(ctx, key).Result()
}

// refreshTTL re-arms the TTL on every key matching each pattern via SCAN +
// pipelined EXPIRE. Errors are logged, wrapped, and returned so a failed 304
// refresh cannot be reported as a successful live tick.
func (s RedisLiveSink) RefreshTTL(ctx context.Context, patterns []TTLPattern) error {
	rc := s.rc
	total := 0
	var refreshErr error
	for _, p := range patterns {
		var cursor uint64
		for {
			keys, next, err := rc.Scan(ctx, cursor, p.Pattern, 500).Result()
			if err != nil {
				refreshErr = errors.Join(refreshErr, _oops.With("pattern", p.Pattern).Wrapf(err, "scan TTL pattern"))
				break
			}
			if len(keys) > 0 {
				pipe := rc.Pipeline()
				for _, k := range keys {
					pipe.Expire(ctx, k, p.TTL)
				}
				if _, err := pipe.Exec(ctx); err != nil {
					refreshErr = errors.Join(refreshErr, _oops.With("pattern", p.Pattern).Wrapf(err, "expire TTL pattern"))
					break
				}
				total += len(keys)
			}
			cursor = next
			if cursor == 0 {
				break
			}
		}
	}
	if refreshErr != nil {
		return refreshErr
	}
	zap.S().Infow("success", "component", "live", "action", "ttl_refresh", "event", "success", "keys", total)
	return nil
}

func (s RedisLiveSink) RefreshOwnedTTL(ctx context.Context, key string, ttl time.Duration) error {
	rc := s.rc
	members, err := rc.SMembers(ctx, key).Result()
	if err != nil {
		return _oops.With("key", key).Wrapf(err, "read ownership set")
	}
	if len(members) == 0 {
		return nil
	}
	pipe := rc.Pipeline()
	expires := make([]*redis.BoolCmd, 0, len(members))
	for _, member := range members {
		expires = append(expires, pipe.Expire(ctx, member, ttl))
	}
	if _, err := pipe.Exec(ctx); err != nil {
		return _oops.With("key", key).Wrapf(err, "refresh ownership set")
	}
	var missing []string
	for i, command := range expires {
		exists, err := command.Result()
		if err != nil {
			return _oops.With("members", members[i]).Wrapf(err, "inspect owned key")
		}
		if !exists {
			missing = append(missing, members[i])
		}
	}
	if len(missing) > 0 {
		// Keep the stale membership until marker invalidation succeeds and the
		// resulting full fetch atomically replaces it. Deleting it here would make
		// a failed invalidation invisible to the next 304, preventing a retry.
		return _oops.With("key", key).
			With("missing_count", len(missing)).
			With("missing_sample", missing[:min(len(missing), 5)]).
			Errorf("ownership set contains missing live keys")
	}
	renewed, err := rc.Expire(ctx, key, OwnedKeysTTL).Result()
	if err != nil {
		return _oops.With("key", key).Wrapf(err, "refresh ownership metadata")
	}
	if !renewed {
		return _oops.With("key", key).Errorf("refresh ownership metadata: key disappeared")
	}
	return nil
}

// redisLivePipe adapts a go-redis Pipeliner to the LivePipe interface, dropping
// the per-command result handles the live jobs never inspect (they only Exec).
//
// Queuing a command never touches the network — the v9 pipeline appends to a
// buffer and discards the context it is handed — so the buffering methods pass
// context.Background() and Exec's context is the one that governs the round-trip.
type redisLivePipe struct {
	pipe       redis.Pipeliner
	finiteWait bool
}

var _ LivePipe = (*redisLivePipe)(nil)

func (p *redisLivePipe) Set(key string, value any, ttl time.Duration) {
	p.pipe.Set(context.Background(), key, value, ttl)
}

func (p *redisLivePipe) Publish(channel string, value any) {
	p.pipe.Publish(context.Background(), channel, value)
}

func (p *redisLivePipe) HSet(key, field string, value any) {
	p.pipe.HSet(context.Background(), key, field, value)
}

func (p *redisLivePipe) Expire(key string, ttl time.Duration) {
	p.pipe.Expire(context.Background(), key, ttl)
}

func (p *redisLivePipe) ReplaceOwnedKeys(key string, members []string, ttl time.Duration) {
	ctx := context.Background()
	p.pipe.Del(ctx, key)
	if len(members) == 0 {
		return
	}
	values := make([]any, len(members))
	for i := range members {
		values[i] = members[i]
	}
	p.pipe.SAdd(ctx, key, values...)
	p.pipe.Expire(ctx, key, ttl)
}

func (p *redisLivePipe) Exec(ctx context.Context) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if !p.finiteWait {
		return errors.New("live Redis pipeline requires finite Redis read timeout and connection timeouts")
	}
	// EXEC now runs under the caller's context, but the finite client timeouts
	// are kept as a floor: an unbounded context must still not let a transaction
	// land after this returns and overwrite a newer run. A context that expires
	// during the wait is joined with the Redis result so callers never
	// acknowledge their TDX marker, even if EXEC itself succeeded.
	_, execErr := p.pipe.Exec(ctx)
	return errors.Join(execErr, ctx.Err())
}

// TTL windows re-armed on a 304, per the CONTEXT.md operating rule. They match
// the SET TTLs each job writes on the success path so a 304 extends a snapshot
// by exactly one more validity window: bus 180s, mrt/bike 2min, tra 3min, thsr
// seats 15min (a slow 10min cadence, so the snapshot outlives one missed refresh).
const (
	BusLiveTTL       = 180 * time.Second
	MrtLiveTTL       = 2 * time.Minute
	BikeLiveTTL      = 2 * time.Minute
	TraLiveTTL       = 3 * time.Minute
	ThsrSeatsLiveTTL = 15 * time.Minute
	OwnedKeysTTL     = 24 * time.Hour
)

// The reduced cadence an unwatched city falls back to, and the window a rider's
// live subscription keeps their city at full cadence for (FDPL-90). Bus and bike
// poll all 23 TDX cities every 30s regardless of whether anyone is looking,
// which is ~99% of this project's TDX request budget; a city nobody is watching
// does not need a 30s refresh, only a fresh enough one to answer the next rider.
//
// The two are a pair, not independent knobs. liveDemandTTL must stay above
// liveColdCadence: a cold city publishes nothing, so a subscriber's own initial
// write is the only thing that can mark it watched, and that write has to
// outlive the gap until the next reduced-cadence tick actually produces a frame.
// Invert them and a cold city can never warm up.
const (
	LiveColdCadence = 5 * time.Minute
)

// LiveDemandGate reports whether dataset's city should be fetched this tick.
//
// A watched city always is. An unwatched one is fetched once per
// liveColdCadence, which the cold marker's own TTL times: while the marker
// exists the tick is skipped, and its expiry is what lets the next one through.
// No timestamp is stored anywhere; Redis expiry is the clock.
//
// A Redis read that fails outright answers true. Losing freshness for every
// city is a far worse failure than spending the requests the job would have
// spent anyway, so the gate degrades to the pre-FDPL-90 behaviour.
func LiveDemandGate(ctx context.Context, sink LiveSink, dataset, city string) bool {
	_, err := sink.GetString(ctx, shared.LiveDemandKey(dataset, city))
	if err == nil {
		return true
	}
	if !errors.Is(err, redis.Nil) {
		zap.S().Warnw("demand read failed",
			"component", "live",
			"action", "demand_gate",
			"dataset", dataset,
			"city", city,
			"event", "failed",
			"err", err,
		)
		return true
	}

	coldKey := shared.LiveColdKey(dataset, city)
	_, err = sink.GetString(ctx, coldKey)
	if err == nil {
		return false
	}
	if !errors.Is(err, redis.Nil) {
		return true
	}

	// Claim this cadence window before fetching. A failed write only costs the
	// next tick a second fetch, so it is logged rather than turned into a skip.
	pipe := sink.Pipe()
	pipe.Set(coldKey, "1", LiveColdCadence)
	if err := pipe.Exec(ctx); err != nil {
		zap.S().Warnw("cold marker write failed",
			"component", "live",
			"action", "demand_gate",
			"dataset", dataset,
			"city", city,
			"event", "failed",
			"err", err,
		)
	}
	return true
}

func InvalidateTDXFetch(fetch *shared.TDXFetch) error {
	if fetch == nil || fetch.Invalidate == nil {
		return errors.New("TDX fetch has no marker invalidation callback")
	}
	return fetch.Invalidate()
}

// NewRESTLiveSource adapts the shared TDX client to the live fetch seam.
func NewRESTLiveSource(tdx *shared.TDXClient) RESTLiveSource { return RESTLiveSource{tdx: tdx} }

// NewRedisLiveSink adapts a Redis client to the live write seam.
func NewRedisLiveSink(rc *redis.Client) RedisLiveSink { return RedisLiveSink{rc: rc} }
