package maas

// GET /api/planner — which planner is live, and what it can be asked for.
//
// The app renders a different set of planning options per backend, because the
// two backends genuinely differ: MOTIS accepts a wheelchair profile, a transfer
// cap and a "no reservation required" filter that TDX has no equivalent for,
// while TDX takes the price/time preference as a search input rather than a
// ranking. Hardcoding one set in the app would mean shipping controls that
// silently do nothing whenever the other backend is live.
//
// So the capability list is served rather than assumed. The app polls this,
// renders the options the live planner actually honours, and shows the operator
// -- and only the operator -- why the backend is what it is.

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

const (
	// PlannerStatusPath is what the app polls.
	PlannerStatusPath = "/api/planner"
	// _plannerStatusMaxAge lets the app cache the answer briefly. Shorter than
	// the health interval so a backend change surfaces within roughly one
	// check, and long enough that opening the planner twice in a minute does
	// not ask twice.
	_plannerStatusMaxAge = 20
)

// Capability names. These are the contract with the app: it maps each to a
// control in the options sheet, and renders nothing for a name it does not
// recognise, so adding one here cannot break an older build.
const (
	// Shared by both planners.
	_capTransitModes    = "transitModes"
	_capItineraryCount  = "itineraryCount"
	_capTransferWindow  = "transferWindow"
	_capFirstLastMile   = "firstLastMile"
	_capPricePreference = "pricePreference"

	// MOTIS only.
	_capWheelchair        = "wheelchair"
	_capWalkingSpeed      = "walkingSpeed"
	_capExtraTransferTime = "extraTransferTime"
	_capMaxTransfers      = "maxTransfers"
	_capMaxTravelTime     = "maxTravelTime"
	_capAvoidReservation  = "avoidReservation"
	_capCarryBike         = "carryBike"
	_capEarlierLater      = "earlierLater"
	_capLegAlternatives   = "legAlternatives"
	_capViaStop           = "viaStop"
	_capDirectComparison  = "directComparison"
	_capAvoidElevation    = "avoidElevation"
	_capShowSkippedStops  = "showSkippedStops"
	_capIgnoreRealtime    = "ignoreRealtime"
)

// plannerCapabilities lists what the given backend honours.
//
// The shared five are first and in the same order for both, so the options
// sheet does not reshuffle under the rider when the backend changes -- only the
// advanced section appears or disappears.
func plannerCapabilities(backend PlannerBackend) []string {
	shared := []string{
		_capTransitModes,
		_capItineraryCount,
		_capTransferWindow,
		_capFirstLastMile,
		_capPricePreference,
	}
	if backend != _plannerMotis {
		return shared
	}
	// Grown once to its final length rather than five times by append.
	capabilities := make([]string, 0, len(shared)+14)
	capabilities = append(capabilities, shared...)
	return append(capabilities,
		_capWheelchair,
		_capWalkingSpeed,
		_capExtraTransferTime,
		_capMaxTransfers,
		_capMaxTravelTime,
		_capAvoidReservation,
		_capCarryBike,
		_capEarlierLater,
		_capLegAlternatives,
		_capViaStop,
		_capDirectComparison,
		_capAvoidElevation,
		_capShowSkippedStops,
		_capIgnoreRealtime,
	)
}

// plannerStatusBody is the response. The status fields are for an operator; the
// app reads `backend` and `capabilities` and ignores the rest.
type plannerStatusBody struct {
	PlannerStatus
	Capabilities []string `json:"capabilities"`
}

// RegisterPlannerStatusRoutes mounts the endpoint. Unlike the geocode proxy this
// is always mounted: an app that cannot tell which planner is live has to guess,
// and guessing is what this exists to remove.
func RegisterPlannerStatusRoutes(r gin.IRoutes, monitor *PlannerHealthMonitor, limit gin.HandlerFunc) {
	r.GET(PlannerStatusPath, limit, handlePlannerStatus(monitor))
}

func handlePlannerStatus(monitor *PlannerHealthMonitor) gin.HandlerFunc {
	return func(c *gin.Context) {
		status := monitor.Status()
		c.Header("Cache-Control", "public, max-age="+strconv.Itoa(_plannerStatusMaxAge))
		c.JSON(http.StatusOK, plannerStatusBody{
			PlannerStatus: status,
			Capabilities:  plannerCapabilities(status.Backend),
		})
	}
}
