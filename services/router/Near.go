package main

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"sync"

	"github.com/go-resty/resty/v2"
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

// walkAndDist returns walking minutes, distance in meters, and whether the
// values came from an OSRM foot-routing response (routed=true) versus the
// geodesic straight-line fallback (routed=false).
func walkAndDist(o osrm, ready bool, idx int, hasIdx bool, geodesic float64) (walk, dist int32, routed bool) {
	if ready && hasIdx && len(o.Durations) > 0 && idx < len(o.Durations[0]) {
		dist = int32(geodesic)
		if len(o.Distances) > 0 && idx < len(o.Distances[0]) {
			dist = int32(o.Distances[0][idx])
		}
		return int32(o.Durations[0][idx] / 60), dist, true
	}
	return int32(geodesic / 80), int32(geodesic), false
}

func findnearstation(lat, lon float64, size int, ctx context.Context, db coreDB, osrmClient *resty.Client) (*models.RespNear, error) {
	res := models.RespNear{}
	if size <= 0 {
		size = 670
	}
	const limit = 80
	var wg sync.WaitGroup
	wg.Add(5)
	go func() {
		defer wg.Done()
		row, err := nearBusGroups(ctx, db, lon, lat, size, limit)
		if err != nil {
			log.Infof("[NEAR] action=near_bus_groups event=query_failed error=%v", err)
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
			walk, dist, routed := walkAndDist(osrmresp, yes, osrmIdx, hasIdx, temp.Distance)
			ns := &models.NearStation{
				Type:        1,
				StationID:   temp.StationUid,
				StationName: temp.Name,
				City:        temp.City,
				PositionLon: temp.Lon,
				PositionLat: temp.Lat,
				Walk:        walk,
				Distance:    dist,
				Routed:      routed,
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
		row, err := nearBikeStations(ctx, db, lon, lat, size, limit)
		if err != nil {
			log.Infof("[NEAR] action=near_bike_stations event=query_failed error=%v", err)
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
			walk, dist, routed := walkAndDist(osrmresp, yes, osrmIdx, hasIdx, temp.Distance)
			bikeres = append(bikeres, &models.NearStation{
				Type:        2,
				StationID:   temp.StationUid,
				StationName: temp.Name,
				City:        temp.City,
				PositionLon: temp.Lon,
				PositionLat: temp.Lat,
				Walk:        walk,
				Distance:    dist,
				Routed:      routed,
			})
		}
		res.NearBikeStations = bikeres
	}()
	go func() {
		defer wg.Done()
		row, err := nearMrtStations(ctx, db, lon, lat, size, limit)
		if err != nil {
			log.Infof("[NEAR] action=near_mrt_stations event=query_failed error=%v", err)
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
			walk, dist, routed := walkAndDist(osrmresp, yes, osrmIdx, hasIdx, temp.Distance)
			mrtres = append(mrtres, &models.NearStation{
				Type:        3,
				StationID:   temp.StationUid,
				StationName: temp.Name,
				City:        temp.City,
				PositionLon: temp.Lon,
				PositionLat: temp.Lat,
				Walk:        walk,
				Distance:    dist,
				Routed:      routed,
			})
		}
		res.NearMrtStations = mrtres
	}()
	go func() {
		defer wg.Done()
		row, err := nearTraStations(ctx, db, lon, lat, size, limit)
		if err != nil {
			log.Infof("[NEAR] action=near_tra_stations event=query_failed error=%v", err)
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
			walk, dist, routed := walkAndDist(osrmresp, yes, osrmIdx, hasIdx, temp.Distance)
			trares = append(trares, &models.NearStation{
				Type:        4,
				StationID:   temp.StationUid,
				StationName: temp.Name,
				City:        temp.City,
				PositionLon: temp.Lon,
				PositionLat: temp.Lat,
				Walk:        walk,
				Distance:    dist,
				Routed:      routed,
			})
		}
		res.NearTraStations = trares
	}()
	go func() {
		defer wg.Done()
		row, err := nearThsrStations(ctx, db, lon, lat, size, limit)
		if err != nil {
			log.Infof("[NEAR] action=near_thsr_stations event=query_failed error=%v", err)
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
			walk, dist, routed := walkAndDist(osrmresp, yes, osrmIdx, hasIdx, temp.Distance)
			thsrres = append(thsrres, &models.NearStation{
				Type:        5,
				StationID:   temp.StationUid,
				StationName: temp.Name,
				City:        temp.City,
				PositionLon: temp.Lon,
				PositionLat: temp.Lat,
				Walk:        walk,
				Distance:    dist,
				Routed:      routed,
			})
		}
		res.NearThsrStations = thsrres
	}()
	wg.Wait()
	return &res, nil
}
