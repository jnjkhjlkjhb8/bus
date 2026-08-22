package search

// The geocoding endpoint (ADR-0022).
//
// MOTIS sits on the internal routing network, so the app cannot reach it. This
// is the proxy: it takes what the rider has typed, asks MOTIS's OSM-backed
// geocoder, and returns the matches in the small shape the planner's
// origin/destination picker needs.
//
// It is deliberately not folded into /api/search. That endpoint answers "which
// stop or route is this", from the PowerSync-replicated search_vector table,
// offline-capable and phonetic-alias aware. This one answers "which address or
// place is this", online only, from OpenStreetMap. Same-looking question,
// different data, different failure modes, different caching.
//
// The app treats this as the first source and falls back to Google Places when
// it returns nothing: Taiwan OSM covers addresses reasonably and named
// businesses poorly, and the planner's entry point is not a place to regress.

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-resty/resty/v2"
	"go.uber.org/zap"
)

const (
	// GeocodePath is what the app calls.
	GeocodePath = "/api/geocode"
	// _motisGeocodePath is what MOTIS serves.
	_motisGeocodePath = "/api/v1/geocode"
	// _geocodeTimeout is short on purpose: this runs on every keystroke, and a
	// suggestion that arrives after the rider has typed three more characters
	// is worse than no suggestion.
	_geocodeTimeout = 3 * time.Second
	// _geocodeMaxResults bounds what MOTIS is asked for. The picker shows a
	// handful; asking for its default 10 and rendering five wastes the trip.
	_geocodeMaxResults = 8
	// _geocodeMaxQueryRunes rejects a query no geocoder can use. Counted in
	// runes, not bytes, because a Chinese address is three bytes a character
	// and a byte bound would cut off a legitimate query.
	_geocodeMaxQueryRunes = 120
	// _geocodeLanguage is what MOTIS reads OSM names in. Taiwan OSM names are
	// already Chinese, so this only decides which of several tagged names wins.
	_geocodeLanguage = "zh"
)

// motisMatch is the subset of a MOTIS geocoding match the picker needs.
type motisMatch struct {
	Type        string  `json:"type"`
	Name        string  `json:"name"`
	ID          string  `json:"id"`
	Lat         float64 `json:"lat"`
	Lon         float64 `json:"lon"`
	Street      string  `json:"street"`
	HouseNumber string  `json:"houseNumber"`
}

// geocodeSuggestion is what the app reads. Coordinates are included because,
// unlike Google Places, MOTIS resolves them in the same call -- there is no
// second "details" round trip, and the picker can skip one.
type geocodeSuggestion struct {
	Name      string  `json:"name"`
	Address   string  `json:"address,omitempty"`
	Latitude  float64 `json:"lat"`
	Longitude float64 `json:"lon"`
	Type      string  `json:"type"`
}

// RegisterGeocodeRoutes mounts the proxy. A nil client means MOTIS is not the
// configured planner, in which case there is nothing to proxy and the route
// stays unmounted -- the app's Google Places fallback is then its only source,
// which is exactly the degraded behaviour a kill switch should produce.
func RegisterGeocodeRoutes(r gin.IRoutes, baseURL string, mounted bool, limit gin.HandlerFunc) {
	if !mounted || baseURL == "" {
		return
	}
	client := resty.New().SetBaseURL(baseURL).SetTimeout(_geocodeTimeout)
	r.GET(GeocodePath, limit, handleGeocode(client))
}

// handleGeocode answers with suggestions, or with an empty list. An upstream
// failure is 503 rather than an empty 200: the app falls back to Google Places
// on an error, and an empty 200 would tell it there is genuinely nothing there,
// which is a different and wrong claim.
func handleGeocode(client *resty.Client) gin.HandlerFunc {
	return func(c *gin.Context) {
		text := strings.TrimSpace(c.Query("text"))
		if text == "" || len([]rune(text)) > _geocodeMaxQueryRunes {
			c.AbortWithStatus(http.StatusBadRequest)
			return
		}

		request := client.R().
			SetContext(c.Request.Context()).
			SetQueryParam("text", text).
			SetQueryParam("language", _geocodeLanguage).
			SetQueryParam("numResults", strconv.Itoa(_geocodeMaxResults))
		// Biasing towards where the rider is, when the app knows. A planner
		// query is almost always local, and without this "車站" matches the
		// whole island by score alone.
		if place, ok := geocodeBias(c.Query("lat"), c.Query("lon")); ok {
			request.SetQueryParam("place", place)
		}

		var matches []motisMatch
		resp, err := request.SetResult(&matches).Get(_motisGeocodePath)
		if err != nil || !resp.IsSuccess() {
			status := 0
			if resp != nil {
				status = resp.StatusCode()
			}
			zap.S().Warnw("geocode upstream failed",
				"component", "geocode",
				"action", "suggest",
				"event", "upstream_failed",
				"status_code", status,
				"err", err,
			)
			c.AbortWithStatus(http.StatusServiceUnavailable)
			return
		}
		c.Header("Cache-Control", "no-store")
		c.JSON(http.StatusOK, gin.H{"suggestions": geocodeSuggestions(matches)})
	}
}

// geocodeBias renders the lat/lon bias parameter, reporting whether the caller
// supplied a usable pair. A malformed or null-island coordinate is dropped
// rather than sent: biasing towards 0,0 pulls every Taiwan result away from the
// rider.
func geocodeBias(latText, lonText string) (string, bool) {
	lat, latErr := strconv.ParseFloat(strings.TrimSpace(latText), 64)
	lon, lonErr := strconv.ParseFloat(strings.TrimSpace(lonText), 64)
	if latErr != nil || lonErr != nil {
		return "", false
	}
	if lat == 0 && lon == 0 {
		return "", false
	}
	if lat < -90 || lat > 90 || lon < -180 || lon > 180 {
		return "", false
	}
	return strconv.FormatFloat(lat, 'f', 6, 64) + "," + strconv.FormatFloat(lon, 'f', 6, 64), true
}

// geocodeSuggestions maps matches onto the app's shape, dropping any that
// cannot be navigated to. A match with no coordinates is a row the rider can
// tap and get nothing from.
func geocodeSuggestions(matches []motisMatch) []geocodeSuggestion {
	out := make([]geocodeSuggestion, 0, len(matches))
	for _, match := range matches {
		if match.Name == "" || (match.Lat == 0 && match.Lon == 0) {
			continue
		}
		out = append(out, geocodeSuggestion{
			Name:      match.Name,
			Address:   geocodeAddress(match),
			Latitude:  match.Lat,
			Longitude: match.Lon,
			Type:      match.Type,
		})
	}
	return out
}

// geocodeAddress composes the secondary line under the name. Taiwan writes the
// house number after the street, which is the opposite of the Western order
// most geocoding clients assume.
func geocodeAddress(match motisMatch) string {
	switch {
	case match.Street != "" && match.HouseNumber != "":
		return match.Street + match.HouseNumber + "號"
	case match.Street != "":
		return match.Street
	default:
		return ""
	}
}
