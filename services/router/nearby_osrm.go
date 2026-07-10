package main

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/go-resty/resty/v2"
)

type osrmWalkingRouter struct {
	client  *resty.Client
	baseURL string
}

func newOSRMWalkingRouter(client *resty.Client, baseURL string) *osrmWalkingRouter {
	return &osrmWalkingRouter{client: client, baseURL: strings.TrimRight(baseURL, "/")}
}

type osrmTableResponse struct {
	Code      string       `json:"code"`
	Durations [][]*float64 `json:"durations"`
	Distances [][]*float64 `json:"distances"`
}

func (r *osrmWalkingRouter) RouteMany(ctx context.Context, origin geoPoint, destinations []geoPoint) ([]walkingMetric, error) {
	if len(destinations) == 0 {
		return nil, nil
	}
	if r == nil || r.client == nil {
		return nil, fmt.Errorf("OSRM client unavailable")
	}

	coordinates := make([]string, 0, len(destinations)+1)
	coordinates = append(coordinates, formatCoordinate(origin))
	destinationIndexes := make([]string, 0, len(destinations))
	for i, point := range destinations {
		coordinates = append(coordinates, formatCoordinate(point))
		destinationIndexes = append(destinationIndexes, strconv.Itoa(i+1))
	}

	result := &osrmTableResponse{}
	response, err := r.client.R().
		SetContext(ctx).
		SetQueryParam("sources", "0").
		SetQueryParam("destinations", strings.Join(destinationIndexes, ";")).
		SetQueryParam("annotations", "duration,distance").
		SetResult(result).
		Get(r.baseURL + "/table/v1/foot/" + strings.Join(coordinates, ";"))
	if err != nil {
		return nil, err
	}
	if !response.IsSuccess() || result.Code != "Ok" || len(result.Durations) == 0 {
		return nil, fmt.Errorf("OSRM table response invalid: status=%d code=%q", response.StatusCode(), result.Code)
	}

	metrics := make([]walkingMetric, len(destinations))
	for i := range destinations {
		if i < len(result.Durations[0]) {
			metrics[i].DurationSeconds = result.Durations[0][i]
		}
		if len(result.Distances) > 0 && i < len(result.Distances[0]) {
			metrics[i].DistanceMeters = result.Distances[0][i]
		}
	}
	return metrics, nil
}

func formatCoordinate(point geoPoint) string {
	return fmt.Sprintf("%f,%f", point.Lon, point.Lat)
}
