package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/functions/notify"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"github.com/robfig/cron/v3"
)

// This file is the live counterpart of loader.go : the realtime ETA
// fan-out as one runner module with two seams. Each live job is a liveSpec whose
// TDX source and Redis sink are adapters, so tests replay recorded fixtures
// instead of calling TDX (CONTEXT.md "live job"). The runner owns per-job
// isolation, start/complete logging, and the CONTEXT.md 304→TTL-refresh rule for
// every job — not just bus.

// liveSource is the seam between a live job and TDX. The production adapter
// (restLiveSource) wraps the shared TDX client's Get; the test adapter
// (fakeLiveSource) serves committed fixture bytes. fetch mirrors Get's contract
// A Modified=false fetch is a 304 Not-Modified (cached live data still valid).
type liveSource interface {
	fetch(ctx context.Context, url, name string) (*shared.TDXFetch, error)
}

// livePipe is the subset of go-redis pipeline operations live jobs use. It is
// the only write surface a liveSpec's run closure touches, so the capture fake
// in tests can record every write without a real Redis.
type livePipe interface {
	Set(key string, value any, ttl time.Duration)
	Publish(channel string, value any)
	HSet(key, field string, value any)
	Expire(key string, ttl time.Duration)
	ReplaceOwnedKeys(key string, members []string, ttl time.Duration)
	// Exec is the only method that touches the network: the others just buffer
	// commands, so the context that governs the round-trip belongs here.
	Exec(ctx context.Context) error
}

// liveSink is the seam between a live job and Redis. The production adapter
// (redisLiveSink) wraps *redis.Client; the test adapter (captureLiveSink)
// records every write. pipeline builds one buffered batch; refreshTTL re-arms
// the TTL on every key matching the given patterns (SCAN + EXPIRE), the
// operation the 304 path needs.
type liveSink interface {
	pipeline() livePipe
	refreshTTL(ctx context.Context, patterns []ttlPattern) error
	refreshOwnedTTL(ctx context.Context, key string, ttl time.Duration) error
	// getString and getHash close the read seam: two jobs need to read a value
	// back from Redis mid-tick (bus reads the cached weather snapshot for
	// prediction features; tra reads the delay hash to merge into the live board),
	// so those reads go through the sink instead of a raw *redis.Client capture.
	getString(ctx context.Context, key string) (string, error)
	getHash(ctx context.Context, key string) (map[string]string, error)
}

// ttlPattern pairs a Redis key glob with the TTL to re-arm on a 304
// Not-Modified. Per CONTEXT.md the cached arrival instants stay valid across a
// 304, so their snapshots must outlive the polling gap instead of expiring.
type ttlPattern struct {
	pattern string
	ttl     time.Duration
}

// liveSpec is one realtime dataset's recipe: its registry key, cron cadence, the
// key patterns+TTL to re-arm on a 304, and the transform. run receives a
// boundFetch (a fetch wrapper that auto-refreshes ttlPatterns on a 304) and the
// sink, mirroring loadSpec.load receiving a decoder and db/rc. Transforms keep
// their existing bodies; the spec only injects the source and sink.
type liveSpec struct {
	key         string
	cadence     string
	ttlPatterns func(fetchName string) []ttlPattern
	ownedKey    func(fetchName string) string
	ownedTTL    time.Duration
	run         func(ctx context.Context, fetch boundFetch, sink liveSink) error
}

// boundFetch is the fetch a liveSpec's run closure calls. It is liveSource.fetch
// pre-bound to one spec: on a 304 Not-Modified it refreshes that spec's
// ttlPatterns before returning, generalizing the bus-only 304→TTL rule to every
// live job; without it mrt/tra/bike would skip and let their snapshots expire.
// run still checks modified and returns on false; the TTL refresh has already
// happened by then.
type boundFetch func(ctx context.Context, url, name string) (*shared.TDXFetch, error)

