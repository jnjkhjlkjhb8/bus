package store

import (
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
	"github.com/redis/go-redis/v9"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// GRPCStatusFor is the shared choke point for every bus/bike/rail read
// handler's DB (and cache) lookup failure (handlers_core.go, handlers_rail.go),
// so it doubles as the single place to tally router_db_errors_total: a
// not-found result is expected traffic and excluded, everything else here is
// a genuine backing-store failure.
func GRPCStatusFor(err error, notFoundMsg string) error {
	if errors.Is(err, pgx.ErrNoRows) || errors.Is(err, redis.Nil) || errors.Is(err, obs.ErrNotFound) {
		return status.Error(codes.NotFound, notFoundMsg)
	}
	obs.IncDBError()
	return status.Error(codes.Internal, "internal error")
}
