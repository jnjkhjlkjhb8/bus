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
	"net/netip"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	sentrygin "github.com/getsentry/sentry-go/gin"
	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

const (
	_metricsCredentialEnv = "ROUTER_METRICS_TOKEN"
	_trustedProxiesEnv    = "ROUTER_TRUSTED_PROXIES"
	_httpTokenRateLimit   = 10
	_httpJWKSRateLimit    = 120
	_httpSearchRateLimit  = 30
	_httpMetricsRateLimit = 60
	_httpBookingRateLimit = 30
	_httpGBFSRateLimit    = 120
	// MOTIS polls its realtime endpoints once a minute by default, and the feed
	// has exactly one authenticated consumer, so this is generous already.
	_httpGTFSRTRateLimit = 10
	// Per minute, and tighter than /api/search's 30 per second because the two
	// are backed by different things: /api/search hits Postgres, while this one
	// hits the planner. Spending MOTIS on autocomplete would degrade route
	// planning, which is the more expensive thing to lose.
	_httpGeocodeRateLimit = 60
	// Per minute. The app polls this when the planner opens and caches the
	// answer for 20s, so this is generous by an order of magnitude on purpose:
	// an app rate-limited here falls back to guessing which options exist,
	// which is the thing the endpoint was added to stop.
	_httpPlannerStatusRateLimit = 60
	// One fetch per app launch, answered from a process-local cache, so this
	// only has to survive a device relaunching in a loop.
	_httpStaticVersionRateLimit = 60

	// Bound every phase of an HTTP request/connection so a slow or hostile
	// client (or a stalled network path) cannot hold a connection open
	// indefinitely and exhaust the router's file descriptors or goroutines.
	_httpReadHeaderTimeout = 5 * time.Second
	_httpReadTimeout       = 10 * time.Second
	_httpWriteTimeout      = 15 * time.Second
	_httpIdleTimeout       = 60 * time.Second

	// _powersyncTokenTTL bounds how long a leaked/observed PowerSync JWT stays
	// usable. Was 24h; narrows this to 1h — short enough to cap exposure, long
	// enough that PowerSyncService's normal refresh cadence (it re-fetches well
	// before expiry) never causes a mid-session drop. No revocation/quota on top
	// of this: single-host scale doesn't justify that machinery (YAGNI; see docs/config.md).
	_powersyncTokenTTL = time.Hour
	// _powersyncAnonymousSubject is the "sub" claim used when the caller sends
	// no installation id — either an older app build that predates the header,
	// or any other caller of this endpoint. Keeps the endpoint working exactly
	// as before for those callers instead of failing the request.
	_powersyncAnonymousSubject = "powersync-client"
	// _installIDHeaderMaxLen bounds the installation id accepted into the JWT
	// "sub" claim. It is not an authorization credential (no secret is
	// checked here, unlike the gRPC x-install-id/x-install-secret pair in
	// firebase_service.go) — only a correlation id an operator can use to
	// trace a specific token back to an installation — so it only needs
	// sanity bounds, not the same validation UpsertDevice applies.
	_installIDHeaderMaxLen = 128
)

type httpServerConfig struct {
	MetricsCredential string
	TrustedProxies    []netip.Prefix
	TokenRateLimit    int
	JWKSRateLimit     int
	SearchRateLimit   int
	// Where MOTIS is reached, and whether it is the configured planner. Both
	// come from main so the geocode proxy cannot disagree with the planner
	// about which backend is live.
	MotisBaseURL string
	MotisEnabled bool
	// The same monitor MaasServer consults, so /api/planner reports the backend
	// that is actually answering rather than a second opinion about it.
	plannerHealth    *plannerHealthMonitor
	MetricsRateLimit int
	// booking is the TDX deeplink proxy for the rail 訂購 handoff (ADR-0012).
	// Set in main; nil in tests and any env without a TDX client, where the
	// endpoint returns 503 and the app falls back to a plain booking site link.
	booking *BookingProxy
	// redis backs the GBFS station_status feed, which reads the same live
	// availability keys the app's bike screens do. Set in main; when nil the
	// GBFS routes are not mounted at all, so an env without Redis serves no
	// half-working feed.
	redis *redis.Client
	// GBFSRateLimit bounds GBFS polling per client. The feed is public and
	// unauthenticated, and station_status costs a full station scan.
	GBFSRateLimit int
	// GTFSRealtimeCredential gates the GTFS-RT endpoint (ADR-0019). Empty leaves
	// the route unmounted, which is what every environment that has not been
	// given a secret should serve.
	GTFSRealtimeCredential string
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
	gtfsRTCredential, err := GTFSRTCredentialFromEnv()
	if err != nil {
		return httpServerConfig{}, err
	}
	return httpServerConfig{
		MetricsCredential:      metricsCredential,
		TrustedProxies:         trustedProxies,
		GTFSRealtimeCredential: gtfsRTCredential,
		MotisBaseURL:           MotisBaseURLFromEnv(),
		// Read from the same env var the planner reads, so the geocode proxy
		// and the planner can never disagree about which backend is live.
		MotisEnabled: !MaasBackendFromEnv(),
	}, nil
}

