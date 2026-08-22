package nearby

// Nearby walking times from MOTIS (ADR-0022).
//
// This replaces the OSRM table service. The question is unchanged -- how long
// does it take to walk from the rider to each of these stops -- but the two
// APIs disagree about what a caller must state up front: OSRM's table took a
// matrix and answered for all of it, while MOTIS requires an explicit travel
// time ceiling and street-matching tolerance on every call.

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/go-resty/resty/v2"
)

const (
	_motisOneToManyPath = "/api/v1/one-to-many"
	// _motisWalkMaxSeconds is the travel-time ceiling one-to-many requires. 30
	// minutes on foot: past that a stop is not "nearby" in any sense a rider
	// means it, and the query radius (nearby.go, 5 km ceiling) already bounds
	// the candidate set geographically. A destination beyond this returns no
	// duration and is listed without a walking time, exactly as an unroutable
	// one was under OSRM.
	_motisWalkMaxSeconds = 1800
	// _motisWalkMatchingMeters is how far a coordinate may sit from the street
	// network before it fails to match. Tighter than MOTIS's own 250 m default:
	// a stop that is 250 m from any street is a data error, and snapping it
	// anyway would quote a walking time to somewhere the rider is not going.
	_motisWalkMatchingMeters = 100
)

// motisWalkingRouter answers the same question the OSRM table service did, so
// the compiler is told it still satisfies the interface nearby depends on.
var _ walkingRouter = (*motisWalkingRouter)(nil)

type motisWalkingRouter struct {
	client  *resty.Client
	baseURL string
}

func NewMotisWalkingRouter(client *resty.Client, baseURL string) *motisWalkingRouter {
	return &motisWalkingRouter{client: client, baseURL: strings.TrimRight(baseURL, "/")}
}

// motisOneToManyRequest is the POST body. The GET form takes the same
// parameters, but a nearby query carries up to ~400 destinations at roughly 22
// characters each, which is a URL long enough to be truncated or rejected by
// something in the path.
type motisOneToManyRequest struct {
	One                 string   `json:"one"`
	Many                []string `json:"many"`
	Mode                string   `json:"mode"`
	Max                 float64  `json:"max"`
	MaxMatchingDistance float64  `json:"maxMatchingDistance"`
	ArriveBy            bool     `json:"arriveBy"`
	WithDistance        bool     `json:"withDistance"`
}

// motisDuration is one entry of the response. Both fields are absent when no
// path was found, which is why they are pointers: a missing duration and a
// zero-second walk are different answers, and WalkingMetric already carries
// that distinction through to the app.
type motisDuration struct {
	Duration *float64 `json:"duration"`
	Distance *float64 `json:"distance"`
}

// RouteMany answers walking duration and distance for every destination, in the
// order they were given. Destinations MOTIS could not reach within the ceiling
// come back with nil metrics rather than an error: one unroutable stop must not
// cost the rider the whole nearby list.
func (r *motisWalkingRouter) RouteMany(
	ctx context.Context,
	origin GeoPoint,
	destinations []GeoPoint,
) ([]WalkingMetric, error) {
	if len(destinations) == 0 {
		return nil, nil
	}
	if r == nil || r.client == nil {
		return nil, errors.New("MOTIS client unavailable")
	}

	many := make([]string, 0, len(destinations))
	for _, point := range destinations {
		many = append(many, formatMotisCoordinate(point))
	}

	var result []motisDuration
	response, err := r.client.R().
		SetContext(ctx).
		SetHeader("Content-Type", "application/json").
		SetBody(motisOneToManyRequest{
			One:                 formatMotisCoordinate(origin),
			Many:                many,
			Mode:                "WALK",
			Max:                 _motisWalkMaxSeconds,
			MaxMatchingDistance: _motisWalkMatchingMeters,
			// One rider walking out to many stops, not many walking in.
			ArriveBy: false,
			// nearby.go surfaces the distance alongside the time. MOTIS has to
			// reconstruct the path to measure it, which is slower than a
			// duration-only query -- the alternative is dropping a field that
			// is already on screen.
			WithDistance: true,
		}).
		SetResult(&result).
		Post(r.baseURL + _motisOneToManyPath)
	if err != nil {
		return nil, _oops.Wrapf(err, "MOTIS one-to-many")
	}
	if !response.IsSuccess() {
		return nil, _oops.
			With("status_code", response.StatusCode()).
			With("destinations", len(destinations)).
			Errorf("MOTIS one-to-many HTTP")
	}
	// A short array would silently pair a stop with another stop's walking
	// time. Length is the only thing tying the two lists together, so it is
	// checked rather than assumed.
	if len(result) != len(destinations) {
		return nil, _oops.
			With("destinations", len(destinations)).
			With("durations", len(result)).
			Errorf("MOTIS one-to-many length mismatch")
	}

	metrics := make([]WalkingMetric, len(destinations))
	for i, entry := range result {
		metrics[i].DurationSeconds = entry.Duration
		metrics[i].DistanceMeters = entry.Distance
	}
	return metrics, nil
}

// formatMotisCoordinate renders a point the way one-to-many reads it:
// semicolon between latitude and longitude, because the comma separates one
// location from the next.
func formatMotisCoordinate(point GeoPoint) string {
	return fmt.Sprintf("%f;%f", point.Lat, point.Lon)
}
