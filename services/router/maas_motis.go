package main

// The MOTIS v2 planning backend (ADR-0022).
//
// MOTIS answers the same question TDX MaaS did, so this file's job is to speak
// its request shape and translate its itineraries back into the internal
// [tdxAPIResponse] every downstream stage already consumes. Keeping that
// intermediate shape means fares, bus notification identities and rail line
// geometry are computed by exactly one implementation regardless of which
// backend produced the plan -- only the upstream call and the walk geometry
// differ.
//
// Walk geometry is the one place the two backends genuinely diverge: TDX
// returns none, so [enrichWalkSections] pays an OSRM round trip per walk
// section, while MOTIS returns an encoded polyline and turn-by-turn steps
// inside the leg it already computed. The geometry therefore travels alongside
// the converted response rather than being fetched again.

import (
	"context"
	"errors"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/go-resty/resty/v2"

	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
)

const (
	// _maasBackendEnv selects the planner. Anything other than "tdx" means
	// MOTIS: the switch exists to fall back, so an unset or misspelled value
	// must not silently resurrect the backend being replaced.
	_maasBackendEnv = "MAAS_BACKEND"
	_maasBackendTDX = "tdx"
	// _motisBaseURLEnv is where MOTIS is reached. Prod's router shares a
	// network with it; staging's dials prod's published port over the host
	// gateway (ADR-0022).
	_motisBaseURLEnv     = "MOTIS_BASE_URL"
	_motisDefaultBaseURL = "http://motis:8080"
	_motisPlanPath       = "/api/v6/plan"
	// _motisTimeout bounds one plan call. The shared work timeout is 20s and
	// covers fares and geometry on top of this, so the upstream call cannot be
	// allowed to consume all of it.
	_motisTimeout = 12 * time.Second
	// _motisExtraItineraries is how many more itineraries than the rider asked
	// for are requested, so [rankMotisRoutes] has something to rank. MOTIS
	// optimises on time and transfers only -- it cannot search on price at all
	// -- so a cheaper-but-slower itinerary is only ever available if it happens
	// to be inside this window. Widening it costs the 6 GB host real work for
	// diminishing returns.
	_motisExtraItineraries = 5
	_motisMaxItineraries   = 10
)

// errMotisNoItinerary marks an empty MOTIS result. It is an empty answer rather
// than a router fault, so it joins errMaasNoRoute and reaches the rider as
// NotFound instead of Unavailable.
var errMotisNoItinerary = errors.New("MOTIS has no itinerary for this origin/destination")

// MaasBackendFromEnv reports whether the TDX planner is selected. Every other
// value, including unset, selects MOTIS.
func MaasBackendFromEnv() (useTDX bool) {
	return strings.EqualFold(strings.TrimSpace(os.Getenv(_maasBackendEnv)), _maasBackendTDX)
}

// MotisBaseURLFromEnv reads where MOTIS is reached, defaulting to the service
// name on the routing network.
func MotisBaseURLFromEnv() string {
	if raw := strings.TrimSpace(os.Getenv(_motisBaseURLEnv)); raw != "" {
		return strings.TrimRight(raw, "/")
	}
	return _motisDefaultBaseURL
}

// motisClient is the MOTIS half of the planner. It holds no state beyond its
// HTTP client: MOTIS is a pure reader and every query is self-contained.
type motisClient struct {
	http *resty.Client
}

// NewMotisClient builds the client. Unlike the TDX one there is no retry
// policy: MOTIS is a local service on the same host, so a failure is a real
// failure rather than a rate limit worth waiting out, and a retry would only
// spend the caller's remaining budget.
func NewMotisClient(baseURL string) *motisClient {
	return &motisClient{
		http: resty.New().
			SetBaseURL(baseURL).
			SetTimeout(_motisTimeout),
	}
}

// motisPlanResponse is the subset of MOTIS's plan result this router consumes.
type motisPlanResponse struct {
	Itineraries []motisItinerary `json:"itineraries"`
	// Opaque cursors for the 更早 / 更晚 departures action. Present only when
	// the query asked for a timetable view.
	PreviousPageCursor string `json:"previousPageCursor"`
	NextPageCursor     string `json:"nextPageCursor"`
}

