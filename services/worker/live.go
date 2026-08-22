package main

import (
	"context"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/bike"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/bus"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/mrt"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/pipeline"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/internal/rail"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/worker/notify"
	"github.com/redis/go-redis/v9"
	"github.com/robfig/cron/v3"
	"go.uber.org/zap"
)

// This file is the live counterpart of loader.go : the realtime ETA
// fan-out as one runner module with two seams. Each live job is a pipeline.LiveSpec whose
// TDX source and Redis sink are adapters, so tests replay recorded fixtures
// instead of calling TDX (CONTEXT.md "live job"). The runner owns per-job
// isolation, start/complete logging, and the CONTEXT.md 304→TTL-refresh rule for
// every job — not just bus.

// liveRegistry lists every realtime dataset the runner knows how to refresh, in
// the order runLegacyProd invokes them within a shared cron tick
// (bike before bus on the 30s tick). db and dispatcher are captured by the specs
// that need them (bus needs both for the static-map join, prediction, history,
// and notifications; bike needs db for history sampling), mirroring how
// loaderRegistry captures src for the bus spec. No spec captures a raw
// *redis.Client: the two jobs that read Redis mid-tick (bus weather, tra delay
// hash) now go through the pipeline.LiveSink read seam.
func liveRegistry(db *pgxpool.Pool, dispatcher *notify.Dispatcher) []pipeline.LiveSpec {
	bikeOwnedKey := func(fetchName string) string {
		return shared.LiveOwnedKeysKey("bike", strings.TrimPrefix(fetchName, "bike_availability"))
	}
	traPatterns := func(string) []pipeline.TTLPattern {
		return []pipeline.TTLPattern{
			{Pattern: shared.TraDelayAllKey, TTL: pipeline.TraLiveTTL},
			{Pattern: shared.TraDelayHashKey, TTL: pipeline.TraLiveTTL},
			{Pattern: shared.TraDelayStationKey, TTL: pipeline.TraLiveTTL},
			{Pattern: shared.TraDelayTrainChannel("*"), TTL: pipeline.TraLiveTTL},
		}
	}
	thsrSeatsPatterns := func(string) []pipeline.TTLPattern {
		// Re-arm today's per-train seat keys on a 304; the date is resolved when the
		// 304 fires so the pattern always targets the current service day.
		return []pipeline.TTLPattern{{Pattern: shared.ThsrSeatsPattern(time.Now().In(pipeline.Taipei).Format(time.DateOnly)), TTL: pipeline.ThsrSeatsLiveTTL}}
	}
	return []pipeline.LiveSpec{
		{Key: "bike", Cadence: "@every 30s", OwnedKey: bikeOwnedKey, OwnedTTL: pipeline.BikeLiveTTL,
			Run: func(ctx context.Context, fetch pipeline.BoundFetch, sink pipeline.LiveSink) error {
				return bike.Eta(ctx, fetch, sink, db)
			}},
		// bus keeps ttlPatterns nil, so pipeline.BoundFetch does not re-arm on its 304.
		// It does not need to: a 304 city still republishes from the cached raw
		// feed, and that write sets a fresh TTL. What does need re-arming is a
		// city run that aborts before publishing, which runCity owns in one
		// deferred guard covering all of its error returns. Wiring ttlPatterns
		// here instead would SCAN and EXPIRE the city's keys on every 304 only
		// for the republish to overwrite them moments later.
		{Key: "bus", Cadence: "@every 30s", TTLPatterns: nil,
			Run: func(ctx context.Context, fetch pipeline.BoundFetch, sink pipeline.LiveSink) error {
				return bus.Eta(ctx, fetch, sink, db, dispatcher)
			}},
		// Taipei and New Taipei get their ETA from Data.taipei, not TDX
		// (FDPL-66 Phase 4), so they are not bound to the shared TDX cadence
		// above and run on their own faster tick instead — 20s, matching
		// Data.taipei's own blob refresh rate rather than mrt's 15s (see
		// busEtaFastTickInterval), which also keeps this job out of mrt's
		// cadence group so it gets its own tick deadline. The TTLPatterns:nil
		// reasoning above applies here too.
		{Key: "bus_fast", Cadence: "@every 20s", TTLPatterns: nil,
			Run: func(ctx context.Context, fetch pipeline.BoundFetch, sink pipeline.LiveSink) error {
				return bus.EtaFast(ctx, fetch, sink, db, dispatcher)
			}},
		// TDX Metro LiveBoard is paused for all four systems (ADR-0014): TRTC
		// arrivals+congestion come from the Metro Taipei API on a 15s cadence;
		// KRTC/KLRT/TYMC live keys simply expire. To resume TDX, restore the
		// mrt.Eta spec ({Key: "mrt", Cadence: "@every 10s", OwnedKey: mrtOwnedKey,
		// OwnedTTL: mrtLiveTTL, Run: mrt.Eta}).
		{Key: "mrt", Cadence: "@every 15s",
			Run: func(ctx context.Context, fetch pipeline.BoundFetch, sink pipeline.LiveSink) error {
				return mrt.TrtcEta(ctx, sink, db)
			}},
		{Key: "tra", Cadence: "@every 2m", TTLPatterns: traPatterns, Run: rail.TraEta},
		// THSR available-seat status changes slowly, so it refreshes on a
		// conservative 10-minute cadence (its own cron entry, unbounded like
		// mrt/tra). This is the seat refresh moved off the router's read path
		// (ADR-0005 amendment).
		{Key: "thsr_seats", Cadence: "@every 10m", TTLPatterns: thsrSeatsPatterns, Run: rail.ThsrAvailableSeats},
	}
}