// bindFetch wraps src.fetch so a 304 for this spec re-arms its Redis TTLs
// through sink before the result is returned.
func bindFetch(src liveSource, sink liveSink, spec liveSpec) boundFetch {
	return func(ctx context.Context, url, name string) (*shared.TDXFetch, error) {
		fetch, err := src.fetch(ctx, url, name)
		if err == nil && fetch != nil && !fetch.Modified && spec.ownedKey != nil {
			if refreshErr := sink.refreshOwnedTTL(ctx, spec.ownedKey(name), spec.ownedTTL); refreshErr != nil {
				invalidateErr := invalidateTDXFetch(fetch)
				if invalidateErr != nil {
					invalidateErr = fmt.Errorf("invalidate %s marker after owned-key refresh failure: %w", name, invalidateErr)
				}
				return nil, errors.Join(
					fmt.Errorf("refresh %s owned live keys: %w", name, refreshErr),
					invalidateErr,
				)
			}
		} else if err == nil && fetch != nil && !fetch.Modified && spec.ttlPatterns != nil {
			// 304 Not-Modified: the cached live data is still valid, so re-arm its
			// TTL instead of letting it expire mid-validity (CONTEXT.md).
			if refreshErr := sink.refreshTTL(ctx, spec.ttlPatterns(name)); refreshErr != nil {
				return nil, fmt.Errorf("refresh %s live TTLs: %w", name, refreshErr)
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

// decodeLiveItems strictly consumes one JSON array. Unlike the static-loader
// decoder, realtime snapshots must fail closed: skipping a malformed element
// and acknowledging the response would make the partial Redis snapshot look
// complete on the next conditional request.
func decodeLiveItems[T any](dec *json.Decoder, fn func(T) error) error {
	opening, err := dec.Token()
	if err != nil {
		return err
	}
	if opening != json.Delim('[') {
		// The token alone ("{") does not say whether TDX wrapped the array in an
		// envelope or returned an error object, and the body is gone by the time
		// the error is read. Carry a bounded prefix of what is still buffered.
		return fmt.Errorf("TDX payload starts with %v, want array: %s", opening, bufferedPrefix(dec))
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
		return fmt.Errorf("TDX payload ends with %v, want array", closing)
	}
	var trailing any
	if err := dec.Decode(&trailing); errors.Is(err, io.EOF) {
		return nil
	} else if err != nil {
		return fmt.Errorf("decode TDX payload trailer: %w", err)
	}
	return errors.New("TDX payload contains trailing data")
}

// commitTDXFetch acknowledges the conditional marker only after process has
// durably published the full snapshot. Close is attempted on every path and its
// error is joined with the primary processing or acknowledgement error.
func commitTDXFetch(fetch *shared.TDXFetch, process func(*json.Decoder) error) error {
	if fetch == nil || !fetch.Modified || fetch.Decoder == nil {
		return errors.New("cannot commit an empty TDX fetch")
	}
	if fetch.Close == nil {
		return errors.New("cannot commit a TDX fetch without Close")
	}
	if err := process(fetch.Decoder); err != nil {
		closeErr := fetch.Close()
		if closeErr != nil {
			closeErr = fmt.Errorf("close TDX fetch: %w", closeErr)
		}
		return errors.Join(err, closeErr)
	}
	if err := fetch.Close(); err != nil {
		return fmt.Errorf("close TDX fetch: %w", err)
	}
	return acknowledgeTDXFetch(fetch)
}

func acknowledgeTDXFetch(fetch *shared.TDXFetch) error {
	if fetch == nil || fetch.Ack == nil {
		return errors.New("modified TDX fetch has no acknowledgement")
	}
	if err := fetch.Ack(); err != nil {
		return fmt.Errorf("acknowledge TDX fetch: %w", err)
	}
	return nil
}

// runLive executes the named live jobs once. keys selects registry entries by
// liveSpec.key; an empty keys slice runs every registered job. Each job runs
// under its own isolation: a panic or error is logged and does not abort the
// others (mirrors runLoadSpecs' per-partition isolation).
func runLive(ctx context.Context, src liveSource, sink liveSink, specs []liveSpec, keys []string) {
	if len(keys) > 0 {
		want := map[string]bool{}
		for _, k := range keys {
			want[k] = true
		}
		filtered := specs[:0:0]
		for _, s := range specs {
			if want[s.key] {
				filtered = append(filtered, s)
			}
		}
		specs = filtered
	}
	for _, spec := range specs {
		runLiveSpec(ctx, src, sink, spec)
	}
}

// runLiveSpec runs one live job with panic recovery and start/complete
// logging. A failing job logs and returns so the runner can move to the next
// one.
func runLiveSpec(ctx context.Context, src liveSource, sink liveSink, spec liveSpec) {
	defer func() {
		if r := recover(); r != nil {
			log.Errorf("[LIVE] action=run event=panic job=%s recovered=%v", spec.key, r)
		}
	}()
	log.Infof("[LIVE] action=run event=start job=%s", spec.key)
	fetch := bindFetch(src, sink, spec)
	if err := spec.run(ctx, fetch, sink); err != nil {
		log.Errorf("[LIVE] action=run event=error job=%s error=%v", spec.key, err)
		return
	}
	log.Infof("[LIVE] action=run event=complete job=%s", spec.key)
}

// restLiveSource is the production liveSource: it wraps the shared TDX client's
// streaming conditional GET, which fetches a TDX endpoint under an
// If-Modified-Since guard and streams the body.
type restLiveSource struct {
	tdx *shared.TDXClient
}

// fetch delegates to the shared TDX client's context-aware conditional Get.
func (s restLiveSource) fetch(ctx context.Context, url, name string) (*shared.TDXFetch, error) {
	return s.tdx.Get(ctx, url, name)
}

// redisLiveSink is the production liveSink backed by *redis.Client. refreshTTL
// re-arms matching keys via SCAN + pipelined EXPIRE, shared by every live job's
// 304 path.
type redisLiveSink struct {
	rc *redis.Client
}

func (s redisLiveSink) pipeline() livePipe {
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
func (s redisLiveSink) getString(ctx context.Context, key string) (string, error) {
	return s.rc.Get(ctx, key).Result()
}

// getHash reads a whole hash, used by the tra job to merge cached per-train
// delays into the live board.
func (s redisLiveSink) getHash(ctx context.Context, key string) (map[string]string, error) {
	return s.rc.HGetAll(ctx, key).Result()
}

// refreshTTL re-arms the TTL on every key matching each pattern via SCAN +
// pipelined EXPIRE. Errors are logged, wrapped, and returned so a failed 304
// refresh cannot be reported as a successful live tick.
func (s redisLiveSink) refreshTTL(ctx context.Context, patterns []ttlPattern) error {
	rc := s.rc
	total := 0
	var refreshErr error
	for _, p := range patterns {
		var cursor uint64
		for {
			keys, next, err := rc.Scan(ctx, cursor, p.pattern, 500).Result()
			if err != nil {
				refreshErr = errors.Join(refreshErr, fmt.Errorf("scan TTL pattern %s: %w", p.pattern, err))
				break
			}
			if len(keys) > 0 {
				pipe := rc.Pipeline()
				for _, k := range keys {
					pipe.Expire(ctx, k, p.ttl)
				}
				if _, err := pipe.Exec(ctx); err != nil {
					refreshErr = errors.Join(refreshErr, fmt.Errorf("expire TTL pattern %s: %w", p.pattern, err))
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
	log.Infof("[LIVE] action=ttl_refresh event=success keys=%d", total)
	return nil
}

func (s redisLiveSink) refreshOwnedTTL(ctx context.Context, key string, ttl time.Duration) error {
	rc := s.rc
	members, err := rc.SMembers(ctx, key).Result()
	if err != nil {
		return fmt.Errorf("read ownership set %s: %w", key, err)
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
		return fmt.Errorf("refresh ownership set %s: %w", key, err)
	}
	missing := make([]string, 0)
	for i, command := range expires {
		exists, err := command.Result()
		if err != nil {
			return fmt.Errorf("inspect owned key %s: %w", members[i], err)
		}
		if !exists {
			missing = append(missing, members[i])
		}
	}
	if len(missing) > 0 {
		// Keep the stale membership until marker invalidation succeeds and the
		// resulting full fetch atomically replaces it. Deleting it here would make
		// a failed invalidation invisible to the next 304, preventing a retry.
		return fmt.Errorf("ownership set %s contains missing live keys %v", key, missing)
	}
	renewed, err := rc.Expire(ctx, key, ownedKeysTTL).Result()
	if err != nil {
		return fmt.Errorf("refresh ownership metadata %s: %w", key, err)
	}
	if !renewed {
		return fmt.Errorf("refresh ownership metadata %s: key disappeared", key)
	}
	return nil
}

// redisLivePipe adapts a go-redis Pipeliner to the livePipe interface, dropping
// the per-command result handles the live jobs never inspect (they only Exec).
//
// Queuing a command never touches the network — the v9 pipeline appends to a
// buffer and discards the context it is handed — so the buffering methods pass
// context.Background() and Exec's context is the one that governs the round-trip.
type redisLivePipe struct {
	pipe       redis.Pipeliner
	finiteWait bool
}

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
	busLiveTTL       = 180 * time.Second
	mrtLiveTTL       = 2 * time.Minute
	bikeLiveTTL      = 2 * time.Minute
	traLiveTTL       = 3 * time.Minute
	thsrSeatsLiveTTL = 15 * time.Minute
	ownedKeysTTL     = 24 * time.Hour
)

// liveRegistry lists every realtime dataset the runner knows how to refresh, in
// the order runLegacyProd invokes them within a shared cron tick
// (bike before bus on the 30s tick). db and dispatcher are captured by the specs
// that need them (bus needs both for the static-map join, prediction, history,
// and notifications; bike needs db for history sampling), mirroring how
// loaderRegistry captures src for the bus spec. No spec captures a raw
// *redis.Client: the two jobs that read Redis mid-tick (bus weather, tra delay
// hash) now go through the liveSink read seam.
func liveRegistry(db *pgxpool.Pool, dispatcher *notify.Dispatcher) []liveSpec {
	bikeOwnedKey := func(fetchName string) string {
		return shared.LiveOwnedKeysKey("bike", strings.TrimPrefix(fetchName, "bike_availability"))
	}
	traPatterns := func(string) []ttlPattern {
		return []ttlPattern{
			{pattern: shared.TraDelayAllKey, ttl: traLiveTTL},
			{pattern: shared.TraDelayHashKey, ttl: traLiveTTL},
			{pattern: shared.TraDelayTrainChannel("*"), ttl: traLiveTTL},
		}
	}
	thsrSeatsPatterns := func(string) []ttlPattern {
		// Re-arm today's per-train seat keys on a 304; the date is resolved when the
		// 304 fires so the pattern always targets the current service day.
		return []ttlPattern{{pattern: shared.ThsrSeatsPattern(time.Now().In(taipei).Format(time.DateOnly)), ttl: thsrSeatsLiveTTL}}
	}
	return []liveSpec{
		{key: "bike", cadence: "@every 30s", ownedKey: bikeOwnedKey, ownedTTL: bikeLiveTTL,
			run: func(ctx context.Context, fetch boundFetch, sink liveSink) error {
				return bikeEta(ctx, fetch, sink, db)
			}},
		// bus keeps ttlPatterns nil, so boundFetch does not re-arm on its 304.
		// It does not need to: a 304 city still republishes from the cached raw
		// feed, and that write sets a fresh TTL. What does need re-arming is a
		// city run that aborts before publishing, which runCity owns in one
		// deferred guard covering all of its error returns. Wiring ttlPatterns
		// here instead would SCAN and EXPIRE the city's keys on every 304 only
		// for the republish to overwrite them moments later.
		{key: "bus", cadence: "@every 30s", ttlPatterns: nil,
			run: func(ctx context.Context, fetch boundFetch, sink liveSink) error {
				return busEta(ctx, fetch, sink, db, dispatcher)
			}},
		// TDX Metro LiveBoard is paused for all four systems (ADR-0014): TRTC
		// arrivals+congestion come from the Metro Taipei API on a 15s cadence;
		// KRTC/KLRT/TYMC live keys simply expire. To resume TDX, restore the
		// mrtEta spec ({key: "mrt", cadence: "@every 10s", ownedKey: mrtOwnedKey,
		// ownedTTL: mrtLiveTTL, run: mrtEta}).
		{key: "mrt", cadence: "@every 15s",
			run: func(ctx context.Context, fetch boundFetch, sink liveSink) error {
				return trtcEta(ctx, sink, db)
			}},
		{key: "tra", cadence: "@every 2m", ttlPatterns: traPatterns, run: traEta},
		// THSR available-seat status changes slowly, so it refreshes on a
		// conservative 10-minute cadence (its own cron entry, unbounded like
		// mrt/tra). This is the seat refresh moved off the router's read path
		// (ADR-0005 amendment).
		{key: "thsr_seats", cadence: "@every 10m", ttlPatterns: thsrSeatsPatterns, run: thsrAvailableSeats},
	}
}

// liveJobTimeout is the whole-tick bound on the "@every 30s" bus/bike group
// (and the separate reminders tick sharing that cadence): 5s under the 30s
// period, matching liveTickDeadline's own margin for that cadence. Kept as a
// named constant because it is also used for the reminders tick, which has no
// liveRegistry cadence entry of its own.
const liveJobTimeout = 25 * time.Second

// liveTickDeadline returns a deadline strictly under cadence's period, leaving
// a one-sixth margin so a full tick's jobs cannot bleed past the next tick and
// collide with SkipIfStillRunning's overlap guard under ordinary conditions.
// Every liveRegistry cadence is "@every <duration>"; an unparseable or
// non-positive cadence falls back to liveJobTimeout rather than leaving the
// tick unbounded.
func liveTickDeadline(cadence string) time.Duration {
	d, err := time.ParseDuration(strings.TrimPrefix(cadence, "@every "))
	if err != nil || d <= 0 {
		return liveJobTimeout
	}
	return d - d/6
}

// registerLiveCrons schedules the realtime ETA jobs from liveRegistry, one cron
// entry per distinct cadence, preserving the pre-refactor grouping and ordering:
// bus and bike share the "@every 30s" tick and run bike-then-bus in registry
// order. Every cadence's whole tick (not each spec individually) runs under a
// single liveTickDeadline bound, so a slow job cannot let the group's total
// runtime bleed past the next tick; a spec that would start after the
// deadline is skipped and logged rather than started. Every cadence entry also
// carries cron.SkipIfStillRunning so an overrunning tick is skipped rather than
// stacking concurrent runs of the same job. Every job goes through
// runLiveSpec, so a failing job is isolated and logged and the 304→TTL
// refresh applies uniformly.
func registerLiveCrons(r *cron.Cron, tdx *shared.TDXClient, rc *redis.Client, db *pgxpool.Pool, dispatcher *notify.Dispatcher) {
	src := restLiveSource{tdx: tdx}
	sink := redisLiveSink{rc: rc}
	specs := liveRegistry(db, dispatcher)

	// Group specs by cadence, keeping registry order within each group so the
	// 30s tick still runs bike before bus.
	order := []string{}
	byCadence := map[string][]liveSpec{}
	for _, s := range specs {
		if _, seen := byCadence[s.cadence]; !seen {
			order = append(order, s.cadence)
		}
		byCadence[s.cadence] = append(byCadence[s.cadence], s)
	}

	for _, cadence := range order {
		group := byCadence[cadence]
		deadline := liveTickDeadline(cadence)
		_, _ = addStaticCron(r, cadence, func() {
			log.Infof("[LIVE] action=tick event=start cadence=%s jobs=%d deadline=%s", cadence, len(group), deadline)
			withTimeout(deadline, func(ctx context.Context) {
				for _, spec := range group {
					if ctx.Err() != nil {
						log.Warnf("[LIVE] action=tick event=overrun cadence=%s deadline=%s job=%s", cadence, deadline, spec.key)
						break
					}
					runLiveSpec(ctx, src, sink, spec)
				}
			})
			log.Infof("[LIVE] action=tick event=end cadence=%s", cadence)
		})
	}

	// Rail arrival reminders fire on a schedule (fire_at = arrival − lead) rather
	// than off a live ETA, so they dispatch on their own tick. Nil-safe when push
	// is disabled.
	_, _ = addStaticCron(r, "@every 30s", func() {
		withTimeout(liveJobTimeout, func(ctx context.Context) {
			if err := dispatcher.FireScheduled(ctx); err != nil {
				log.Errorf("[LIVE] action=run event=error job=scheduled_reminders error=%v", err)
			}
		})
	})
}