type motisItinerary struct {
	Duration  int64      `json:"duration"`
	StartTime string     `json:"startTime"`
	EndTime   string     `json:"endTime"`
	Transfers int32      `json:"transfers"`
	Legs      []motisLeg `json:"legs"`
}

type motisLeg struct {
	Mode              string        `json:"mode"`
	From              motisPlace    `json:"from"`
	To                motisPlace    `json:"to"`
	Duration          int64         `json:"duration"`
	StartTime         string        `json:"startTime"`
	EndTime           string        `json:"endTime"`
	Distance          float64       `json:"distance"`
	Headsign          string        `json:"headsign"`
	RouteShortName    string        `json:"routeShortName"`
	RouteLongName     string        `json:"routeLongName"`
	RouteColor        string        `json:"routeColor"`
	DisplayName       string        `json:"displayName"`
	AgencyID          string        `json:"agencyId"`
	AgencyName        string        `json:"agencyName"`
	AgencyURL         string        `json:"agencyUrl"`
	IntermediateStops []motisPlace  `json:"intermediateStops"`
	LegGeometry       motisPolyline `json:"legGeometry"`
	Steps             []motisStep   `json:"steps"`
	// Services that could replace this leg, each framed by MOTIS as its own
	// little journey -- normally [ingress footpath, transit, egress footpath].
	// Only set when the request asked for alternatives, and only on the first
	// leg of an interlined chain.
	Alternatives [][]motisLeg `json:"alternatives"`
}

type motisPlace struct {
	Name      string  `json:"name"`
	StopID    string  `json:"stopId"`
	Lat       float64 `json:"lat"`
	Lon       float64 `json:"lon"`
	Arrival   string  `json:"arrival"`
	Departure string  `json:"departure"`
}

type motisPolyline struct {
	Points    string `json:"points"`
	Precision int    `json:"precision"`
}

type motisStep struct {
	RelativeDirection string        `json:"relativeDirection"`
	Distance          float64       `json:"distance"`
	StreetName        string        `json:"streetName"`
	Polyline          motisPolyline `json:"polyline"`
}

// motisWalkGeometry is one walk section's path and turn-by-turn steps, already
// known because MOTIS routed the street leg itself. Index i corresponds to the
// i-th section of the converted response, in the same flattened order
// [convertRoutes] assigns to its refs.
type motisWalkGeometry struct {
	path  []*pb.Location
	steps []*pb.WalkStep
}

// Plan runs one MOTIS query and returns it in the internal shape, alongside the
// per-section walk geometry MOTIS already computed. The geometry slice is
// parallel to the flattened section order, with a nil entry for any section
// that is not a walk.
// motisPlanResult is one MOTIS answer in the router's internal shape: the plan,
// the walk geometry MOTIS already computed for it, and the cursors that let the
// rider ask for earlier or later departures.
type motisPlanResult struct {
	api      *tdxAPIResponse
	geometry []*motisWalkGeometry
	previous string
	next     string
}

func (c *motisClient) Plan(
	ctx context.Context,
	req *pb.MaasPlanRequest,
) (*motisPlanResult, error) {
	var out motisPlanResponse
	resp, err := c.http.R().
		SetContext(ctx).
		SetQueryParamsFromValues(motisPlanQuery(req, time.Now())).
		SetResult(&out).
		Get(_motisPlanPath)
	if err != nil {
		return nil, _oops.Wrapf(err, "MOTIS plan")
	}
	if !resp.IsSuccess() {
		err := _oops.
			With("status_code", resp.StatusCode()).
			With("url", resp.Request.URL).
			With("string", strings.TrimSpace(resp.String())).
			Errorf("MOTIS plan HTTP")
		if resp.StatusCode() == http.StatusNotFound {
			return nil, _oops.Join(errMaasNoRoute, errMotisNoItinerary, err)
		}
		return nil, err
	}
	if len(out.Itineraries) == 0 {
		return nil, _oops.Join(errMaasNoRoute, errMotisNoItinerary)
	}
	api, geometry := convertMotisItineraries(out.Itineraries)
	return &motisPlanResult{
		api:      api,
		geometry: geometry,
		previous: out.PreviousPageCursor,
		next:     out.NextPageCursor,
	}, nil
}

