package main

import (
	"context"
	"encoding/json"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5/pgxpool"
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
// (restLiveSource) wraps callApi; the test adapter (fakeLiveSource) serves
// committed fixture bytes. fetch mirrors callApi's contract with the ordering
// normalized to (dec, modified, close, err): modified=false && err==nil is a 304
// Not-Modified (cached live data still valid); close closes the response body
// and is nil when there is nothing to close.
type liveSource interface {
	fetch(ctx context.Context, url, name string) (dec *json.Decoder, modified bool, close func(), err error)
}

// livePipe is the subset of go-redis pipeline operations live jobs use. It is
// the only write surface a liveSpec's run closure touches, so the capture fake
// in tests can record every write without a real Redis.
type livePipe interface {
	Set(key string, value any, ttl time.Duration)
	Publish(channel string, value any)
	HSet(key, field string, value any)
	Expire(key string, ttl time.Duration)
	Exec() error
}

// liveSink is the seam between a live job and Redis. The production adapter
// (redisLiveSink) wraps *redis.Client; the test adapter (captureLiveSink)
// records every write. pipeline builds one buffered batch; refreshTTL re-arms
// the TTL on every key matching the given patterns (SCAN + EXPIRE), the
// operation the 304 path needs.
type liveSink interface {
	pipeline() livePipe
	refreshTTL(patterns []ttlPattern)
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
	ttlPatterns func() []ttlPattern
	run         func(ctx context.Context, fetch boundFetch, sink liveSink) error
}

// boundFetch is the fetch a liveSpec's run closure calls. It is liveSource.fetch
// pre-bound to one spec: on a 304 Not-Modified it refreshes that spec's
// ttlPatterns before returning, generalizing the bus-only 304→TTL rule to every
// live job (mrt/tra/bike previously just skipped and let their snapshots
// expire). run still checks modified and returns on false; the TTL refresh has
// already happened by then.
type boundFetch func(ctx context.Context, url, name string) (dec *json.Decoder, modified bool, close func(), err error)

// bindFetch wraps src.fetch so a 304 for this spec re-arms its Redis TTLs
// through sink before the result is returned.
func bindFetch(src liveSource, sink liveSink, spec liveSpec) boundFetch {
	return func(ctx context.Context, url, name string) (*json.Decoder, bool, func(), error) {
		dec, modified, close, err := src.fetch(ctx, url, name)
		if err == nil && !modified && spec.ttlPatterns != nil {
			// 304 Not-Modified: the cached live data is still valid, so re-arm its
			// TTL instead of letting it expire mid-validity (CONTEXT.md).
			sink.refreshTTL(spec.ttlPatterns())
		}
		return dec, modified, close, err
	}
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

// restLiveSource is the production liveSource: it wraps callApi, which fetches a
// TDX endpoint under an If-Modified-Since guard and streams the body.
type restLiveSource struct {
	client *resty.Client
	rc     *redis.Client
}

// fetch adapts callApi's (dec, comp, err, flipopen) return to the liveSource
// contract (dec, modified, close, err). ctx is accepted for interface symmetry;
// callApi's resty client carries its own timeout and the cron wrapper bounds the
// job, matching the pre-refactor behavior where callApi took no context.
func (s restLiveSource) fetch(_ context.Context, url, name string) (*json.Decoder, bool, func(), error) {
	dec, comp, err, flipopen := callApi(s.client, s.rc, url, name)
	return dec, comp, flipopen, err
}

// redisLiveSink is the production liveSink backed by *redis.Client. refreshTTL
// re-arms matching keys via SCAN + pipelined EXPIRE, the logic previously inline
// in refreshBusEtaTTLs, now shared by every live job's 304 path.
type redisLiveSink struct {
	rc *redis.Client
}

func (s redisLiveSink) pipeline() livePipe {
	return &redisLivePipe{pipe: s.rc.Pipeline()}
}

// refreshTTL re-arms the TTL on every key matching each pattern via SCAN +
// pipelined EXPIRE. Errors are logged and the scan for that pattern stops;
// a refresh failure never aborts the caller (this runs on a 304, off the write
// path).
func (s redisLiveSink) refreshTTL(patterns []ttlPattern) {
	total := 0
	for _, p := range patterns {
		var cursor uint64
		for {
			keys, next, err := s.rc.Scan(cursor, p.pattern, 500).Result()
			if err != nil {
				log.Infof("[LIVE] action=ttl_refresh event=scan_error pattern=%s error=%v", p.pattern, err)
				break
			}
			if len(keys) > 0 {
				pipe := s.rc.Pipeline()
				for _, k := range keys {
					pipe.Expire(k, p.ttl)
				}
				if _, err := pipe.Exec(); err != nil {
					log.Infof("[LIVE] action=ttl_refresh event=expire_error pattern=%s error=%v", p.pattern, err)
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
	log.Infof("[LIVE] action=ttl_refresh event=success keys=%d", total)
}

// redisLivePipe adapts a go-redis Pipeliner to the livePipe interface, dropping
// the per-command result handles the live jobs never inspect (they only Exec).
type redisLivePipe struct {
	pipe redis.Pipeliner
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

func (p *redisLivePipe) Exec() error {
	_, err := p.pipe.Exec()
	return err
}

// TTL windows re-armed on a 304, per the CONTEXT.md operating rule. They match
// the SET TTLs each job writes on the success path so a 304 extends a snapshot
// by exactly one more validity window: bus 180s, mrt/bike 2min, tra 3min.
const (
	busLiveTTL  = 180 * time.Second
	mrtLiveTTL  = 2 * time.Minute
	bikeLiveTTL = 2 * time.Minute
	traLiveTTL  = 3 * time.Minute
)

// liveRegistry lists every realtime dataset the runner knows how to refresh, in
// the order runLegacyProd previously invoked them within a shared cron tick
// (bike before bus on the 30s tick). db and dispatcher are captured by the specs
// that need them (bus needs both for the static-map join, prediction, history,
// and notifications; bike needs db for history sampling), mirroring how
// loaderRegistry captures src for the bus spec. rc is captured only where a job
// reads Redis outside the sink (bus reads cached weather; tra reads the delay
// hash back for the liveboard merge).
func liveRegistry(rc *redis.Client, db *pgxpool.Pool, dispatcher *notificationDispatcher) []liveSpec {
	bikeCityPatterns := func() []ttlPattern {
		// Bike availability keys are per-station-UID with no city prefix, so a
		// single-city 304 cannot target its own keys precisely. Re-arm the whole
		// bike keyspace: over-refreshing a still-valid snapshot is harmless, and a
		// missing refresh would let live data expire.
		return []ttlPattern{{pattern: shared.BikeAvailabilityKey("*"), ttl: bikeLiveTTL}}
	}
	mrtPatterns := func() []ttlPattern {
		return []ttlPattern{{pattern: shared.MrtLivePattern(), ttl: mrtLiveTTL}}
	}
	traPatterns := func() []ttlPattern {
		return []ttlPattern{
			{pattern: shared.TraLiveboardKey("*"), ttl: traLiveTTL},
			{pattern: shared.TraDelayAllKey, ttl: traLiveTTL},
			{pattern: shared.TraDelayHashKey, ttl: traLiveTTL},
		}
	}
	return []liveSpec{
		{key: "bike", cadence: "@every 30s", ttlPatterns: bikeCityPatterns,
			run: func(ctx context.Context, fetch boundFetch, sink liveSink) error {
				bikeEta(ctx, fetch, sink, db)
				return nil
			}},
		// bus keeps ttlPatterns nil: it fetches per city and re-arms exactly that
		// city's keys inline (processBusEtaCity → sink.refreshTTL(busEtaTTLPatterns))
		// on a 304, which is more precise than a whole-keyspace scan and avoids
		// re-scanning every city's keys on each city's 304. boundFetch's generic
		// refresh is for the jobs that previously skipped (bike/mrt/tra).
		{key: "bus", cadence: "@every 30s", ttlPatterns: nil,
			run: func(ctx context.Context, fetch boundFetch, sink liveSink) error {
				busEta(ctx, fetch, sink, rc, db, dispatcher)
				return nil
			}},
		{key: "mrt", cadence: "@every 10s", ttlPatterns: mrtPatterns,
			run: func(ctx context.Context, fetch boundFetch, sink liveSink) error {
				mrtEta(ctx, fetch, sink)
				return nil
			}},
		{key: "tra", cadence: "@every 2m", ttlPatterns: traPatterns,
			run: func(ctx context.Context, fetch boundFetch, sink liveSink) error {
				traEta(ctx, fetch, sink, rc)
				return nil
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
func registerLiveCrons(r *cron.Cron, client *resty.Client, rc *redis.Client, db *pgxpool.Pool, dispatcher *notificationDispatcher) {
	src := restLiveSource{client: client, rc: rc}
	sink := redisLiveSink{rc: rc}
	specs := liveRegistry(rc, db, dispatcher)

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
			dispatcher.fireScheduled(ctx)
		})
	})
}
