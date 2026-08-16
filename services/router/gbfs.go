package main

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
	"google.golang.org/protobuf/proto"
)

// GBFS (General Bikeshare Feed Specification) exposes the bike-share network to
// a trip planner. GTFS has no concept of shared vehicles, so a planner that is
// to offer a YouBike leg as first or last mile reads it from here instead.
//
// Version 2.3 rather than 3.0: 2.3 is what the planners that consume this
// actually implement, and nothing here needs a 3.0 field.
//
// The feed is served rather than built. Both halves already exist in the
// running system — stations in bike_stations, availability in Redis under
// shared.BikeAvailabilityKey — so a builder would only add a copy to go stale.
const (
	_gbfsVersion = "2.3"
	// _gbfsSystemID identifies the whole feed as one system.
	//
	// Taiwan has several bikeshare operators and GBFS models one operator per
	// feed, so this is a deliberate simplification: it publishes them as a single
	// system. A planner only needs to know where a bike can be picked up and
	// dropped off, and that answer does not change. Split into per-operator feeds
	// if something downstream ever needs to price or brand a leg.
	_gbfsSystemID = "tw"
	// Station locations change on the order of months and availability on the
	// order of seconds; the ttl fields tell a consumer how often to re-poll each.
	// _gbfsStatusTTL matches the 30s bikeEta cron that writes the Redis keys —
	// polling faster than the producer only re-reads the same numbers.
	_gbfsStaticTTL = 3600
	_gbfsStatusTTL = 30
	// _gbfsStatusChunk bounds one MGET. The network is ~10k stations, and asking
	// for every key in a single command makes one oversized request and one
	// oversized reply; chunking keeps both bounded without meaningfully more
	// round trips.
	_gbfsStatusChunk = 1000
	// TDX ServiceStatus: 0 stopped, 1 in service, 2 suspended.
	_bikeServiceStopped   = 0
	_bikeServiceInService = 1
)

// gbfsWrite emits the envelope every GBFS file shares: when it was generated,
// how long it stays valid, the spec version, and the payload.
func gbfsWrite(c *gin.Context, ttl int, data any) {
	c.JSON(http.StatusOK, gin.H{
		"last_updated": time.Now().Unix(),
		"ttl":          ttl,
		"version":      _gbfsVersion,
		"data":         data,
	})
}

// handleGBFSDiscovery serves gbfs.json, the auto-discovery file: the entry point
// a consumer is pointed at, listing the URLs of every other file.
//
// The URLs are absolute per the spec and are built from the request's own scheme
// and host, so the feed is correct behind whatever hostname it is reached by
// without a base-URL setting to keep in sync.
func handleGBFSDiscovery() gin.HandlerFunc {
	return func(c *gin.Context) {
		base := requestBaseURL(c.Request)
		feeds := make([]gin.H, 0, len(_gbfsFeedNames))
		for _, name := range _gbfsFeedNames {
			feeds = append(feeds, gin.H{"name": name, "url": base + "/gbfs/" + name + ".json"})
		}
		// The spec keys feeds by language; this feed is published in one.
		gbfsWrite(c, _gbfsStaticTTL, gin.H{"zh-TW": gin.H{"feeds": feeds}})
	}
}

// requestBaseURL reconstructs the scheme://host the client used. gin has already
// applied the trusted-proxy rules to X-Forwarded-*, so an untrusted client
// cannot forge either value.
func requestBaseURL(r *http.Request) string {
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}
	if forwarded := r.Header.Get("X-Forwarded-Proto"); forwarded != "" {
		scheme = forwarded
	}
	return scheme + "://" + r.Host
}

func handleGBFSSystemInformation() gin.HandlerFunc {
	return func(c *gin.Context) {
		gbfsWrite(c, _gbfsStaticTTL, gin.H{
			"system_id": _gbfsSystemID,
			"language":  "zh-TW",
			"name":      "台灣公共自行車",
			"timezone":  "Asia/Taipei",
		})
	}
}