// liveJobTimeout is the whole-tick bound on the "@every 30s" bus/bike group
// (and the separate reminders tick sharing that cadence): 5s under the 30s
// period, matching liveTickDeadline's own margin for that cadence. Kept as a
// named constant because it is also used for the reminders tick, which has no
// liveRegistry cadence entry of its own.
const _liveJobTimeout = 25 * time.Second

// liveTickDeadline returns a deadline strictly under cadence's period, leaving
// a one-sixth margin so a full tick's jobs cannot bleed past the next tick and
// collide with SkipIfStillRunning's overlap guard under ordinary conditions.
// Every liveRegistry cadence is "@every <duration>"; an unparseable or
// non-positive cadence falls back to liveJobTimeout rather than leaving the
// tick unbounded.
func liveTickDeadline(cadence string) time.Duration {
	d, err := time.ParseDuration(strings.TrimPrefix(cadence, "@every "))
	if err != nil || d <= 0 {
		return _liveJobTimeout
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
	src := pipeline.NewRESTLiveSource(tdx)
	sink := pipeline.NewRedisLiveSink(rc)
	specs := liveRegistry(db, dispatcher)

	// Group specs by cadence, keeping registry order within each group so the
	// 30s tick still runs bike before bus.
	order := []string{}
	byCadence := map[string][]pipeline.LiveSpec{}
	for _, s := range specs {
		if _, seen := byCadence[s.Cadence]; !seen {
			order = append(order, s.Cadence)
		}
		byCadence[s.Cadence] = append(byCadence[s.Cadence], s)
	}

	for _, cadence := range order {
		group := byCadence[cadence]
		deadline := liveTickDeadline(cadence)
		_, _ = addStaticCron(r, cadence, func() {
			zap.S().Infow("start",
				"component", "live",
				"action", "tick",
				"event", "start",
				"cadence", cadence,
				"jobs", len(group),
				"deadline", deadline,
			)
			pipeline.WithTimeout(deadline, func(ctx context.Context) {
				for _, spec := range group {
					if ctx.Err() != nil {
						zap.S().Warnw("overrun",
							"component", "live",
							"action", "tick",
							"event", "overrun",
							"cadence", cadence,
							"deadline", deadline,
							"job", spec.Key,
						)
						break
					}
					pipeline.RunLiveSpec(ctx, src, sink, spec)
				}
			})
			zap.S().Infow("end", "component", "live", "action", "tick", "event", "end", "cadence", cadence)
		})
	}

	// Rail arrival reminders fire on a schedule (fire_at = arrival − lead) rather
	// than off a live ETA, so they dispatch on their own tick. Nil-safe when push
	// is disabled.
	_, _ = addStaticCron(r, "@every 30s", func() {
		pipeline.WithTimeout(_liveJobTimeout, func(ctx context.Context) {
			if err := dispatcher.FireScheduled(ctx); err != nil {
				zap.S().Errorw("error",
					"component", "live",
					"action", "run",
					"event", "error",
					"job", "scheduled_reminders",
					"err", err,
				)
			}
		})
	})
}

// _reminderDemandCitiesSQL lists the cities holding a pending bus arrival
// reminder. Rail reminders carry a fire_at and dispatch on a schedule, so only
// bus rows matter here.
// The latest expiry per city is what the demand key's TTL has to reach: a
// shorter one would reopen the same silent hole partway through the reminder
// it was written for.
const _reminderDemandCitiesSQL = `
	SELECT left(route_key, 3) AS city_prefix, max(expires_at)
	FROM firebase_arrival_reminder
	WHERE route_type = 'bus' AND status = 'pending' AND expires_at > NOW()
	GROUP BY city_prefix`

// restoreReminderDemand re-asserts the demand keys of every city holding a
// pending bus reminder, and returns how many it wrote.
//
// The router writes these when a reminder is created, which covers the normal
// case at zero runtime cost. This closes the two holes that leaves. The keys
// live in Redis, which is a cache here: a restart or an eviction drops them
// while the reminder itself sits in PostgreSQL, and the failure is silent —
// the city quietly drops to its reduced cadence and the reminder never fires,
// with no error anywhere to notice. Reminders that already existed when this
// gate was deployed have no key either. One query at boot answers both.
//
// Failures are logged and swallowed: a reminder that fires late is worse than
// a slow start, but neither is worth refusing to boot over.
func restoreReminderDemand(ctx context.Context, db *pgxpool.Pool, sink pipeline.LiveSink) int {
	if db == nil || sink == nil {
		return 0
	}
	rows, err := db.Query(ctx, _reminderDemandCitiesSQL)
	if err != nil {
		zap.S().Errorw("query failed",
			"component", "live",
			"action", "restore_reminder_demand",
			"event", "failed",
			"err", err,
		)
		return 0
	}
	defer rows.Close()

	pipe := sink.Pipe()
	restored := 0
	now := time.Now()
	for rows.Next() {
		var (
			prefix    string
			expiresAt time.Time
		)
		if err := rows.Scan(&prefix, &expiresAt); err != nil {
			zap.S().Errorw("scan failed",
				"component", "live",
				"action", "restore_reminder_demand",
				"event", "failed",
				"err", err,
			)
			return 0
		}
		city := shared.CityFromUID(prefix)
		ttl := expiresAt.Sub(now)
		if city == "" || ttl <= 0 {
			continue
		}
		pipe.Set(shared.LiveDemandKey("bus_eta", city), "1", ttl)
		restored++
	}
	if err := rows.Err(); err != nil {
		zap.S().Errorw("rows failed",
			"component", "live",
			"action", "restore_reminder_demand",
			"event", "failed",
			"err", err,
		)
		return 0
	}
	if restored == 0 {
		return 0
	}
	if err := pipe.Exec(ctx); err != nil {
		zap.S().Errorw("write failed",
			"component", "live",
			"action", "restore_reminder_demand",
			"event", "failed",
			"err", err,
		)
		return 0
	}
	zap.S().Infow("success",
		"component", "live",
		"action", "restore_reminder_demand",
		"event", "success",
		"cities", restored,
	)
	return restored
}
