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
	"io"
	"math/big"
	"net"
	"net/http"
	"net/netip"
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
	trustedProxiesEnv    = "ROUTER_TRUSTED_PROXIES"
	httpTokenRateLimit   = 10
	httpJWKSRateLimit    = 120
	httpSearchRateLimit  = 30
	httpMetricsRateLimit = 60
)

type httpServerConfig struct {
	MetricsCredential string
	TrustedProxies    []netip.Prefix
	TokenRateLimit    int
	JWKSRateLimit     int
	SearchRateLimit   int
	MetricsRateLimit  int
}

func httpServerConfigFromEnv() (httpServerConfig, error) {
	metricsCredential, err := metricsCredentialFromEnv()
	if err != nil {
		return httpServerConfig{}, err
	}
	trustedProxies, err := trustedProxiesFromEnv()
	if err != nil {
		return httpServerConfig{}, err
	}
	return httpServerConfig{MetricsCredential: metricsCredential, TrustedProxies: trustedProxies}, nil
}

func trustedProxiesFromEnv() ([]netip.Prefix, error) {
	raw := strings.TrimSpace(os.Getenv(trustedProxiesEnv))
	if raw == "" {
		return nil, nil
	}
	parts := strings.Split(raw, ",")
	proxies := make([]netip.Prefix, 0, len(parts))
	for _, part := range parts {
		value := strings.TrimSpace(part)
		prefix, err := netip.ParsePrefix(value)
		if err != nil {
			addr, addrErr := netip.ParseAddr(value)
			if addrErr != nil {
				return nil, fmt.Errorf("%s contains invalid IP or CIDR %q", trustedProxiesEnv, value)
			}
			prefix = netip.PrefixFrom(addr, addr.BitLen())
		}
		prefix = prefix.Masked()
		addressBits := prefix.Addr().BitLen()
		network := &net.IPNet{
			IP:   net.IP(prefix.Addr().AsSlice()),
			Mask: net.CIDRMask(prefix.Bits(), addressBits),
		}
		if network.Contains(net.IPv4zero) || network.Contains(net.IPv6zero) {
			return nil, fmt.Errorf("%s contains unsafe catch-all or unspecified proxy %q", trustedProxiesEnv, value)
		}
		proxies = append(proxies, prefix)
	}
	return proxies, nil
}

func startHTTPServer(db *pgxpool.Pool, live *liveHub, config httpServerConfig) {
	key, err := loadOrGenerateKey()
	if err != nil {
		log.Fatalf("[HTTP] failed to load/generate RSA key: %v", err)
	}
	log.Infof("[HTTP] RS256 key ready")
	gin.SetMode(gin.ReleaseMode)
	r := newHTTPRouter(db, live, key, config)
	log.Infof("[HTTP] server running on 0.0.0.0:8080")
	if err := r.Run("0.0.0.0:8080"); err != nil {
		log.Fatalf("[HTTP] server failed: %v", err)
	}
}

func newHTTPRouter(db *pgxpool.Pool, live *liveHub, key *rsa.PrivateKey, config httpServerConfig) *gin.Engine {
	r := gin.New()
	trustedProxies := make([]string, len(config.TrustedProxies))
	for index, prefix := range config.TrustedProxies {
		trustedProxies[index] = prefix.String()
	}
	if err := r.SetTrustedProxies(trustedProxies); err != nil {
		panic(fmt.Sprintf("validated trusted proxy configuration rejected: %v", err))
	}
	r.Use(safeAccessLogger(gin.DefaultWriter), gin.Recovery())
	r.Use(sentrygin.New(sentrygin.Options{Repanic: true}))
	limiter := newRateLimiter()
	tokenLimit := configuredLimit(config.TokenRateLimit, httpTokenRateLimit)
	jwksLimit := configuredLimit(config.JWKSRateLimit, httpJWKSRateLimit)
	searchLimit := configuredLimit(config.SearchRateLimit, httpSearchRateLimit)
	metricsLimit := configuredLimit(config.MetricsRateLimit, httpMetricsRateLimit)
	r.GET("/api/token/powersync",
		httpRateLimit(limiter, "GET /api/token/powersync", tokenLimit, time.Minute),
		handleToken(key))
	r.GET("/api/.well-known/jwks.json",
		httpRateLimit(limiter, "GET /api/.well-known/jwks.json", jwksLimit, time.Minute),
		handleJWKS(key))
	r.GET("/api/search",
		httpRateLimit(limiter, "GET /api/search", searchLimit, time.Second),
		handleSearch(db))
	r.GET("/metrics",
		requireMetricsCredential(config.MetricsCredential),
		httpPrincipalRateLimit(limiter, "GET /metrics", metricsLimit, time.Minute),
		handleMetrics(live))
	return r
}

func configuredLimit(configured, fallback int) int {
	if configured > 0 {
		return configured
	}
	return fallback
}

func safeAccessLogger(writer io.Writer) gin.HandlerFunc {
	return func(c *gin.Context) {
		started := time.Now()
		c.Next()
		_, _ = fmt.Fprintf(writer, "[HTTP] method=%s path=%s status=%d latency=%s\n",
			c.Request.Method, c.Request.URL.EscapedPath(), c.Writer.Status(), time.Since(started))
	}
}

func httpRateLimit(limiter *rateLimiter, scope string, limit int, window time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		caller := c.ClientIP()
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

const metricsPrincipalContextKey = "metrics-principal"

func httpPrincipalRateLimit(limiter *rateLimiter, scope string, limit int, window time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		principal, ok := c.Get(metricsPrincipalContextKey)
		caller, valid := principal.(string)
		if !ok || !valid || caller == "" {
			c.AbortWithStatus(http.StatusUnauthorized)
			return
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
	credential := os.Getenv(metricsCredentialEnv)
	if credential != strings.TrimSpace(credential) {
		return "", fmt.Errorf("%s must not contain leading or trailing whitespace", metricsCredentialEnv)
	}
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
	principal := fmt.Sprintf("metrics:%x", expectedHash[:8])
	return func(c *gin.Context) {
		c.Header("Cache-Control", "no-store")
		provided := parseBearerCredential(c.GetHeader("Authorization"))
		providedHash := sha256.Sum256([]byte(provided))
		if provided == "" || subtle.ConstantTimeCompare(providedHash[:], expectedHash[:]) != 1 {
			c.Header("WWW-Authenticate", "Bearer")
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		c.Set(metricsPrincipalContextKey, principal)
		c.Next()
	}
}

func parseBearerCredential(header string) string {
	if header == "" || header != strings.TrimSpace(header) {
		return ""
	}
	separator := strings.IndexAny(header, " \t")
	if separator <= 0 || !strings.EqualFold(header[:separator], "Bearer") {
		return ""
	}
	credentialStart := separator
	for credentialStart < len(header) && (header[credentialStart] == ' ' || header[credentialStart] == '\t') {
		credentialStart++
	}
	if credentialStart == len(header) {
		return ""
	}
	credential := header[credentialStart:]
	if strings.IndexAny(credential, " \t\r\n") >= 0 {
		return ""
	}
	return credential
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