// convertMotisItineraries maps MOTIS itineraries onto the internal shape. The
// geometry slice is built in the same nested order the caller will flatten its
// sections in, which is what lets [applyMotisWalkGeometry] pair them by index
// without threading a key through the conversion.
func convertMotisItineraries(itineraries []motisItinerary) (*tdxAPIResponse, []*motisWalkGeometry) {
	api := &tdxAPIResponse{}
	geometry := make([]*motisWalkGeometry, 0)
	for _, itinerary := range itineraries {
		route := tdxRoute{
			TravelTime: itinerary.Duration,
			StartTime:  itinerary.StartTime,
			EndTime:    itinerary.EndTime,
			Transfers:  itinerary.Transfers,
		}
		for _, leg := range itinerary.Legs {
			route.Sections = append(route.Sections, motisSection(leg))
			geometry = append(geometry, motisLegGeometry(leg))
		}
		api.Data.Routes = append(api.Data.Routes, route)
	}
	return api, geometry
}

// motisSection maps one leg. The mode strings are deliberately TDX's rather
// than MOTIS's, because the rail/bus/metro classifiers in maas_geometry.go and
// the fare lookup in maas.go both switch on them -- translating once here keeps
// a second vocabulary out of the rest of the router.
func motisSection(leg motisLeg) tdxSection {
	section := tdxSection{
		Type: motisSectionType(leg.Mode),
		TravelSummary: tdxSummary{
			Duration: leg.Duration,
			Length:   leg.Distance,
		},
		Departure: tdxPlaceInfo{
			Time: leg.StartTime,
			Place: tdxPlace{
				Name:     leg.From.Name,
				Type:     motisPlaceType(leg.From),
				Location: tdxLocation{Lat: leg.From.Lat, Lng: leg.From.Lon},
			},
		},
		Arrival: tdxPlaceInfo{
			Time: leg.EndTime,
			Place: tdxPlace{
				Name:     leg.To.Name,
				Type:     motisPlaceType(leg.To),
				Location: tdxLocation{Lat: leg.To.Lat, Lng: leg.To.Lon},
			},
		},
	}
	if mode := motisTransitMode(leg.Mode); mode != "" {
		section.Transport = tdxTransport{
			Mode:       mode,
			Name:       motisRouteName(leg),
			ShortName:  leg.RouteShortName,
			LongName:   leg.RouteLongName,
			Number:     leg.RouteShortName,
			Headsign:   leg.Headsign,
			RouteColor: leg.RouteColor,
		}
	}
	for _, stop := range leg.IntermediateStops {
		section.IntermediateStops = append(section.IntermediateStops, tdxStop{
			Departure: tdxPlaceInfo{
				Time: stop.Departure,
				Place: tdxPlace{
					Name:     stop.Name,
					Location: tdxLocation{Lat: stop.Lat, Lng: stop.Lon},
				},
			},
		})
	}
	if leg.AgencyName != "" {
		section.Agency = tdxAgency{
			AgencyID: leg.AgencyID,
			Name:     leg.AgencyName,
			Website:  leg.AgencyURL,
		}
	}
	for _, alternative := range leg.Alternatives {
		transit, ok := motisAlternativeLeg(alternative)
		if !ok {
			continue
		}
		section.Alternatives = append(section.Alternatives, motisSection(transit))
	}
	return section
}

// motisAlternativeLeg picks the one leg of an alternative the rider is actually
// being offered. MOTIS wraps each alternative in the footpaths that get the
// rider to and from it, and an interlined alternative carries several transit
// legs; in both cases the first transit leg is the service being named, so that
// is what the section reports. An alternative with no transit leg at all is
// walking the rider somewhere, which is not an answer to "what else runs this?".
func motisAlternativeLeg(legs []motisLeg) (motisLeg, bool) {
	for _, leg := range legs {
		if motisTransitMode(leg.Mode) != "" {
			return leg, true
		}
	}
	return motisLeg{}, false
}

