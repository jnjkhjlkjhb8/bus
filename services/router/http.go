package main

import (
	"crypto"
	cryptorand "crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"os"
	"runtime"
	"strings"
	"time"

	sentrygin "github.com/getsentry/sentry-go/gin"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	metricsCredentialEnv = "ROUTER_METRICS_TOKEN"
	httpTokenRateLimit   = 10
	httpJWKSRateLimit    = 120
	httpSearchRateLimit  = 30
	httpMetricsRateLimit = 60
)

func startHTTPServer(db *pgxpool.Pool, live *liveHub) {
	metricsCredential, err := metricsCredentialFromEnv()
	if err != nil {
		log.Fatalf("[HTTP] metrics credential configuration failed: %v", err)
	}
	key, err := loadOrGenerateKey()
	if err != nil {
		log.Fatalf("[HTTP] failed to load/generate RSA key: %v", err)
	}
	log.Infof("[HTTP] RS256 key ready")
	gin.SetMode(gin.ReleaseMode)
	r := newHTTPRouter(db, live, key, metricsCredential)
	log.Infof("[HTTP] server running on 0.0.0.0:8080")
	if err := r.Run("0.0.0.0:8080"); err != nil {
		log.Fatalf("[HTTP] server failed: %v", err)
	}
}

func newHTTPRouter(db *pgxpool.Pool, live *liveHub, key *rsa.PrivateKey, metricsCredential string) *gin.Engine {
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery())
	r.Use(sentrygin.New(sentrygin.Options{Repanic: true}))
	limiter := newRateLimiter()
	r.GET("/api/token/powersync",
		httpRateLimit(limiter, "GET /api/token/powersync", httpTokenRateLimit, time.Minute),
		handleToken(key))
	r.GET("/api/.well-known/jwks.json",
		httpRateLimit(limiter, "GET /api/.well-known/jwks.json", httpJWKSRateLimit, time.Minute),
		handleJWKS(key))
	r.GET("/api/search",
		httpRateLimit(limiter, "GET /api/search", httpSearchRateLimit, time.Second),
		handleSearch(db))
	r.GET("/metrics",
		httpRateLimit(limiter, "GET /metrics", httpMetricsRateLimit, time.Minute),
		requireMetricsCredential(metricsCredential),
		handleMetrics(live))
	return r
}

func httpRateLimit(limiter *rateLimiter, scope string, limit int, window time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		caller := c.Request.RemoteAddr
		if host, _, err := net.SplitHostPort(caller); err == nil {
			caller = host
		}
		if caller == "" {
			caller = "unknown"
		}
		if !limiter.allow(scope, caller, limit, window) {
			c.Header("Retry-After", fmt.Sprint(max(1, int(window/time.Second))))
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{"error": "rate limit exceeded"})
			return
		}
		c.Next()
	}
}

func metricsCredentialFromEnv() (string, error) {
	credential := strings.TrimSpace(os.Getenv(metricsCredentialEnv))
	if len(credential) < 32 {
		return "", fmt.Errorf("%s must be configured with at least 32 characters", metricsCredentialEnv)
	}
	return credential, nil
}

// requireMetricsCredential accepts the credential only in the Authorization
// header, keeping it out of URLs and access logs. Hashing both values before the
// constant-time comparison avoids leaking the configured credential length.
func requireMetricsCredential(expected string) gin.HandlerFunc {
	expectedHash := sha256.Sum256([]byte(expected))
	return func(c *gin.Context) {
		const prefix = "Bearer "
		header := c.GetHeader("Authorization")
		provided := ""
		if strings.HasPrefix(header, prefix) {
			provided = strings.TrimPrefix(header, prefix)
		}
		providedHash := sha256.Sum256([]byte(provided))
		if provided == "" || subtle.ConstantTimeCompare(providedHash[:], expectedHash[:]) != 1 {
			c.Header("Cache-Control", "no-store")
			c.Header("WWW-Authenticate", "Bearer")
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		c.Header("Cache-Control", "no-store")
		c.Next()
	}
}

func handleMetrics(live *liveHub) gin.HandlerFunc {
	return func(c *gin.Context) {
		stats := live.stats()
		body := fmt.Sprintf(
			"router_live_streams %d\nrouter_live_channels %d\nrouter_live_dropped_frames_total %d\nrouter_goroutines %d\n",
			stats.ActiveStreams,
			stats.ActiveChannels,
			stats.DroppedFrames,
			runtime.NumGoroutine(),
		)
		c.Data(200, "text/plain; version=0.0.4; charset=utf-8", []byte(body))
	}
}
func handleToken(key *rsa.PrivateKey) gin.HandlerFunc {
	return func(c *gin.Context) {
		now := time.Now()
		token, err := signRS256(key, map[string]any{
			"sub": "powersync-client",
			"aud": "powersync",
			"iat": now.Unix(),
			"exp": now.Add(24 * time.Hour).Unix(),
		})
		if err != nil {
			c.JSON(500, gin.H{"error": "sign failed"})
			return
		}
		c.JSON(200, gin.H{"token": token})
	}
}
func handleJWKS(key *rsa.PrivateKey) gin.HandlerFunc {
	pub := &key.PublicKey
	n := base64.RawURLEncoding.EncodeToString(pub.N.Bytes())
	e := base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes())
	body := gin.H{
		"keys": []gin.H{{
			"kty": "RSA", "use": "sig", "alg": "RS256", "kid": "k1",
			"n": n, "e": e,
		}},
	}
	return func(c *gin.Context) { c.JSON(200, body) }
}
func signRS256(key *rsa.PrivateKey, claims map[string]any) (string, error) {
	header := b64j(map[string]string{"alg": "RS256", "typ": "JWT", "kid": "k1"})
	payload := b64j(claims)
	msg := header + "." + payload
	h := sha256.New()
	h.Write([]byte(msg))
	sig, err := rsa.SignPKCS1v15(cryptorand.Reader, key, crypto.SHA256, h.Sum(nil))
	if err != nil {
		return "", err
	}
	return msg + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}
func b64j(v any) string {
	b, _ := json.Marshal(v)
	return base64.RawURLEncoding.EncodeToString(b)
}

func loadOrGenerateKey() (*rsa.PrivateKey, error) {
	return loadOrGenerateKeyAt("/data/powersync_key.pem")
}

// loadOrGenerateKeyAt loads the persisted RS256 signing key, generating and
// persisting a fresh one when the file is missing or unparseable. A key change
// invalidates every client's PowerSync JWT at once, so keeping the persisted
// key readable across restarts is what keeps sync alive.
func loadOrGenerateKeyAt(keyFile string) (*rsa.PrivateKey, error) {
	data, err := os.ReadFile(keyFile)
	if err == nil {
		block, _ := pem.Decode(data)
		if block != nil {
			key, err := x509.ParsePKCS1PrivateKey(block.Bytes)
			if err == nil {
				log.Infof("[HTTP] loaded persisted RSA key from %s", keyFile)
				return key, nil
			}
		}
	}
	key, err := rsa.GenerateKey(cryptorand.Reader, 2048)
	if err != nil {
		return nil, err
	}
	data = pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(key),
	})
	_ = os.WriteFile(keyFile, data, 0600)
	log.Infof("[HTTP] generated new RSA key and persisted to %s", keyFile)
	return key, nil
}
