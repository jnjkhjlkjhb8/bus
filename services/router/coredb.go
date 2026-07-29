package main

import (
	"context"

	"github.com/jackc/pgx/v5"
	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
)

// coreDB is the read surface the bus, bike, and station-group handlers need.
// Both *pgxpool.Pool and the pgxmock pool satisfy it, so the read-path helpers
// can be unit-tested with a mock.
type coreDB interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
	QueryRow(context.Context, string, ...any) pgx.Row
}

// busStaticPayload reads the pre-serialized static payload for a bus sub-route
// from the loaded env schema. The sub-route UID is used as-is: canonical
// subroute identity is produced at the 03:30 load (ADR-0006). A missing row
// surfaces as pgx.ErrNoRows for the caller to map to NotFound.
func busStaticPayload(ctx context.Context, db coreDB, subRouteUID string) ([]byte, error) {
	var data []byte
	if err := db.QueryRow(ctx, `SELECT pb FROM bus_static WHERE sub_route_uid = $1;`, subRouteUID).Scan(&data); err != nil {
		return nil, err
	}
	return data, nil
}

// busStationGroupCity resolves a station group's city from the loaded env
// schema, used to key the live-ETA stream when the request omits the city.
func busStationGroupCity(ctx context.Context, db coreDB, groupUID string) (string, error) {
	var city string
	if err := db.QueryRow(ctx, `SELECT city FROM bus_station_groups WHERE group_uid = $1`, groupUID).Scan(&city); err != nil {
		return "", err
	}
	return city, nil
}

type busStationGroupHeaderRow struct {
	GroupName string
	City      string
	Lon       float64
	Lat       float64
}

// busStationGroupHeader reads a station group's name, city, and position. A
// missing group surfaces as pgx.ErrNoRows for the caller to map to NotFound.
func busStationGroupHeader(ctx context.Context, db coreDB, groupUID string) (busStationGroupHeaderRow, error) {
	var r busStationGroupHeaderRow
	err := db.QueryRow(ctx, `
		SELECT group_name, city, ST_X(position), ST_Y(position)
		FROM bus_station_groups
		WHERE group_uid = $1`, groupUID).Scan(&r.GroupName, &r.City, &r.Lon, &r.Lat)
	return r, err
}

// busStationGroupMembers reads the member stops of a station group, ordered for
// stable presentation.
func busStationGroupMembers(ctx context.Context, db coreDB, groupUID string) ([]*pb.Bus_StationGroupMember, error) {
	rows, err := db.Query(ctx, `
		SELECT station_uid, station_id, station_name, ST_X(position), ST_Y(position)
		FROM bus_station_group_members
		WHERE group_uid = $1
		ORDER BY station_id, station_uid`, groupUID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var members []*pb.Bus_StationGroupMember
	for rows.Next() {
		m := &pb.Bus_StationGroupMember{}
		if err := rows.Scan(&m.StationUid, &m.StationId, &m.StationName, &m.PositionLon, &m.PositionLat); err != nil {
			return nil, err
		}
		members = append(members, m)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return members, nil
}

type bikeStaticRow struct {
	Name        string
	Capacity    int32
	ServiceType int32
	Address     string
	// Nullable: geom is not NOT NULL, and a station landed without a point
	// leaves both nil rather than reporting (0, 0) off West Africa.
	Lat *float64
	Lon *float64
}

// bikeStaticData reads a bike station's static fields from the loaded env
// schema. A missing station surfaces as pgx.ErrNoRows for the caller to map to
// NotFound.
func bikeStaticData(ctx context.Context, db coreDB, stationUID string) (bikeStaticRow, error) {
	var r bikeStaticRow
	err := db.QueryRow(ctx, `SELECT name,capacity,service_type,address,ST_Y(geom),ST_X(geom) FROM bike_stations WHERE station_uid = $1;`, stationUID).
		Scan(&r.Name, &r.Capacity, &r.ServiceType, &r.Address, &r.Lat, &r.Lon)
	return r, err
}