// motisRouteName picks the label the bus notification lookup matches on.
// displayName is MOTIS's own already-composed label and is the closest thing to
// TDX's route name; the short name is the fallback because a bus leg always has
// one and matching on an empty string finds nothing.
func motisRouteName(leg motisLeg) string {
	if leg.DisplayName != "" {
		return leg.DisplayName
	}
	if leg.RouteShortName != "" {
		return leg.RouteShortName
	}
	return leg.RouteLongName
}

// motisSectionType maps a leg onto the section type the app branches on.
// Anything the rider travels on their own feet or a rented bike is a pedestrian
// section, which is also what [isWalkSection] tests.
func motisSectionType(mode string) string {
	if motisTransitMode(mode) == "" {
		return "pedestrian"
	}
	return "transit"
}

// motisPlaceType distinguishes a timetable stop from a street coordinate. TDX
// used the same two values, and the app renders a stop name differently from an
// address.
func motisPlaceType(place motisPlace) string {
	if place.StopID != "" {
		return "station"
	}
	return "place"
}

// motisTransitMode translates a MOTIS mode onto the TDX mode vocabulary the
// rest of the router classifies on. An empty result means the leg is not
// transit.
//
// The rail split is what the feed's route_type carries: THSR is emitted as the
// extended type 101 and TRA as the plain 2, which nigiri maps to HIGHSPEED_RAIL
// and REGIONAL_RAIL respectively. Without that split both would arrive here as
// the same class and a rider filtering to one would get the other.
func motisTransitMode(mode string) string {
	switch strings.ToUpper(mode) {
	case "BUS":
		return "Bus"
	case "COACH":
		return "HighwayBus"
	case "SUBWAY":
		return "Subway"
	case "TRAM":
		return "Tram"
	case "HIGHSPEED_RAIL":
		return "THSR"
	case "RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL", "SUBURBAN":
		return "Rail"
	case "FERRY":
		return "Ferry"
	case "AERIAL_LIFT", "FUNICULAR":
		return "CableCar"
	default:
		// WALK, BIKE, RENTAL, CAR and anything MOTIS adds later.
		return ""
	}
}

// motisLegGeometry lifts the street geometry MOTIS already computed for a walk
// leg. Transit legs return nil: their shape comes from the rail line lookup in
// enrichTransitPaths, which is a different source and a different question.
func motisLegGeometry(leg motisLeg) *motisWalkGeometry {
	if motisTransitMode(leg.Mode) != "" {
		return nil
	}
	path := decodeMotisPolyline(leg.LegGeometry)
	if len(path) == 0 && len(leg.Steps) == 0 {
		return nil
	}
	geometry := &motisWalkGeometry{path: path}
	for _, step := range leg.Steps {
		walkStep := &pb.WalkStep{
			Instruction:    motisStepInstruction(step),
			ManeuverType:   "turn",
			Modifier:       motisStepModifier(step.RelativeDirection),
			DistanceMeters: step.Distance,
		}
		if points := decodeMotisPolyline(step.Polyline); len(points) > 0 {
			walkStep.Location = points[0]
		}
		geometry.steps = append(geometry.steps, walkStep)
	}
	return geometry
}

// motisStepModifier maps MOTIS's relativeDirection onto the OSRM modifier
// vocabulary [walkInstruction] and the app already speak, so the turn-by-turn
// list renders identically whichever backend produced it.
func motisStepModifier(direction string) string {
	switch strings.ToUpper(direction) {
	case "HARD_LEFT":
		return "sharp left"
	case "HARD_RIGHT":
		return "sharp right"
	case "LEFT", "CONTINUE_LEFT":
		return "left"
	case "RIGHT", "CONTINUE_RIGHT":
		return "right"
	case "SLIGHTLY_LEFT":
		return "slight left"
	case "SLIGHTLY_RIGHT":
		return "slight right"
	case "UTURN_LEFT", "UTURN_RIGHT":
		return "uturn"
	default:
		// CONTINUE, DEPART, ELEVATOR, STAIRS and anything added later.
		return ""
	}
}

