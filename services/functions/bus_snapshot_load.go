package main

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// loadBus replaces one city only after all eight correlated landing partitions
// have been read, validated, reconciled, and materialized. Source validation is
// outside the target transaction; every target write and stale prune is inside
// one transaction. Cache generation advances only after commit.
func loadBus(ctx context.Context, src loadSource, db *pgxpool.Pool, rc *redis.Client, city string) error {
	zap.S().Infow("city start", "component", "load", "action", "bus", "event", "city_start", "city", city)
	snapshot, err := readBusCitySnapshot(ctx, src, city)
	if err != nil {
		return fmt.Errorf("load bus city %s: snapshot: %w", city, err)
	}
	if err := persistBusCitySnapshot(ctx, pgBusTxBeginner{db: db}, snapshot, func() error {
		return invalidateBusStaticAfterCommit(ctx, rc, city)
	}); err != nil {
		if !errors.Is(err, errBusPostCommitCache) {
			return fmt.Errorf("load bus city %s: target: %w", city, err)
		}
		// PostgreSQL is already committed. Return the post-commit failure so the
		// daily retry repeats the idempotent write and repairs the generation.
		return fmt.Errorf("load bus city %s: committed; invalidate cache: %w", city, err)
	}
	zap.S().Infow("city complete",
		"component", "load",
		"action", "bus",
		"event", "city_complete",
		"city", city,
		"subroute_count", len(snapshot.subroutes),
	)
	return nil
}

var errBusPostCommitCache = errors.New("bus snapshot post-commit cache invalidation failed")

func persistBusCitySnapshot(
	ctx context.Context,
	db busTxBeginner,
	snapshot *busCitySnapshot,
	invalidate func() error,
) error {
	if err := writeBusCitySnapshot(ctx, db, snapshot); err != nil {
		return err
	}
	if invalidate == nil {
		return fmt.Errorf("%w: nil invalidator", errBusPostCommitCache)
	}
	if err := invalidate(); err != nil {
		return errors.Join(errBusPostCommitCache, err)
	}
	return nil
}

func invalidateBusStaticAfterCommit(ctx context.Context, rc *redis.Client, city string) error {
	prefix := citymap[city]
	invalidateBusStaticMapCity(prefix)
	if rc == nil {
		return errors.New("redis client is nil")
	}
	generation, incrementErr := rc.Incr(ctx, shared.BusStaticGenerationKey(city)).Result()
	publishErr := rc.Publish(ctx, shared.BusStaticGenerationChannel(city), generation).Err()
	return errors.Join(incrementErr, publishErr)
}
