package main

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"sync"

	"github.com/go-resty/resty/v2"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
)

type bikeSations struct {
	StationUid string  `db:"station_uid"`
	Name       string  `db:"name"`
	City       string  `db:"city"`
	Distance   float64 `db:"distance"`
	Lon        float64 `db:"lon"`
	Lat        float64 `db:"lat"`
}
type busStations struct {
	StationUid string  `db:"station_uid"`
	Name       string  `db:"station_name"`
	City       string  `db:"city"`
	Distance   float64 `db:"distance"`
	Lon        float64 `db:"lon"`
	Lat        float64 `db:"lat"`
}
type mrtSations struct {
	StationUid string  `db:"station_id"`
	Name       string  `db:"name"`
	City       string  `db:"city"`
	Distance   float64 `db:"distance"`
	Lon        float64 `db:"lon"`
	Lat        float64 `db:"lat"`
}
type traStations struct {
	StationUid string  `db:"station_id"`
	Name       string  `db:"name"`
	City       string  `db:"city"`
	Distance   float64 `db:"distance"`
	Lon        float64 `db:"lon"`
	Lat        float64 `db:"lat"`
}
type thsrStations struct {
	StationUid string  `db:"station_id"`
	Name       string  `db:"name"`
	City       string  `db:"city"`
	Distance   float64 `db:"distance"`
	Lon        float64 `db:"lon"`
	Lat        float64 `db:"lat"`
}
type osrm struct {
	Code      string      `json:"code"`
	Durations [][]float64 `json:"durations"`
	Distances [][]float64 `json:"distances"`
}

func walkAndDist(o osrm, ready bool, idx int, hasIdx bool, geodesic float64) (walk, dist int32) {
	if ready && hasIdx && len(o.Durations) > 0 && idx < len(o.Durations[0]) {
		dist = int32(geodesic)
		if len(o.Distances) > 0 && idx < len(o.Distances[0]) {
			dist = int32(o.Distances[0][idx])
		}
		return int32(o.Durations[0][idx] / 60), dist
	}
	return int32(geodesic / 80), int32(geodesic)
}

