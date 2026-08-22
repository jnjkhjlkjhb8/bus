// Package rail serves TRA and THSR fares, timetables, and per-train stop
// times. Every path is a pure read against the loaded env schema with a Redis
// cache in front; a miss returns NotFound rather than reaching for TDX
// (ADR-0005).
package rail

import (
	"github.com/jackc/pgx/v5/pgxpool"
	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/api/internal/livestream"
	"github.com/redis/go-redis/v9"
)

// ThsrServer serves high-speed-rail fares, timetables, and available-seat
// streams. Every path is a pure read: fare/timetable results are cached in Redis
// and, on a miss, read from the loaded env schema, and AvailableSeats streams the
// seat snapshots the functions THSR-seats live job refreshes into Redis. No TDX
// fetch (ADR-0005), so the server holds no TDX client.
type ThsrServer struct {
	pb.UnimplementedThsrTimetableServiceServer

	db   *pgxpool.Pool
	rc   *redis.Client
	live livestream.LiveSource
}

// TraTimetableServer serves TRA fares and timetables and streams system-wide
// delays. Fare/timetable lookups are Redis-cached and, on a miss, read from the
// loaded env schema; empty results return NotFound (no TDX fetch, ADR-0005).
type TraTimetableServer struct {
	pb.UnimplementedTRATimetableServiceServer

	db   *pgxpool.Pool
	rc   *redis.Client
	live livestream.LiveSource
}

// TraDetainServer serves per-train TRA stop times and streams per-train delay
// updates. Stop times are Redis-cached and, on a miss, read from the loaded env
// schema; empty results return NotFound (no TDX fetch, ADR-0005).
type TraDetainServer struct {
	pb.UnimplementedTRA_DetainServiceServer

	db   *pgxpool.Pool
	rc   *redis.Client
	live livestream.LiveSource
}

// ThsrDetainServer serves per-train THSR stop times. Stop times are Redis-cached
// and, on a miss, read from the loaded env schema; empty results return NotFound
// (no TDX fetch, ADR-0005).
type ThsrDetainServer struct {
	pb.UnimplementedThsr_DetainServiceServer

	db   *pgxpool.Pool
	rc   *redis.Client
	live livestream.LiveSource
}

// NewThsrServer wires the read-only dependencies the server needs.
func NewThsrServer(db *pgxpool.Pool, rc *redis.Client, live livestream.LiveSource) *ThsrServer {
	return &ThsrServer{db: db, rc: rc, live: live}
}

// NewTraTimetableServer wires the read-only dependencies the server needs.
func NewTraTimetableServer(db *pgxpool.Pool, rc *redis.Client, live livestream.LiveSource) *TraTimetableServer {
	return &TraTimetableServer{db: db, rc: rc, live: live}
}

// NewTraDetainServer wires the read-only dependencies the server needs.
func NewTraDetainServer(db *pgxpool.Pool, rc *redis.Client, live livestream.LiveSource) *TraDetainServer {
	return &TraDetainServer{db: db, rc: rc, live: live}
}

// NewThsrDetainServer wires the read-only dependencies the server needs.
func NewThsrDetainServer(db *pgxpool.Pool, rc *redis.Client, live livestream.LiveSource) *ThsrDetainServer {
	return &ThsrDetainServer{db: db, rc: rc, live: live}
}
