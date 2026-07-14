package main

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// busTx is the complete target-DB surface of the bus snapshot writer. It has no
// raw_tdx read method; correlated source data must already be in the snapshot.
type busTx interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	CopyFrom(context.Context, pgx.Identifier, []string, pgx.CopyFromSource) (int64, error)
	QueryRow(context.Context, string, ...any) pgx.Row
	Commit(context.Context) error
	Rollback(context.Context) error
}

type busTxBeginner interface {
	BeginBusTx(context.Context) (busTx, error)
}

type pgBusTxBeginner struct{ db *pgxpool.Pool }

func (b pgBusTxBeginner) BeginBusTx(ctx context.Context) (busTx, error) {
	return b.db.Begin(ctx)
}

type busTempSpec struct {
	name    string
	create  string
	columns []string
	rows    [][]any
}

func writeBusCitySnapshot(ctx context.Context, db busTxBeginner, snapshot *busCitySnapshot) error {
	if db == nil || snapshot == nil {
		return errors.New("write bus city snapshot: nil database or snapshot")
	}
	tx, err := db.BeginBusTx(ctx)
	if err != nil {
		return fmt.Errorf("write bus city snapshot %s: begin: %w", snapshot.city, err)
	}
	defer func() {
		rollbackCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = tx.Rollback(rollbackCtx)
	}()

	if _, err := tx.Exec(ctx, "SET LOCAL lock_timeout = '20s'"); err != nil {
		return fmt.Errorf("write bus city snapshot %s: set lock timeout: %w", snapshot.city, err)
	}

	temps := []busTempSpec{
		{
			name: "temp_bus", create: `CREATE TEMP TABLE temp_bus (
				uid text, rid text, d int, name1 text, name2 text, city text,
				depart text, destin text, geom text, rawstop jsonb, schedule jsonb,
				operators jsonb) ON COMMIT DROP`,
			columns: []string{"uid", "rid", "d", "name1", "name2", "city", "depart", "destin", "geom", "rawstop", "schedule", "operators"}, rows: snapshot.subrouteRows,
		},
		{
			name: "temp_bus_stations", create: `CREATE TEMP TABLE temp_bus_stations (
				station_uid text, station_id text, station_name text,
				position_lon double precision, position_lat double precision,
				group_id text) ON COMMIT DROP`,
			columns: []string{"station_uid", "station_id", "station_name", "position_lon", "position_lat", "group_id"}, rows: snapshot.stationRows,
		},
		{
			name: "temp_bus_groups", create: `CREATE TEMP TABLE temp_bus_groups (
				group_uid text, group_id text, group_name text,
				position_lon double precision, position_lat double precision,
				source text) ON COMMIT DROP`,
			columns: []string{"group_uid", "group_id", "group_name", "position_lon", "position_lat", "source"}, rows: snapshot.groupRows,
		},
		{
			name: "temp_bus_members", create: `CREATE TEMP TABLE temp_bus_members (
				station_uid text, group_uid text, station_id text, station_name text,
				position_lon double precision, position_lat double precision) ON COMMIT DROP`,
			columns: []string{"station_uid", "group_uid", "station_id", "station_name", "position_lon", "position_lat"}, rows: snapshot.memberRows,
		},
		{
			name: "temp_bus_schedule", create: `CREATE TEMP TABLE temp_bus_schedule (
				uid text, dir smallint, type bool, id text, floor bool, seq smallint,
				stopuid text, stopname text, arrival text, departure text,
				sdays smallint) ON COMMIT DROP`,
			columns: []string{"uid", "dir", "type", "id", "floor", "seq", "stopuid", "stopname", "arrival", "departure", "sdays"}, rows: snapshot.scheduleRows,
		},
		{
			name: "temp_bus_static", create: `CREATE TEMP TABLE temp_bus_static (
				sname text, rname text, uid text, rid text, city text,
				depart text, destin text, pb bytea) ON COMMIT DROP`,
			columns: []string{"sname", "rname", "uid", "rid", "city", "depart", "destin", "pb"}, rows: snapshot.staticRows,
		},
		{
			name: "temp_bus_stop_map", create: `CREATE TEMP TABLE temp_bus_stop_map (
				sid text, sname text, sruid text, rname text, dir int,
				suid text, seq int) ON COMMIT DROP`,
			columns: []string{"sid", "sname", "sruid", "rname", "dir", "suid", "seq"}, rows: snapshot.stopMapRows,
		},
	}
	for _, temp := range temps {
		if _, err := tx.Exec(ctx, temp.create); err != nil {
			return fmt.Errorf("write bus city snapshot %s: create %s: %w", snapshot.city, temp.name, err)
		}
		if _, err := tx.CopyFrom(ctx, pgx.Identifier{temp.name}, temp.columns, pgx.CopyFromRows(temp.rows)); err != nil {
			return fmt.Errorf("write bus city snapshot %s: copy %s: %w", snapshot.city, temp.name, err)
		}
	}

	// A changed group_uid under an existing (city, group_id) would hit the
	// secondary unique constraint. Member FKs make an implicit destructive rekey
	// unsafe, so diagnose it before the first target upsert.
	var unsafeGroupRekey bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (
		SELECT 1
		FROM temp_bus_groups incoming
		JOIN bus_station_groups current
		  ON current.city = $1 AND current.group_id = incoming.group_id
		WHERE current.group_uid <> incoming.group_uid
	)`, snapshot.city).Scan(&unsafeGroupRekey); err != nil {
		return fmt.Errorf("write bus city snapshot %s: inspect station-group rekey: %w", snapshot.city, err)
	}
	if unsafeGroupRekey {
		return fmt.Errorf("%w: city %s station group changed UID for an existing group_id", errBusSnapshotConflict, snapshot.city)
	}

	steps := []struct {
		name string
		sql  string
		args []any
	}{
		{name: "upsert subroutes", sql: busSubroutesUpsertSQL},
		{name: "upsert stations", sql: `INSERT INTO bus_stations (
			station_uid, station_name, city, position, updated_at)
		SELECT station_uid, station_name, $1,
			ST_SetSRID(ST_MakePoint(position_lon, position_lat), 4326), NOW()
		FROM temp_bus_stations
		ON CONFLICT (station_uid) DO UPDATE SET
			station_name = EXCLUDED.station_name,
			city = EXCLUDED.city,
			position = EXCLUDED.position,
			updated_at = NOW()`, args: []any{snapshot.city}},
		{name: "upsert station groups", sql: `INSERT INTO bus_station_groups (
			group_uid, group_id, group_name, city, position, source, updated_at)
		SELECT group_uid, group_id, group_name, $1,
			ST_SetSRID(ST_MakePoint(position_lon, position_lat), 4326), source, NOW()
		FROM temp_bus_groups
		ON CONFLICT (group_uid) DO UPDATE SET
			group_id = EXCLUDED.group_id,
			group_name = EXCLUDED.group_name,
			city = EXCLUDED.city,
			position = EXCLUDED.position,
			source = EXCLUDED.source,
			updated_at = NOW()`, args: []any{snapshot.city}},
		{name: "upsert station group members", sql: `INSERT INTO bus_station_group_members (
			station_uid, group_uid, station_id, station_name, city, position, updated_at)
		SELECT m.station_uid,
			CASE WHEN $1 = 'InterCity' THEN COALESCE(nearby.group_uid, m.group_uid) ELSE m.group_uid END,
			m.station_id, m.station_name, $1,
			ST_SetSRID(ST_MakePoint(m.position_lon, m.position_lat), 4326), NOW()
		FROM temp_bus_members m
		LEFT JOIN LATERAL (
			SELECT g.group_uid
			FROM bus_station_groups g
			WHERE $1 = 'InterCity'
			  AND g.city <> $1
			  AND g.group_name = m.station_name
			  AND ST_DWithin(
				g.position::geography,
				ST_SetSRID(ST_MakePoint(m.position_lon, m.position_lat), 4326)::geography,
				1000)
			ORDER BY g.position <-> ST_SetSRID(ST_MakePoint(m.position_lon, m.position_lat), 4326)
			LIMIT 1
		) nearby ON true
		ON CONFLICT (station_uid) DO UPDATE SET
			group_uid = EXCLUDED.group_uid,
			station_id = EXCLUDED.station_id,
			station_name = EXCLUDED.station_name,
			city = EXCLUDED.city,
			position = EXCLUDED.position,
			updated_at = NOW()`, args: []any{snapshot.city}},
		{name: "replace schedule partition", sql: `DELETE FROM bus_schedule WHERE sub_route_uid LIKE $1`, args: []any{snapshot.prefix + "%"}},
		{name: "insert schedule", sql: busScheduleInsertSQL},
		{name: "upsert static protobufs", sql: `INSERT INTO bus_static (
			sub_route_name, route_name, sub_route_uid, route_uid, city, depart, destin, pb)
		SELECT sname, rname, uid, rid, city, depart, destin, pb
		FROM temp_bus_static
		ON CONFLICT (sub_route_uid) DO UPDATE SET
			sub_route_name = EXCLUDED.sub_route_name,
			route_name = EXCLUDED.route_name,
			route_uid = EXCLUDED.route_uid,
			city = EXCLUDED.city,
			depart = EXCLUDED.depart,
			destin = EXCLUDED.destin,
			pb = EXCLUDED.pb,
			updated_at = NOW()`},
		{name: "delete old stop map partition", sql: `DELETE FROM bus_station_stop_map WHERE sub_route_uid LIKE $1`, args: []any{snapshot.prefix + "%"}},
		{name: "insert stop map", sql: `INSERT INTO bus_station_stop_map (
			station_id, station_name, sub_route_uid, route_name, direction,
			stop_uid, stop_sequence, updated_at)
		SELECT DISTINCT ON (sruid, suid, dir)
			sid, sname, sruid, rname, dir, suid, seq, NOW()
		FROM temp_bus_stop_map
		ORDER BY sruid, suid, dir, seq
		ON CONFLICT (sub_route_uid, stop_uid, direction) DO UPDATE SET
			station_id = EXCLUDED.station_id,
			station_name = EXCLUDED.station_name,
			route_name = EXCLUDED.route_name,
			stop_sequence = EXCLUDED.stop_sequence,
			updated_at = NOW()`},
		{name: "prune stale station-group members", sql: `DELETE FROM bus_station_group_members current
		WHERE current.city = $1
		  AND NOT EXISTS (SELECT 1 FROM temp_bus_members fresh WHERE fresh.station_uid = current.station_uid)`, args: []any{snapshot.city}},
		{name: "prune empty station groups", sql: `DELETE FROM bus_station_groups current
		WHERE current.city = $1
		  AND NOT EXISTS (SELECT 1 FROM bus_station_group_members member WHERE member.group_uid = current.group_uid)`, args: []any{snapshot.city}},
		{name: "prune stale station groups", sql: `DELETE FROM bus_station_groups current
		WHERE current.city = $1
		  AND NOT EXISTS (SELECT 1 FROM temp_bus_groups fresh WHERE fresh.group_uid = current.group_uid)
		  AND NOT EXISTS (SELECT 1 FROM bus_station_group_members member WHERE member.group_uid = current.group_uid)`, args: []any{snapshot.city}},
		{name: "prune stale stations", sql: `DELETE FROM bus_stations current
		WHERE current.city = $1
		  AND NOT EXISTS (SELECT 1 FROM temp_bus_stations fresh WHERE fresh.station_uid = current.station_uid)`, args: []any{snapshot.city}},
		{name: "prune stale subroutes", sql: `DELETE FROM bus_subroutes current
		WHERE current.city = $1
		  AND NOT EXISTS (SELECT 1 FROM temp_bus fresh WHERE fresh.uid = current.sub_route_uid AND fresh.d = current.direction)`, args: []any{snapshot.city}},
		{name: "prune stale static routes", sql: `DELETE FROM bus_static current
		WHERE current.city = $1
		  AND NOT EXISTS (SELECT 1 FROM temp_bus_static fresh WHERE fresh.uid = current.sub_route_uid)`, args: []any{snapshot.city}},
	}
	for _, step := range steps {
		if _, err := tx.Exec(ctx, step.sql, step.args...); err != nil {
			return fmt.Errorf("write bus city snapshot %s: %s: %w", snapshot.city, step.name, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("write bus city snapshot %s: commit: %w", snapshot.city, err)
	}
	return nil
}