// motisStepInstruction composes the same Traditional Chinese sentence the OSRM
// path produced, reusing [walkInstruction] so the two backends cannot drift
// into two phrasings of the same turn.
func motisStepInstruction(step motisStep) string {
	switch strings.ToUpper(step.RelativeDirection) {
	case "DEPART":
		return walkInstruction("depart", "", step.StreetName)
	case "ARRIVE":
		return walkInstruction("arrive", "", step.StreetName)
	default:
		return walkInstruction("turn", motisStepModifier(step.RelativeDirection), step.StreetName)
	}
}

// applyMotisWalkGeometry fills in the walk paths MOTIS already computed. It
// pairs by position rather than by identity because both slices are built by
// flattening the same routes in the same order; a length mismatch means that
// invariant broke, and leaving the geometry off is better than attaching the
// wrong section's path to a rider's map.
func applyMotisWalkGeometry(refs []maasSectionRef, geometry []*motisWalkGeometry) bool {
	if len(geometry) != len(refs) {
		return false
	}
	for i, ref := range refs {
		leg := geometry[i]
		if leg == nil || ref.target == nil {
			continue
		}
		ref.target.WalkPath = leg.path
		ref.target.WalkSteps = leg.steps
	}
	return true
}

// decodeMotisPolyline decodes a Google-encoded polyline. The precision is read
// from the response rather than assumed: MOTIS documents 7 for its v1 endpoints
// and 6 for v2, so a hardcoded exponent would silently misplace every point by
// a factor of ten the day an endpoint's version moves.
func decodeMotisPolyline(line motisPolyline) []*pb.Location {
	if line.Points == "" {
		return nil
	}
	precision := line.Precision
	if precision <= 0 {
		return nil
	}
	scale := math.Pow10(precision)
	var (
		out     []*pb.Location
		lat     int64
		lng     int64
		index   int
		encoded = line.Points
	)
	readValue := func() (int64, bool) {
		var (
			shift  uint
			result int64
		)
		for {
			if index >= len(encoded) {
				return 0, false
			}
			b := int64(encoded[index]) - 63
			index++
			result |= (b & 0x1f) << shift
			if b < 0x20 {
				break
			}
			shift += 5
			if shift > 60 {
				return 0, false
			}
		}
		if result&1 != 0 {
			return ^(result >> 1), true
		}
		return result >> 1, true
	}
	for index < len(encoded) {
		dLat, ok := readValue()
		if !ok {
			return out
		}
		dLng, ok := readValue()
		if !ok {
			return out
		}
		lat += dLat
		lng += dLng
		out = append(out, &pb.Location{
			Lat: float64(lat) / scale,
			Lng: float64(lng) / scale,
		})
	}
	return out
}

// motisPlanQuery builds the MOTIS plan query from the app's request.
//
// The mode ids are TDX's and stay in the wire contract; they are translated
// here rather than in the app so an old build keeps working. Codes with no
// MOTIS equivalent are dropped rather than widened: asking for a mode the feed
// cannot contain would quietly turn a filtered search into an unfiltered one.
func motisPlanQuery(req *pb.MaasPlanRequest, now time.Time) url.Values {
	query := url.Values{}
	query.Set("fromPlace", fmt.Sprintf("%.6f,%.6f", req.FromLat, req.FromLon))
	query.Set("toPlace", fmt.Sprintf("%.6f,%.6f", req.ToLat, req.ToLon))
	query.Set("time", motisTimeParam(req.Date, req.Time, req.ArriveBy, now))
	if req.ArriveBy {
		query.Set("arriveBy", "true")
	}

	top := clampInt(req.Top, 1, 10, 5)
	// More than the rider asked for, so rankMotisRoutes has alternatives to
	// weigh the price/time preference against before the list is trimmed back.
	query.Set("numItineraries", fmt.Sprintf("%d", min(top+_motisExtraItineraries, _motisMaxItineraries)))

	if modes := motisTransitModes(req.TransitModes); len(modes) > 0 {
		query.Set("transitModes", strings.Join(modes, ","))
	}
	// MOTIS takes a floor, not a window. The upper bound has no equivalent: MOTIS
	// does not reject a connection for waiting too long, it ranks a faster one
	// higher, so only the floor changes which connections are legal. A reversed
	// pair is read as the smaller of the two -- sending the larger would reject
	// connections the rider's own settings allow.
	tMin := clampInt(req.TransferTimeMin, 0, 60, 15)
	tMax := clampInt(req.TransferTimeMax, 0, 60, 60)
	query.Set("minTransferTime", fmt.Sprintf("%d", min(tMin, tMax)))

	firstModes, firstRental := motisMileModes(clampInt(req.FirstMileMode, 0, 3, 0))
	query.Set("preTransitModes", strings.Join(firstModes, ","))
	query.Set("maxPreTransitTime", fmt.Sprintf("%d", clampInt(req.FirstMileTime, 1, 60, 10)*60))
	lastModes, lastRental := motisMileModes(clampInt(req.LastMileMode, 0, 3, 0))
	query.Set("postTransitModes", strings.Join(lastModes, ","))
	query.Set("maxPostTransitTime", fmt.Sprintf("%d", clampInt(req.LastMileTime, 1, 60, 10)*60))
	// Shared bike is RENTAL plus a form-factor filter: without the filter MOTIS
	// would also offer scooters and cargo bikes from any GBFS feed that carries
	// them, which is not what the rider asked for by picking 共享單車.
	if firstRental {
		query.Set("preTransitRentalFormFactors", "BICYCLE")
	}
	if lastRental {
		query.Set("postTransitRentalFormFactors", "BICYCLE")
	}
	addMotisPreferences(query, req)
	return query
}

