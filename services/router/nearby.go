package main

import (
	"context"
	"errors"
	"fmt"

	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
)

const (
	defaultNearbyRadius = 670
	defaultNearbyLimit  = 80
)

var ErrNearbyUnavailable = errors.New("nearby discovery unavailable")

type geoPoint struct {
	Lon float64
	Lat float64
}

type nearbyMode int32

const (
	nearbyBus nearbyMode = iota + 1
	nearbyBike
	nearbyMRT
	nearbyTRA
	nearbyTHSR
)

var allNearbyModes = [...]nearbyMode{nearbyBus, nearbyBike, nearbyMRT, nearbyTRA, nearbyTHSR}

type nearbyQuery struct {
	Origin       geoPoint
	RadiusMeters int
	Limit        int
}

type nearbyCandidate struct {
	Mode           nearbyMode
	ID             string
	Name           string
	City           string
	Point          geoPoint
	GeodesicMeters float64
}

type walkingMetric struct {
	DurationSeconds *float64
	DistanceMeters  *float64
}

type nearbyStore interface {
	Find(context.Context, nearbyMode, nearbyQuery) ([]nearbyCandidate, error)
}

type walkingRouter interface {
	RouteMany(context.Context, geoPoint, []geoPoint) ([]walkingMetric, error)
}

type nearbyDiscovery struct {
	store  nearbyStore
	router walkingRouter
}

func newNearbyDiscovery(store nearbyStore, router walkingRouter) *nearbyDiscovery {
	return &nearbyDiscovery{store: store, router: router}
}

type nearbyModeResult struct {
	mode       nearbyMode
	stations   []*pb.NearStation
	queryError error
	error      error
}

func (d *nearbyDiscovery) Discover(ctx context.Context, query nearbyQuery) (*pb.RespNear, error) {
	if query.RadiusMeters <= 0 {
		query.RadiusMeters = defaultNearbyRadius
	}
	if query.Limit <= 0 {
		query.Limit = defaultNearbyLimit
	}

	results := make(chan nearbyModeResult, len(allNearbyModes))
	for _, mode := range allNearbyModes {
		go func() {
			candidates, err := d.store.Find(ctx, mode, query)
			if err != nil {
				results <- nearbyModeResult{mode: mode, queryError: err}
				return
			}
			stations, err := d.enrich(ctx, query.Origin, candidates)
			results <- nearbyModeResult{mode: mode, stations: stations, error: err}
		}()
	}

	response := &pb.RespNear{NearBusStations: make(map[string]*pb.ArrayNear)}
	queryFailures := 0
	for range allNearbyModes {
		result := <-results
		if result.queryError != nil {
			if isContextError(result.queryError) {
				return nil, result.queryError
			}
			queryFailures++
			log.Infof("[NEAR] action=query mode=%d event=failed error=%v", result.mode, result.queryError)
			continue
		}
		if result.error != nil {
			return nil, result.error
		}
		appendNearbyResult(response, result.mode, result.stations)
	}
	if queryFailures == len(allNearbyModes) {
		return nil, ErrNearbyUnavailable
	}
	return response, nil
}

func (d *nearbyDiscovery) enrich(ctx context.Context, origin geoPoint, candidates []nearbyCandidate) ([]*pb.NearStation, error) {
	if len(candidates) == 0 {
		return nil, nil
	}

	points := make([]geoPoint, len(candidates))
	for i, item := range candidates {
		points[i] = item.Point
	}

	var metrics []walkingMetric
	var routeErr error
	if d.router != nil {
		metrics, routeErr = d.router.RouteMany(ctx, origin, points)
	}
	if isContextError(routeErr) {
		return nil, routeErr
	}

	stations := make([]*pb.NearStation, 0, len(candidates))
	for i, item := range candidates {
		walk := int32(item.GeodesicMeters / 80)
		distance := int32(item.GeodesicMeters)
		routed := false
		if routeErr == nil && i < len(metrics) && metrics[i].DurationSeconds != nil {
			walk = int32(*metrics[i].DurationSeconds / 60)
			routed = true
			if metrics[i].DistanceMeters != nil {
				distance = int32(*metrics[i].DistanceMeters)
			}
		}
		stations = append(stations, &pb.NearStation{
			Type: int32(item.Mode), StationID: item.ID, StationName: item.Name,
			City: item.City, PositionLon: item.Point.Lon, PositionLat: item.Point.Lat,
			Walk: walk, Distance: distance, Routed: routed,
		})
	}
	return stations, nil
}

func appendNearbyResult(response *pb.RespNear, mode nearbyMode, stations []*pb.NearStation) {
	switch mode {
	case nearbyBus:
		for _, station := range stations {
			response.NearBusStations[station.StationID] = &pb.ArrayNear{NearStations: []*pb.NearStation{station}}
		}
	case nearbyBike:
		response.NearBikeStations = stations
	case nearbyMRT:
		response.NearMrtStations = stations
	case nearbyTRA:
		response.NearTraStations = stations
	case nearbyTHSR:
		response.NearThsrStations = stations
	default:
		panic(fmt.Sprintf("unknown nearby mode %d", mode))
	}
}

func isContextError(err error) bool {
	return errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded)
}
