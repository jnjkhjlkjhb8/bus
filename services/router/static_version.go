package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// StaticVersionPath serves the identity of the static dataset this environment
// currently holds. The app namespaces its offline cache (ADR-0017) on the
// value, so a nightly load is what expires a cached route — not a TTL that
// guesses when the data moved.
const StaticVersionPath = "/api/static-version"

// staticVersionCacheTTL bounds how stale a served version may be. The value
// only changes at 03:30 (and on a LOAD_ON_BOOT restart), so a few minutes of
// lag costs nothing and keeps a launch spike off the database. The app fetches
// this once per launch.
const staticVersionCacheTTL = 5 * time.Minute

const staticVersionCacheKey = "static-version"

type staticVersionResponse struct {
	Version string `json:"version"`
}

// HandleStaticVersion reports when this environment's static tables were last
// fully loaded, as unix seconds. An environment that has never completed a
// load reports "0" rather than an error: that is a real, stable answer, and
// failing here would make every app launch clear its cache for nothing.
func HandleStaticVersion(db *pgxpool.Pool) gin.HandlerFunc {
	return handleStaticVersion(NewTTLCache(), func(ctx context.Context) (string, error) {
		var completedAt time.Time
		err := db.QueryRow(ctx,
			`SELECT completed_at FROM pipeline_runs
			 WHERE job = 'load' ORDER BY run_date DESC LIMIT 1`,
		).Scan(&completedAt)
		if errors.Is(err, pgx.ErrNoRows) {
			return "0", nil
		}
		if err != nil {
			return "", fmt.Errorf("query pipeline_runs load marker: %w", err)
		}
		return strconv.FormatInt(completedAt.Unix(), 10), nil
	})
}

// handleStaticVersion is the transport half, split from the query so it can be
// tested without a database.
func handleStaticVersion(cache *TTLCache, read func(context.Context) (string, error)) gin.HandlerFunc {
	return func(c *gin.Context) {
		if body, ok := cache.get(staticVersionCacheKey); ok {
			c.Data(http.StatusOK, gin.MIMEJSON, body)
			return
		}
		version, err := read(c.Request.Context())
		if err != nil {
			// The client treats any failure as "keep what you have", so a blip
			// here degrades to the previous behaviour (cache stays valid)
			// rather than to a wipe.
			log.Errorf("[HTTP] action=static_version event=read_failed error=%v", err)
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "static version unavailable"})
			return
		}
		body, err := json.Marshal(staticVersionResponse{Version: version})
		if err != nil {
			log.Errorf("[HTTP] action=static_version event=encode_failed error=%v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "static version unavailable"})
			return
		}
		cache.set(staticVersionCacheKey, body, staticVersionCacheTTL)
		c.Data(http.StatusOK, gin.MIMEJSON, body)
	}
}