// addMotisPreferences sends the parameters only MOTIS honours. Each is omitted
// when unset rather than sent at a default, because MOTIS's own defaults are
// the ones its documentation describes and restating them here would mean two
// places to change when it moves.
func addMotisPreferences(query url.Values, req *pb.MaasPlanRequest) {
	if req.Wheelchair {
		query.Set("pedestrianProfile", "WHEELCHAIR")
	}
	// Sent in metres per second, held in centimetres on the wire: the app
	// offers a few discrete paces, and an integer cannot disagree with itself
	// about what "slow" was.
	if speed := clampInt(req.WalkSpeedCmPerSec, 30, 250, 0); speed > 0 {
		query.Set("pedestrianSpeed", strconv.FormatFloat(float64(speed)/100, 'f', 2, 64))
	}
	// Zero is a request here -- direct connections only -- which is why the
	// field carries presence and this reads it rather than testing for zero.
	if req.MaxTransfers != nil {
		query.Set("maxTransfers", strconv.Itoa(int(clampInt(req.GetMaxTransfers(), 0, 5, 0))))
	}
	if req.AvoidReservation {
		query.Set("noCompulsoryReservation", "true")
	}
	if req.CarryBike {
		query.Set("requireBikeTransport", "true")
	}
	if cursor := strings.TrimSpace(req.PageCursor); cursor != "" {
		query.Set("pageCursor", cursor)
		// Paging only means anything against a timetable view: the default
		// search answers one departure window, and a cursor into it has nothing
		// to advance through.
		query.Set("timetableView", "true")
	}
	if alternatives := clampInt(req.LegAlternatives, 1, 5, 0); alternatives > 0 {
		query.Set("numLegAlternatives", strconv.Itoa(int(alternatives)))
	}
}

// motisTimeParam renders the departure or arrival instant MOTIS expects. Unlike
// TDX it takes one RFC 3339 timestamp rather than a depart/arrival pair, and it
// does not reject a time in the past, so no bump is needed. An unparseable date
// or time falls back to now rather than failing the search: the rider asked for
// a plan, and "now" is the answer to a malformed clock.
func motisTimeParam(date, timeStr string, _ bool, now time.Time) string {
	if len(timeStr) == len("HH:mm") {
		timeStr += ":00"
	}
	parsed, err := time.ParseInLocation("2006-01-02T15:04:05", date+"T"+timeStr, time.Local)
	if err != nil {
		return now.Format(time.RFC3339)
	}
	return parsed.Format(time.RFC3339)
}

