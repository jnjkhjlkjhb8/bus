package main

import (
	"context"

	"github.com/jackc/pgx/v5"
	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
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
	return members, nil
}

type bikeStaticRow struct {
	Name        string
	Capacity    int32
	ServiceType int32
	Address     string
}

// bikeStaticData reads a bike station's static fields from the loaded env
// schema. A missing station surfaces as pgx.ErrNoRows for the caller to map to
// NotFound.
func bikeStaticData(ctx context.Context, db coreDB, stationUID string) (bikeStaticRow, error) {
	var r bikeStaticRow
	err := db.QueryRow(ctx, `SELECT name,capacity,service_type,address FROM bike_stations WHERE station_uid = $1;`, stationUID).
		Scan(&r.Name, &r.Capacity, &r.ServiceType, &r.Address)
	return r, err
}

// nearBusGroups reads bus station groups within radius of (lon,lat), nearest
// first, keeping only groups that have at least one member stop.
func nearBusGroups(ctx context.Context, db coreDB, lon, lat float64, size, limit int) ([]*busStations, error) {
	rows, err := db.Query(ctx, `SELECT group_uid AS station_uid, group_name AS station_name, city, ST_Distance(position::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography) AS distance, ST_X(position) AS lon, ST_Y(position) AS lat FROM bus_station_groups g WHERE ST_DWithin(position::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography, $3) AND EXISTS (SELECT 1 FROM bus_station_group_members m WHERE m.group_uid = g.group_uid) ORDER BY distance LIMIT $4;`, lon, lat, size, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[busStations])
}

// nearBikeStations reads bike stations within radius of (lon,lat), nearest first.
func nearBikeStations(ctx context.Context, db coreDB, lon, lat float64, size, limit int) ([]*bikeSations, error) {
	rows, err := db.Query(ctx, `SELECT station_uid, name, city, ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography) AS distance,ST_X(geom) AS lon ,ST_Y(geom) AS lat FROM bike_stations WHERE ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography, $3) ORDER BY distance LIMIT $4;`, lon, lat, size, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[bikeSations])
}

// nearMrtStations reads metro stations within radius of (lon,lat), nearest first.
func nearMrtStations(ctx context.Context, db coreDB, lon, lat float64, size, limit int) ([]*mrtSations, error) {
	rows, err := db.Query(ctx, `SELECT station_id, name, city, ST_Distance(stationposition::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography) AS distance,ST_X(stationposition) AS lon ,ST_Y(stationposition) AS lat FROM mrt_station WHERE ST_DWithin(stationposition::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography, $3) ORDER BY distance LIMIT $4;`, lon, lat, size, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[mrtSations])
}

// nearTraStations reads TRA stations within radius of (lon,lat), nearest first.
func nearTraStations(ctx context.Context, db coreDB, lon, lat float64, size, limit int) ([]*traStations, error) {
	rows, err := db.Query(ctx, `SELECT station_id, name, city, ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography) AS distance,ST_X(geom) AS lon ,ST_Y(geom) AS lat FROM tra_stations WHERE ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography, $3) ORDER BY distance LIMIT $4;`, lon, lat, size, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[traStations])
}

// nearThsrStations reads THSR stations within radius of (lon,lat), nearest first.
func nearThsrStations(ctx context.Context, db coreDB, lon, lat float64, size, limit int) ([]*thsrStations, error) {
	rows, err := db.Query(ctx, `SELECT station_id, name, city, ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography) AS distance,ST_X(geom) AS lon ,ST_Y(geom) AS lat FROM thsr_stations WHERE ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography, $3) ORDER BY distance LIMIT $4;`, lon, lat, size, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[thsrStations])
}
