package main

import (
	"crypto/sha256"
	"crypto/subtle"
	"errors"
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// The GTFS-RT endpoint (ADR-0019).
//
// This file serves; it does not build. services/functions rebuilds the whole
// FeedMessage on a cron and leaves the serialized bytes in one Redis key, and
// the handler returns them verbatim. The router therefore holds no GTFS-RT
// types and no background work: the request path stays a request path.
//
// The key's TTL is the liveness check. A stopped builder lets it expire, this
// returns 503, and a planner falls back to the static timetable — which is the
// right answer, and strictly better than serving a snapshot that is quietly
// hours old because nothing noticed the builder died.

const (
	// gtfsRTCredentialEnv is the shared secret MOTIS sends. Prod binds the HTTP
	// port to 0.0.0.0 with no reverse proxy, so an ungated route here is a public
	// route. Unset means the endpoint is not mounted at all: an environment
	// without a credential serves no feed rather than an open one.
	gtfsRTCredentialEnv = "GTFS_RT_CREDENTIAL"
	// gtfsRTCredentialMinLength matches the metrics credential's floor. The value
	// is a machine-to-machine secret, so there is no reason for it to be short.
	gtfsRTCredentialMinLength = 32
	// GTFSRTPath is what MOTIS is pointed at. The extension is part of the name
	// because the body is protobuf, not JSON like everything else under /api.
	GTFSRTPath = "/api/gtfs-rt/trip-updates.pb"
	// gtfsRTContentType is the type GTFS-RT feeds are conventionally served as.
	gtfsRTContentType = "application/x-protobuf"
)

// GTFSRTCredentialFromEnv reads the endpoint's shared secret. An empty value is
// not an error — it means "do not mount the endpoint" — but a short or padded
// one is, because that is a misconfiguration rather than a decision.
func GTFSRTCredentialFromEnv() (string, error) {
	credential := os.Getenv(gtfsRTCredentialEnv)
	if credential == "" {
		return "", nil
	}
	if credential != strings.TrimSpace(credential) {
		return "", errors.New(gtfsRTCredentialEnv + " must not contain leading or trailing whitespace")
	}
	if len(credential) < gtfsRTCredentialMinLength {
		return "", errors.New(gtfsRTCredentialEnv + " must be at least 32 characters")
	}
	return credential, nil
}

// RegisterGTFSRTRoutes mounts the feed. Both a credential and a Redis client are
// required: without the first the route would be public, and without the second
// there is nothing to serve.
func RegisterGTFSRTRoutes(r gin.IRoutes, rc *redis.Client, credential string, limit gin.HandlerFunc) {
	if rc == nil || credential == "" {
		return
	}
	r.GET(GTFSRTPath, limit, requireGTFSRTCredential(credential), handleGTFSRT(rc))
}

// requireGTFSRTCredential accepts the secret only in the Authorization header,
// which is where MOTIS's own `headers:` config puts it and keeps it out of URLs
// and access logs. Both sides are hashed before the constant-time comparison so
// the configured length does not leak.
func requireGTFSRTCredential(expected string) gin.HandlerFunc {
	expectedHash := sha256.Sum256([]byte(expected))
	return func(c *gin.Context) {
		c.Header("Cache-Control", "no-store")
		provided := ParseBearerCredential(c.GetHeader("Authorization"))
		providedHash := sha256.Sum256([]byte(provided))
		if provided == "" || subtle.ConstantTimeCompare(providedHash[:], expectedHash[:]) != 1 {
			c.Header("WWW-Authenticate", "Bearer")
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		c.Next()
	}
}

// handleGTFSRT returns the current snapshot. A missing key is 503 rather than an
// empty feed: an empty FeedMessage is a valid statement that nothing is
// cancelled and nothing is delayed, which is exactly the wrong thing to say when
// the truth is that we do not know.
func handleGTFSRT(rc *redis.Client) gin.HandlerFunc {
	return func(c *gin.Context) {
		payload, err := rc.Get(c.Request.Context(), shared.GTFSRealtimeKey()).Bytes()
		if errors.Is(err, redis.Nil) {
			c.AbortWithStatus(http.StatusServiceUnavailable)
			return
		}
		if err != nil {
			zap.S().Errorw("read failed",
				"component", "gtfs_rt",
				"action", "serve",
				"event", "read_failed",
				"err", err,
			)
			c.AbortWithStatus(http.StatusServiceUnavailable)
			return
		}
		c.Data(http.StatusOK, gtfsRTContentType, payload)
	}
}