// motisTransitModes translates the app's TDX mode ids. The mapping is exact
// rather than generous: every value here corresponds to a route_type the feed
// actually emits (gtfs_files.go), so a mode the rider deselects cannot come
// back through a broader MOTIS alias such as RAIL.
func motisTransitModes(modes []int32) []string {
	byID := map[int32][]string{
		3: {"HIGHSPEED_RAIL"},
		4: {"REGIONAL_RAIL"},
		5: {"BUS", "COACH"},
		6: {"SUBWAY"},
		7: {"TRAM"},
		8: {"FERRY"},
		9: {"AERIAL_LIFT"},
	}
	seen := make(map[string]struct{}, len(modes))
	out := make([]string, 0, len(modes))
	for _, id := range modes {
		for _, mode := range byID[id] {
			if _, dup := seen[mode]; dup {
				continue
			}
			seen[mode] = struct{}{}
			out = append(out, mode)
		}
	}
	return out
}

// motisMileModes translates a first/last-mile mode id, reporting whether the
// choice was a shared bike so the caller can add the form-factor filter. Car is
// mapped to CAR even though no Taiwan rider plans one today, because dropping
// it would silently turn the request into a walk.
func motisMileModes(mode int32) (modes []string, rental bool) {
	switch mode {
	case 1:
		return []string{"BIKE"}, false
	case 2:
		return []string{"CAR"}, false
	case 3:
		return []string{"RENTAL", "WALK"}, true
	default:
		return []string{"WALK"}, false
	}
}

// rankMotisRoutes orders itineraries by the rider's price/time preference and
// trims the list to what they asked for.
//
// This exists because MOTIS cannot search on price: withFares is experimental
// and reporting-only, and the documented search criteria are travel time,
// transfers and departure/arrival time (ADR-0022). TDX took the preference as a
// search input, so the slider used to change which itineraries were found; here
// it can only change which of the found ones are shown. An itinerary that is
// much cheaper but much slower is therefore only offered when MOTIS returned it
// anyway -- the slider's reach is genuinely smaller than it was, and no amount
// of ranking recovers that.
//
// gc is the app's slider: 0 is cheapest, 1 is fastest. Both axes are normalised
// against the range actually present in this result set, so the weighting is
// between the alternatives the rider has rather than against an absolute scale
// that would make every urban trip look identical.
func rankMotisRoutes(response *pb.MaasPlanResponse, gc float64, top int32) {
	if response == nil || len(response.Routes) <= 1 {
		return
	}
	if gc < 0 || gc > 1 {
		gc = 0
	}
	minTime, maxTime := response.Routes[0].TravelTime, response.Routes[0].TravelTime
	minFare, maxFare := response.Routes[0].TotalFare, response.Routes[0].TotalFare
	for _, route := range response.Routes {
		minTime = min(minTime, route.TravelTime)
		maxTime = max(maxTime, route.TravelTime)
		minFare = min(minFare, route.TotalFare)
		maxFare = max(maxFare, route.TotalFare)
	}
	// A zero span means every itinerary agrees on that axis, so it carries no
	// information and must not be allowed to divide by zero into one.
	normalise := func(value, low, high int64) float64 {
		if high <= low {
			return 0
		}
		return float64(value-low) / float64(high-low)
	}
	cost := make(map[*pb.Route]float64, len(response.Routes))
	for _, route := range response.Routes {
		timeCost := normalise(route.TravelTime, minTime, maxTime)
		fareCost := normalise(int64(route.TotalFare), int64(minFare), int64(maxFare))
		cost[route] = gc*timeCost + (1-gc)*fareCost
	}
	// SliceStable so itineraries the weighting cannot separate keep the order
	// MOTIS returned them in, which is by departure time.
	sort.SliceStable(response.Routes, func(i, j int) bool {
		return cost[response.Routes[i]] < cost[response.Routes[j]]
	})
	if limit := int(clampInt(top, 1, 10, 5)); len(response.Routes) > limit {
		response.Routes = response.Routes[:limit]
	}
}

// maasBackendName labels the selected planner for the startup log, so the
// answer to "which planner is this container running" is one grep away rather
// than an inference from an env dump.
func maasBackendName(usingMotis bool) string {
	if usingMotis {
		return "motis"
	}
	return _maasBackendTDX
}