// gbfsStation is one row of station_information.
type gbfsStation struct {
	StationID string  `json:"station_id"`
	Name      string  `json:"name"`
	Lat       float64 `json:"lat"`
	Lon       float64 `json:"lon"`
	Address   string  `json:"address,omitempty"`
	Capacity  int32   `json:"capacity,omitempty"`
}

// gbfsStations reads the station list. station_uid is the station_id in the feed
// because it is the same key the availability cache is written under, so the two
// files join without a translation table.
//
// Rows with no geometry are skipped: a station GBFS cannot place is one a
// planner cannot route to, and emitting it at (0,0) would put it in the Gulf of
// Guinea.
func gbfsStations(ctx context.Context, db *pgxpool.Pool) ([]gbfsStation, error) {
	rows, err := db.Query(ctx, `
		SELECT station_uid, name, ST_Y(geom), ST_X(geom), COALESCE(address, ''), COALESCE(capacity, 0)
		FROM bike_stations
		WHERE geom IS NOT NULL
		ORDER BY station_uid`)
	if err != nil {
		return nil, _oops.Wrapf(err, "gbfs stations: query")
	}
	defer rows.Close()
	stations := make([]gbfsStation, 0, 12000)
	for rows.Next() {
		var s gbfsStation
		if err := rows.Scan(&s.StationID, &s.Name, &s.Lat, &s.Lon, &s.Address, &s.Capacity); err != nil {
			return nil, _oops.Wrapf(err, "gbfs stations: scan")
		}
		stations = append(stations, s)
	}
	if err := rows.Err(); err != nil {
		return nil, _oops.Wrapf(err, "gbfs stations: rows")
	}
	return stations, nil
}

func handleGBFSStationInformation(db *pgxpool.Pool) gin.HandlerFunc {
	return func(c *gin.Context) {
		stations, err := gbfsStations(c.Request.Context(), db)
		if err != nil {
			zap.S().Errorw("failed",
				"component", "gbfs",
				"action", "station_information",
				"event", "failed",
				"err", err,
			)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "station information unavailable"})
			return
		}
		gbfsWrite(c, _gbfsStaticTTL, gin.H{"stations": stations})
	}
}

// gbfsStatus is one row of station_status.
type gbfsStatus struct {
	StationID         string `json:"station_id"`
	NumBikesAvailable int32  `json:"num_bikes_available"`
	NumDocksAvailable int32  `json:"num_docks_available"`
	IsInstalled       bool   `json:"is_installed"`
	IsRenting         bool   `json:"is_renting"`
	IsReturning       bool   `json:"is_returning"`
	LastReported      int64  `json:"last_reported"`
}