func findnearstation(lat, lon float64, size int, ctx context.Context, db *pgxpool.Pool, osrmClient *resty.Client) (*models.RespNear, error) {
	res := models.RespNear{}
	if size <= 0 {
		size = 670
	}
	const limit = 80
	var wg sync.WaitGroup
	wg.Add(5)
	go func() {
		defer wg.Done()
		rows, _ := db.Query(ctx, `SELECT group_uid AS station_uid, group_name AS station_name, city, ST_Distance(position::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography) AS distance, ST_X(position) AS lon, ST_Y(position) AS lat FROM bus_station_groups g WHERE ST_DWithin(position::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography, $3) AND EXISTS (SELECT 1 FROM bus_station_group_members m WHERE m.group_uid = g.group_uid) ORDER BY distance LIMIT $4;`, lon, lat, size, limit)
		defer rows.Close()
		row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[busStations])
		if err != nil {
			rows.Close()
			log.Infoln(err.Error())
		}
		cnt := 1
		arr := []string{fmt.Sprintf("%f,%f", lon, lat)}
		ids := make([]string, 0, len(row))
		mp := make(map[string]int)
		for _, r := range row {
			arr = append(arr, fmt.Sprintf("%f,%f", r.Lon, r.Lat))
			ids = append(ids, strconv.Itoa(cnt))
			mp[r.StationUid] = cnt - 1
			cnt++
		}
		var osrmresp osrm
		yes := false
		c1 := strings.Join(arr, ";")
		c2 := strings.Join(ids, ";")
		resp, err := osrmClient.R().
			SetQueryParam("sources", "0").
			SetQueryParam("destinations", c2).
			SetQueryParam("annotations", "duration,distance").
			SetResult(&osrmresp).
			Get(fmt.Sprintf("http://osrm:5000/table/v1/foot/%s", c1))
		osrmOK := err == nil && resp.IsSuccess() && osrmresp.Code == "Ok" && len(osrmresp.Durations) > 0
		if osrmOK {
			yes = true
		}
		busres := make(map[string]*models.ArrayNear)
		for _, temp := range row {
			osrmIdx, hasIdx := mp[temp.StationUid]
			walk, dist := walkAndDist(osrmresp, yes, osrmIdx, hasIdx, temp.Distance)
			ns := &models.NearStation{
				Type:        1,
				StationID:   temp.StationUid,
				StationName: temp.Name,
				City:        temp.City,
				PositionLon: temp.Lon,
				PositionLat: temp.Lat,
				Walk:        walk,
				Distance:    dist,
			}
			if _, ok := busres[temp.Name]; !ok {
				busres[temp.Name] = &models.ArrayNear{
					NearStations: []*models.NearStation{},
				}
			}
			busres[temp.Name].NearStations = append(busres[temp.Name].NearStations, ns)
		}
		res.NearBusStations = busres
	}()
	go func() {
		defer wg.Done()
		rows, _ := db.Query(ctx, `SELECT station_uid, name, city, ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography) AS distance,ST_X(geom) AS lon ,ST_Y(geom) AS lat FROM bike_stations WHERE ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography, $3) ORDER BY distance LIMIT $4;`, lon, lat, size, limit)
		defer rows.Close()
		row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[bikeSations])
		if err != nil {
			rows.Close()
			log.Infoln(err.Error())
		}
		cnt := 1
		arr := []string{fmt.Sprintf("%f,%f", lon, lat)}
		ids := make([]string, 0, len(row))
		mp := make(map[string]int)
		for _, r := range row {
			arr = append(arr, fmt.Sprintf("%f,%f", r.Lon, r.Lat))
			ids = append(ids, strconv.Itoa(cnt))
			mp[r.StationUid] = cnt - 1
			cnt++
		}
		var osrmresp osrm
		yes := false
		c1 := strings.Join(arr, ";")
		c2 := strings.Join(ids, ";")
		resp, err := osrmClient.R().
			SetQueryParam("sources", "0").
			SetQueryParam("destinations", c2).
			SetQueryParam("annotations", "duration,distance").
			SetResult(&osrmresp).
			Get(fmt.Sprintf("http://osrm:5000/table/v1/foot/%s", c1))
		osrmOK := err == nil && resp.IsSuccess() && osrmresp.Code == "Ok" && len(osrmresp.Durations) > 0
		if osrmOK {
			yes = true
		}
		bikeres := make([]*models.NearStation, 0, len(row))
		for _, temp := range row {
			osrmIdx, hasIdx := mp[temp.StationUid]
			walk, dist := walkAndDist(osrmresp, yes, osrmIdx, hasIdx, temp.Distance)
			bikeres = append(bikeres, &models.NearStation{
				Type:        2,
				StationID:   temp.StationUid,
				StationName: temp.Name,
				City:        temp.City,
				PositionLon: temp.Lon,
				PositionLat: temp.Lat,
				Walk:        walk,
				Distance:    dist,
			})
		}
		res.NearBikeStations = bikeres
	}()
	go func() {
		defer wg.Done()
		rows, _ := db.Query(ctx, `SELECT station_id, name, city, ST_Distance(stationposition::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography) AS distance,ST_X(stationposition) AS lon ,ST_Y(stationposition) AS lat FROM mrt_station WHERE ST_DWithin(stationposition::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography, $3) ORDER BY distance LIMIT $4;`, lon, lat, size, limit)
		defer rows.Close()
		row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[mrtSations])
		if err != nil {
			rows.Close()
			log.Infoln(err.Error())
		}
		cnt := 1
		arr := []string{fmt.Sprintf("%f,%f", lon, lat)}
		ids := make([]string, 0, len(row))
		mp := make(map[string]int)
		for _, r := range row {
			arr = append(arr, fmt.Sprintf("%f,%f", r.Lon, r.Lat))
			ids = append(ids, strconv.Itoa(cnt))
			mp[r.StationUid] = cnt - 1
			cnt++
		}
		var osrmresp osrm
		yes := false
		c1 := strings.Join(arr, ";")
		c2 := strings.Join(ids, ";")
		resp, err := osrmClient.R().
			SetQueryParam("sources", "0").
			SetQueryParam("destinations", c2).
			SetQueryParam("annotations", "duration,distance").
			SetResult(&osrmresp).
			Get(fmt.Sprintf("http://osrm:5000/table/v1/foot/%s", c1))
		osrmOK := err == nil && resp.IsSuccess() && osrmresp.Code == "Ok" && len(osrmresp.Durations) > 0
		if osrmOK {
			yes = true
		}
		mrtres := make([]*models.NearStation, 0, len(row))
		for _, temp := range row {
			osrmIdx, hasIdx := mp[temp.StationUid]
			walk, dist := walkAndDist(osrmresp, yes, osrmIdx, hasIdx, temp.Distance)
			mrtres = append(mrtres, &models.NearStation{
				Type:        3,
				StationID:   temp.StationUid,
				StationName: temp.Name,
				City:        temp.City,
				PositionLon: temp.Lon,
				PositionLat: temp.Lat,
				Walk:        walk,
				Distance:    dist,
			})
		}
		res.NearMrtStations = mrtres
	}()
	go func() {
		defer wg.Done()
		rows, _ := db.Query(ctx, `SELECT station_id, name, city, ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography) AS distance,ST_X(geom) AS lon ,ST_Y(geom) AS lat FROM tra_stations WHERE ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography, $3) ORDER BY distance LIMIT $4;`, lon, lat, size, limit)
		defer rows.Close()
		row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[traStations])
		if err != nil {
			rows.Close()
			log.Infoln(err.Error())
		}
		cnt := 1
		arr := []string{fmt.Sprintf("%f,%f", lon, lat)}
		ids := make([]string, 0, len(row))
		mp := make(map[string]int)
		for _, r := range row {
			arr = append(arr, fmt.Sprintf("%f,%f", r.Lon, r.Lat))
			ids = append(ids, strconv.Itoa(cnt))
			mp[r.StationUid] = cnt - 1
			cnt++
		}
		var osrmresp osrm
		yes := false
		c1 := strings.Join(arr, ";")
		c2 := strings.Join(ids, ";")
		resp, err := osrmClient.R().
			SetQueryParam("sources", "0").
			SetQueryParam("destinations", c2).
			SetQueryParam("annotations", "duration,distance").
			SetResult(&osrmresp).
			Get(fmt.Sprintf("http://osrm:5000/table/v1/foot/%s", c1))
		osrmOK := err == nil && resp.IsSuccess() && osrmresp.Code == "Ok" && len(osrmresp.Durations) > 0
		if osrmOK {
			yes = true
		}
		trares := make([]*models.NearStation, 0, len(row))
		for _, temp := range row {
			osrmIdx, hasIdx := mp[temp.StationUid]
			walk, dist := walkAndDist(osrmresp, yes, osrmIdx, hasIdx, temp.Distance)
			trares = append(trares, &models.NearStation{
				Type:        4,
				StationID:   temp.StationUid,
				StationName: temp.Name,
				City:        temp.City,
				PositionLon: temp.Lon,
				PositionLat: temp.Lat,
				Walk:        walk,
				Distance:    dist,
			})
		}
		res.NearTraStations = trares
	}()
	go func() {
		defer wg.Done()
		rows, _ := db.Query(ctx, `SELECT station_id, name, city, ST_Distance(geom::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography) AS distance,ST_X(geom) AS lon ,ST_Y(geom) AS lat FROM thsr_stations WHERE ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint($1,$2), 4326)::geography, $3) ORDER BY distance LIMIT $4;`, lon, lat, size, limit)
		defer rows.Close()
		row, err := pgx.CollectRows(rows, pgx.RowToAddrOfStructByName[thsrStations])
		if err != nil {
			rows.Close()
			log.Infoln(err.Error())
		}
		cnt := 1
		arr := []string{fmt.Sprintf("%f,%f", lon, lat)}
		ids := make([]string, 0, len(row))
		mp := make(map[string]int)
		for _, r := range row {
			arr = append(arr, fmt.Sprintf("%f,%f", r.Lon, r.Lat))
			ids = append(ids, strconv.Itoa(cnt))
			mp[r.StationUid] = cnt - 1
			cnt++
		}
		var osrmresp osrm
		yes := false
		c1 := strings.Join(arr, ";")
		c2 := strings.Join(ids, ";")
		resp, err := osrmClient.R().
			SetQueryParam("sources", "0").
			SetQueryParam("destinations", c2).
			SetQueryParam("annotations", "duration,distance").
			SetResult(&osrmresp).
			Get(fmt.Sprintf("http://osrm:5000/table/v1/foot/%s", c1))
		osrmOK := err == nil && resp.IsSuccess() && osrmresp.Code == "Ok" && len(osrmresp.Durations) > 0
		if osrmOK {
			yes = true
		}
		thsrres := make([]*models.NearStation, 0, len(row))
		for _, temp := range row {
			osrmIdx, hasIdx := mp[temp.StationUid]
			walk, dist := walkAndDist(osrmresp, yes, osrmIdx, hasIdx, temp.Distance)
			thsrres = append(thsrres, &models.NearStation{
				Type:        5,
				StationID:   temp.StationUid,
				StationName: temp.Name,
				City:        temp.City,
				PositionLon: temp.Lon,
				PositionLat: temp.Lat,
				Walk:        walk,
				Distance:    dist,
			})
		}
		res.NearThsrStations = thsrres
	}()
	wg.Wait()
	return &res, nil
}
