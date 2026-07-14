package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/functions/notify"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
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
	Exec() error
}

// liveSink is the seam between a live job and Redis. The production adapter
// (redisLiveSink) wraps *redis.Client; the test adapter (captureLiveSink)
// records every write. pipeline builds one buffered batch; refreshTTL re-arms
// the TTL on every key matching the given patterns (SCAN + EXPIRE), the
// operation the 304 path needs.
type liveSink interface {
	pipelineContext(ctx context.Context) livePipe
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
// live job (mrt/tra/bike previously just skipped and let their snapshots
// expire). run still checks modified and returns on false; the TTL refresh has
// already happened by then.
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
		return fmt.Errorf("TDX payload starts with %v, want array", opening)
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
	if err := dec.Decode(&trailing); err == io.EOF {
		return nil
	} else if err != nil {
		return err
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

// runLiveSpec runs one live job with panic recovery and start/complete logging.
// A failing job logs and returns so the runner can move to the next one.
func runLiveSpec(ctx context.Context, src liveSource, sink liveSink, spec liveSpec) {
	defer func() {
		if r := recover(); r != nil {
			log.Infof("[LIVE] action=run event=panic job=%s recovered=%v", spec.key, r)
		}
	}()
	log.Infof("[LIVE] action=run event=start job=%s", spec.key)
	fetch := bindFetch(src, sink, spec)
	if err := spec.run(ctx, fetch, sink); err != nil {
		log.Infof("[LIVE] action=run event=error job=%s error=%v", spec.key, err)
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
// re-arms matching keys via SCAN + pipelined EXPIRE, the logic previously inline
// in refreshBusEtaTTLs, now shared by every live job's 304 path.
type redisLiveSink struct {
	rc *redis.Client
}

func (s redisLiveSink) pipelineContext(ctx context.Context) livePipe {
	options := s.rc.Options()
	return &redisLivePipe{
		pipe: s.rc.WithContext(ctx).TxPipeline(),
		ctx:  ctx,
		finiteWait: options.DialTimeout > 0 && options.ReadTimeout > 0 &&
			options.WriteTimeout > 0 && options.PoolTimeout > 0,
	}
}

// getString reads a single string value, delegating to the underlying client so
// a missing key surfaces the same redis.Nil error the jobs previously handled
// inline.
func (s redisLiveSink) getString(ctx context.Context, key string) (string, error) {
	return s.rc.WithContext(ctx).Get(key).Result()
}

// getHash reads a whole hash, used by the tra job to merge cached per-train
// delays into the live board.
func (s redisLiveSink) getHash(ctx context.Context, key string) (map[string]string, error) {
	return s.rc.WithContext(ctx).HGetAll(key).Result()
}

// refreshTTL re-arms the TTL on every key matching each pattern via SCAN +
// pipelined EXPIRE. Errors are logged, wrapped, and returned so a failed 304
// refresh cannot be reported as a successful live tick.
func (s redisLiveSink) refreshTTL(ctx context.Context, patterns []ttlPattern) error {
	rc := s.rc.WithContext(ctx)
	total := 0
	var refreshErr error
	for _, p := range patterns {
		var cursor uint64
		for {
			keys, next, err := rc.Scan(cursor, p.pattern, 500).Result()
			if err != nil {
				log.Infof("[LIVE] action=ttl_refresh event=scan_error pattern=%s error=%v", p.pattern, err)
				refreshErr = errors.Join(refreshErr, fmt.Errorf("scan TTL pattern %s: %w", p.pattern, err))
				break
			}
			if len(keys) > 0 {
				pipe := rc.Pipeline()
				for _, k := range keys {
					pipe.Expire(k, p.ttl)
				}
				if _, err := pipe.Exec(); err != nil {
					log.Infof("[LIVE] action=ttl_refresh event=expire_error pattern=%s error=%v", p.pattern, err)
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
	rc := s.rc.WithContext(ctx)
	members, err := rc.SMembers(key).Result()
	if err != nil {
		return fmt.Errorf("read ownership set %s: %w", key, err)
	}
	if len(members) == 0 {
		return nil
	}
	pipe := rc.Pipeline()
	expires := make([]*redis.BoolCmd, 0, len(members))
	for _, member := range members {
		expires = append(expires, pipe.Expire(member, ttl))
	}
	if _, err := pipe.Exec(); err != nil {
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
	renewed, err := rc.Expire(key, ownedKeysTTL).Result()
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
type redisLivePipe struct {
	pipe       redis.Pipeliner
	ctx        context.Context
	finiteWait bool
}

func (p *redisLivePipe) Set(key string, value any, ttl time.Duration) {
	p.pipe.Set(key, value, ttl)
}

func (p *redisLivePipe) Publish(channel string, value any) {
	p.pipe.Publish(channel, value)
}

func (p *redisLivePipe) HSet(key, field string, value any) {
	p.pipe.HSet(key, field, value)
}

func (p *redisLivePipe) Expire(key string, ttl time.Duration) {
	p.pipe.Expire(key, ttl)
}

func (p *redisLivePipe) ReplaceOwnedKeys(key string, members []string, ttl time.Duration) {
	p.pipe.Del(key)
	if len(members) == 0 {
		return
	}
	values := make([]interface{}, len(members))
	for i := range members {
		values[i] = members[i]
	}
	p.pipe.SAdd(key, values...)
	p.pipe.Expire(key, ttl)
}

func (p *redisLivePipe) Exec() error {
	if err := p.ctx.Err(); err != nil {
		return err
	}
	if !p.finiteWait {
		return errors.New("live Redis pipeline requires finite Redis read timeout and connection timeouts")
	}
	// go-redis v6 stores Context on the client but does not apply it to pipeline
	// socket deadlines. Execute synchronously under the finite client timeouts so
	// no transaction can land after this call returns and overwrite a newer run.
	// A context that expires during the wait is joined with the Redis result so
	// callers never acknowledge its TDX marker, even if EXEC itself succeeded.
	_, execErr := p.pipe.Exec()
	return errors.Join(execErr, p.ctx.Err())
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
// the order runLegacyProd previously invoked them within a shared cron tick
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
	mrtOwnedKey := func(fetchName string) string {
		return shared.LiveOwnedKeysKey("mrt", strings.TrimPrefix(fetchName, "mrt_LiveBoard"))
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
		// bus keeps ttlPatterns nil: it fetches per city and re-arms exactly that
		// city's keys inline (processBusEtaCity → sink.refreshTTL(busEtaTTLPatterns))
		// on a 304, which is more precise than a whole-keyspace scan and avoids
		// re-scanning every city's keys on each city's 304. boundFetch's generic
		// refresh is for the jobs that previously skipped (bike/mrt/tra).
		{key: "bus", cadence: "@every 30s", ttlPatterns: nil,
			run: func(ctx context.Context, fetch boundFetch, sink liveSink) error {
				return busEta(ctx, fetch, sink, db, dispatcher)
			}},
		{key: "mrt", cadence: "@every 10s", ownedKey: mrtOwnedKey, ownedTTL: mrtLiveTTL,
			run: func(ctx context.Context, fetch boundFetch, sink liveSink) error {
				return mrtEta(ctx, fetch, sink, db)
			}},
		{key: "tra", cadence: "@every 2m", ttlPatterns: traPatterns,
			run: func(ctx context.Context, fetch boundFetch, sink liveSink) error {
				return traEta(ctx, fetch, sink)
			}},
		// THSR available-seat status changes slowly, so it refreshes on a
		// conservative 10-minute cadence (its own cron entry, unbounded like
		// mrt/tra). This is the seat refresh moved off the router's read path
		// (ADR-0005 amendment).
		{key: "thsr_seats", cadence: "@every 10m", ttlPatterns: thsrSeatsPatterns,
			run: func(ctx context.Context, fetch boundFetch, sink liveSink) error {
				return thsrAvailableSeats(ctx, fetch, sink)
			}},
	}
}

// liveJobTimeout is the per-tick bound on the 30s bus/bike group: each spec runs
// under a 25s deadline so a slow city cannot bleed into the next 30s tick. The
// slower jobs (mrt 10s, tra 2m) kept no per-tick timeout before this refactor,
// and keep none, to preserve exact behavior.
const liveJobTimeout = 25 * time.Second

// registerLiveCrons schedules the realtime ETA jobs from liveRegistry, one cron
// entry per distinct cadence, preserving the pre-refactor grouping and ordering:
// bus and bike share the "@every 30s" tick and run bike-then-bus in registry
// order, each under a 25s timeout; mrt runs on 10s and tra on 2m, unbounded, as
// before. Every job goes through runLiveSpec, so a failing job is isolated and
// logged and the 304→TTL refresh applies uniformly.
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
		bounded := cadence == "@every 30s"
		_, _ = r.AddFunc(cadence, func() {
			log.Infof("[LIVE] action=tick event=start cadence=%s jobs=%d", cadence, len(group))
			for _, spec := range group {
				if bounded {
					withTimeout(liveJobTimeout, func(ctx context.Context) {
						runLiveSpec(ctx, src, sink, spec)
					})
				} else {
					runLiveSpec(context.Background(), src, sink, spec)
				}
			}
			log.Infof("[LIVE] action=tick event=end cadence=%s", cadence)
		})
	}

	// Rail arrival reminders fire on a schedule (fire_at = arrival − lead) rather
	// than off a live ETA, so they dispatch on their own tick. Nil-safe when push
	// is disabled.
	_, _ = r.AddFunc("@every 30s", func() {
		withTimeout(liveJobTimeout, func(ctx context.Context) {
			dispatcher.FireScheduled(ctx)
		})
	})
}