func trustedProxiesFromEnv() ([]netip.Prefix, error) {
	raw := strings.TrimSpace(os.Getenv(_trustedProxiesEnv))
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
				return nil, _oops.With("_trusted_proxies_env", _trustedProxiesEnv).With("value", value).Errorf("contains invalid IP or CIDR")
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
			return nil, _oops.With("_trusted_proxies_env", _trustedProxiesEnv).With("value", value).Errorf("contains unsafe catch-all or unspecified proxy")
		}
		proxies = append(proxies, prefix)
	}
	return proxies, nil
}

type trackedHTTPHandler struct {
	handler  http.Handler
	mu       sync.Mutex
	active   int
	stopping bool
	done     chan struct{}
	doneOnce sync.Once
}

func newTrackedHTTPHandler(handler http.Handler) *trackedHTTPHandler {
	return &trackedHTTPHandler{handler: handler, done: make(chan struct{})}
}

func (h *trackedHTTPHandler) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	h.mu.Lock()
	if h.stopping {
		h.mu.Unlock()
		http.Error(writer, "server shutting down", http.StatusServiceUnavailable)
		return
	}
	h.active++
	h.mu.Unlock()
	defer func() {
		h.mu.Lock()
		h.active--
		if h.stopping && h.active == 0 {
			h.doneOnce.Do(func() { close(h.done) })
		}
		h.mu.Unlock()
	}()
	h.handler.ServeHTTP(writer, request)
}

func (h *trackedHTTPHandler) stopAndWait() {
	h.mu.Lock()
	h.stopping = true
	if h.active == 0 {
		h.doneOnce.Do(func() { close(h.done) })
	}
	done := h.done
	h.mu.Unlock()
	<-done
}

type preparedHTTPServer struct {
	server   *http.Server
	listener net.Listener
	handlers *trackedHTTPHandler
}

func prepareHTTPServer(
	db *pgxpool.Pool,
	live *LiveHub,
	config httpServerConfig,
	loadKey func() (*rsa.PrivateKey, error),
	listen func(string, string) (net.Listener, error),
) (preparedHTTPServer, error) {
	key, err := loadKey()
	if err != nil {
		return preparedHTTPServer{}, _oops.Wrapf(err, "prepare HTTP signing key")
	}
	zap.S().Infow("RS256 key ready", "component", "http")
	gin.SetMode(gin.ReleaseMode)
	handlers := newTrackedHTTPHandler(newHTTPRouter(db, live, key, config))
	server := &http.Server{
		Handler:           handlers,
		ReadHeaderTimeout: _httpReadHeaderTimeout,
		ReadTimeout:       _httpReadTimeout,
		WriteTimeout:      _httpWriteTimeout,
		IdleTimeout:       _httpIdleTimeout,
	}
	listener, err := listen("tcp", "0.0.0.0:8080")
	if err != nil {
		return preparedHTTPServer{}, _oops.Wrapf(err, "listen for HTTP")
	}
	return preparedHTTPServer{server: server, listener: listener, handlers: handlers}, nil
}