// handleGBFSStationStatus joins the station list to the live availability cache.
//
// A station whose Redis key is absent — never published, or expired past
// bikeLiveTTL because the upstream stopped reporting it — is omitted rather than
// emitted with zeroes. Absent means "no current data", which is what happened;
// zeroes would assert an empty dock the planner would then route around.
func handleGBFSStationStatus(db *pgxpool.Pool, rc *redis.Client) gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx := c.Request.Context()
		stations, err := gbfsStations(ctx, db)
		if err != nil {
			zap.S().Errorw("failed", "component", "gbfs", "action", "station_status", "event", "failed", "err", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "station status unavailable"})
			return
		}
		// The upstream payload carries no per-station observation time, so every
		// row reports the time this response was built. A key that is present was
		// written within its TTL, so the value is accurate to bikeEta's cadence
		// rather than invented — but that cadence is now per-city: a city no rider
		// is streaming refreshes every few minutes instead of every 30s (FDPL-90),
		// and this endpoint does not claim demand for the cities it reads, since
		// it reads every station in the country on every call.
		now := time.Now().Unix()
		statuses := make([]gbfsStatus, 0, len(stations))
		for start := 0; start < len(stations); start += _gbfsStatusChunk {
			end := min(start+_gbfsStatusChunk, len(stations))
			chunk := stations[start:end]
			keys := make([]string, len(chunk))
			for i, s := range chunk {
				keys[i] = shared.BikeAvailabilityKey(s.StationID)
			}
			values, err := rc.MGet(ctx, keys...).Result()
			if err != nil {
				zap.S().Errorw("mget failed",
					"component", "gbfs",
					"action", "station_status",
					"event", "mget_failed",
					"err", err,
				)
				c.JSON(http.StatusInternalServerError, gin.H{"error": "station status unavailable"})
				return
			}
			for i, value := range values {
				status, ok := decodeBikeStatus(chunk[i].StationID, value, now)
				if !ok {
					continue
				}
				statuses = append(statuses, status)
			}
		}
		if len(statuses) < len(stations) {
			zap.S().Infow("partial",
				"component", "gbfs",
				"action", "station_status",
				"event", "partial",
				"stations", len(stations),
				"reported", len(statuses),
			)
		}
		gbfsWrite(c, _gbfsStatusTTL, gin.H{"stations": statuses})
	}
}

// decodeBikeStatus turns one cached Bike_eta into a GBFS status row. It reports
// false for a missing key or an undecodable value, which the caller omits.
func decodeBikeStatus(stationID string, value any, now int64) (gbfsStatus, bool) {
	// MGET yields nil for a key that is absent or expired. An empty string is
	// treated the same way: bikeEta always sets StationUID, so a marshaled
	// Bike_eta is never zero-length, and a zero-length value means a corrupt or
	// truncated write rather than a station with nothing at it.
	raw, ok := value.(string)
	if !ok || raw == "" {
		return gbfsStatus{}, false
	}
	var eta models.BikeEta
	if err := proto.Unmarshal([]byte(raw), &eta); err != nil {
		zap.S().Warnw("decode failed",
			"component", "gbfs",
			"action", "station_status",
			"station", stationID,
			"event", "decode_failed",
			"err", err,
		)
		return gbfsStatus{}, false
	}
	inService := eta.GetServiceStatus() == _bikeServiceInService
	return gbfsStatus{
		StationID: stationID,
		// TDX splits the rentable count by vehicle kind. GBFS carries that split
		// in a vehicle_types feed, which this one does not publish: a planner
		// choosing a station needs to know a bike is there, not which kind. Add
		// vehicle_types when a leg's speed or price depends on the distinction.
		NumBikesAvailable: eta.GetGeneralBikes() + eta.GetElectricBikes(),
		NumDocksAvailable: eta.GetAvailableReturnBikes(),
		IsInstalled:       eta.GetServiceStatus() != _bikeServiceStopped,
		IsRenting:         inService,
		IsReturning:       inService,
		LastReported:      now,
	}, true
}

// _gbfsFeedNames is the file set the discovery document advertises. It is also
// what registerGBFSRoutes mounts, so a file cannot be advertised without being
// served.
var _gbfsFeedNames = []string{"system_information", "station_information", "station_status"}

// RegisterGBFSRoutes mounts the feed. Every file is unauthenticated: the whole
// point is that a planner can poll it. The rate limit is the only guard, and it
// is shared across the files because they are polled together.
func RegisterGBFSRoutes(r gin.IRoutes, db *pgxpool.Pool, rc *redis.Client, limit gin.HandlerFunc) {
	handlers := map[string]gin.HandlerFunc{
		"system_information":  handleGBFSSystemInformation(),
		"station_information": handleGBFSStationInformation(db),
		"station_status":      handleGBFSStationStatus(db, rc),
	}
	r.GET("/gbfs/gbfs.json", limit, handleGBFSDiscovery())
	for _, name := range _gbfsFeedNames {
		r.GET("/gbfs/"+name+".json", limit, handlers[name])
	}
}