func newHTTPRouter(db *pgxpool.Pool, live *LiveHub, key *rsa.PrivateKey, config httpServerConfig) *gin.Engine {
	r := gin.New()
	trustedProxies := make([]string, len(config.TrustedProxies))
	for index, prefix := range config.TrustedProxies {
		trustedProxies[index] = prefix.String()
	}
	if err := r.SetTrustedProxies(trustedProxies); err != nil {
		panic(fmt.Sprintf("validated trusted proxy configuration rejected: %v", err))
	}
	r.Use(safeAccessLogger(), gin.Recovery())
	r.Use(sentrygin.New(sentrygin.Options{Repanic: true}))
	limiter := NewRateLimiter()
	tokenLimit := configuredLimit(config.TokenRateLimit, _httpTokenRateLimit)
	jwksLimit := configuredLimit(config.JWKSRateLimit, _httpJWKSRateLimit)
	searchLimit := configuredLimit(config.SearchRateLimit, _httpSearchRateLimit)
	metricsLimit := configuredLimit(config.MetricsRateLimit, _httpMetricsRateLimit)
	gbfsLimit := configuredLimit(config.GBFSRateLimit, _httpGBFSRateLimit)
	r.GET("/api/token/powersync",
		httpRateLimit(limiter, "GET /api/token/powersync", tokenLimit, time.Minute),
		handleToken(key))
	r.GET("/api/.well-known/jwks.json",
		httpRateLimit(limiter, "GET /api/.well-known/jwks.json", jwksLimit, time.Minute),
		handleJWKS(key))
	r.GET("/api/search",
		httpRateLimit(limiter, "GET /api/search", searchLimit, time.Second),
		HandleSearch(db))
	r.GET(StaticVersionPath,
		httpRateLimit(limiter, "GET "+StaticVersionPath, _httpStaticVersionRateLimit, time.Minute),
		HandleStaticVersion(db))
	// Mounted only when MOTIS is the configured planner: with MAAS_BACKEND=tdx
	// there is nothing behind this route, and the app's Google Places fallback
	// becomes its only source (ADR-0022).
	RegisterGeocodeRoutes(r, config.MotisBaseURL, config.MotisEnabled,
		httpRateLimit(limiter, "GET "+GeocodePath, _httpGeocodeRateLimit, time.Minute))
	// Always mounted, unlike the geocode proxy: an app that cannot tell which
	// planner is live has to guess which options it may offer, and guessing is
	// what this exists to remove.
	RegisterPlannerStatusRoutes(r, config.plannerHealth,
		httpRateLimit(limiter, "GET "+PlannerStatusPath, _httpPlannerStatusRateLimit, time.Minute))
	r.GET("/api/booking/deeplink",
		httpRateLimit(limiter, "GET /api/booking/deeplink", _httpBookingRateLimit, time.Minute),
		HandleBookingDeeplink(config.booking))
	// Mounted only with a Redis client: cancelling has to publish the session's
	// ending, and a cancel a watching app never hears about is half a cancel.
	if config.redis != nil {
		r.POST(TrackCancelPath,
			httpRateLimit(limiter, "POST "+TrackCancelPath, _httpTrackCancelRateLimit, time.Minute),
			HandleTrackCancel(trackCancelStoreFor(db), config.redis))
	}
	// GBFS is mounted only with a Redis client: station_status is the point of
	// the feed, and it cannot be answered without one.
	if config.redis != nil {
		RegisterGBFSRoutes(r, db, config.redis,
			httpRateLimit(limiter, "GET /gbfs", gbfsLimit, time.Minute))
	}
	// GTFS-RT is mounted only with both a Redis client and a credential: the
	// snapshot lives in Redis, and prod's HTTP port is public, so an ungated
	// route would publish a feed that was scoped as internal (ADR-0019).
	RegisterGTFSRTRoutes(r, config.redis, config.GTFSRealtimeCredential,
		httpRateLimit(limiter, "GET "+GTFSRTPath, _httpGTFSRTRateLimit, time.Minute))
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

func safeAccessLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		started := time.Now()
		c.Next()
		status := c.Writer.Status()
		// FullPath (the registered route pattern, e.g. "/bus/route/:subRouteUid")
		// keeps the router_http_requests_total label set bounded to the routes
		// actually registered in newHTTPRouter; the raw request path would let a
		// client mint unbounded label values by varying path parameters or
		// probing unregistered paths. An unmatched route (404, empty FullPath)
		// is aggregated under "unmatched" for the same reason.
		routePath := c.FullPath()
		if routePath == "" {
			routePath = "unmatched"
		}
		obs.RecordHTTPRequest(routePath, status)
		// EscapedPath, never RequestURI: the raw query can carry a bearer token
		// or another credential a client appended, and an access log is the one
		// place it would be persisted verbatim.
		zap.S().Infow("http request",
			"method", c.Request.Method,
			"path", c.Request.URL.EscapedPath(),
			"status", status,
			"latency", time.Since(started),
		)
	}
}

func httpRateLimit(limiter *RateLimiter, scope string, limit int, window time.Duration) gin.HandlerFunc {
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

const _metricsPrincipalContextKey = "metrics-principal"

func httpPrincipalRateLimit(limiter *RateLimiter, scope string, limit int, window time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		principal, ok := c.Get(_metricsPrincipalContextKey)
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
	credential := os.Getenv(_metricsCredentialEnv)
	if credential != strings.TrimSpace(credential) {
		return "", _oops.With("_metrics_credential_env", _metricsCredentialEnv).Errorf("must not contain leading or trailing whitespace")
	}
	if len(credential) < 32 {
		return "", _oops.With("_metrics_credential_env", _metricsCredentialEnv).Errorf("must be configured with at least 32 characters")
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
		provided := ParseBearerCredential(c.GetHeader("Authorization"))
		providedHash := sha256.Sum256([]byte(provided))
		if provided == "" || subtle.ConstantTimeCompare(providedHash[:], expectedHash[:]) != 1 {
			c.Header("WWW-Authenticate", "Bearer")
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		c.Set(_metricsPrincipalContextKey, principal)
		c.Next()
	}
}
func handleMetrics(live *LiveHub) gin.HandlerFunc {
	return func(c *gin.Context) {
		stats := live.stats()
		body := fmt.Sprintf(
			"router_live_streams %d\nrouter_live_channels %d\nrouter_live_evicted_subscribers_total %d\nrouter_goroutines %d\n%s",
			stats.ActiveStreams,
			stats.ActiveChannels,
			stats.EvictedSubscribers,
			runtime.NumGoroutine(),
			obs.MetricsText(),
		)
		c.Data(200, "text/plain; version=0.0.4; charset=utf-8", []byte(body))
	}
}

// handleToken issues a short-lived PowerSync sync JWT. The "sub" claim binds
// the token to the caller's installation id (X-Install-Id header, the same
// identity the app already carries for gRPC — see FirebaseCallOptions in the
// Flutter client) when present, purely so a token can be traced back to an
// installation after the fact; there is no secret check here and no
// revocation, so a stolen token is still usable until it expires
// (_powersyncTokenTTL) regardless of whose sub it carries.
func handleToken(key *rsa.PrivateKey) gin.HandlerFunc {
	return func(c *gin.Context) {
		now := time.Now()
		token, err := signRS256(key, map[string]any{
			"sub": tokenSubject(c.GetHeader(InstallIDMetadataKey)),
			"aud": "powersync",
			"iat": now.Unix(),
			"exp": now.Add(_powersyncTokenTTL).Unix(),
		})
		if err != nil {
			c.JSON(500, gin.H{"error": "sign failed"})
			return
		}
		c.JSON(200, gin.H{"token": token})
	}
}

// tokenSubject sanitizes the caller-supplied installation id into a "sub"
// claim, falling back to _powersyncAnonymousSubject for an empty, oversized, or
// otherwise unusable header instead of putting untrusted content straight
// into a signed token.
func tokenSubject(installID string) string {
	installID = strings.TrimSpace(installID)
	if installID == "" || len(installID) > _installIDHeaderMaxLen {
		return _powersyncAnonymousSubject
	}
	for _, r := range installID {
		if r < 0x20 || r == 0x7f {
			return _powersyncAnonymousSubject
		}
	}
	return installID
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
				zap.S().Infow("loaded persisted RSA key", "component", "http", "key_file", keyFile)
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
	if err := persistKeyAtomically(keyFile, data); err != nil {
		return nil, _oops.Wrapf(err, "persist RSA key")
	}
	zap.S().Infow("generated new RSA key", "component", "http", "key_file", keyFile)
	return key, nil
}

// persistKeyAtomically writes data to a temp file in keyFile's own directory,
// fsyncs it, restricts it to owner-only 0600, and renames it into place.
// Writing through a same-directory temp file plus rename means a concurrent
// reader (or a crash mid-write) never observes a partial key; Sync forces the
// bytes to durable storage before the rename makes them visible under
// keyFile, and every step's error is returned rather than swallowed so a
// failed persist regenerates loudly instead of silently invalidating every
// client's PowerSync token on the next restart.
func persistKeyAtomically(keyFile string, data []byte) error {
	dir := filepath.Dir(keyFile)
	tmp, err := os.CreateTemp(dir, filepath.Base(keyFile)+".tmp-*")
	if err != nil {
		return _oops.Wrapf(err, "create temp key file")
	}
	tmpName := tmp.Name()
	renamed := false
	defer func() {
		if !renamed {
			_ = os.Remove(tmpName)
		}
	}()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return _oops.Wrapf(err, "write temp key file")
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return _oops.Wrapf(err, "sync temp key file")
	}
	if err := tmp.Close(); err != nil {
		return _oops.Wrapf(err, "close temp key file")
	}
	if err := os.Chmod(tmpName, 0600); err != nil {
		return _oops.Wrapf(err, "chmod temp key file")
	}
	if err := os.Rename(tmpName, keyFile); err != nil {
		return _oops.Wrapf(err, "rename temp key file into place")
	}
	renamed = true
	return nil
}
