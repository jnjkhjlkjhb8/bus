package main

import (
	"bytes"
	"crypto"
	cryptorand "crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/getsentry/sentry-go"
	"github.com/gin-gonic/gin"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
)

func testKey(t *testing.T) *rsa.PrivateKey {
	t.Helper()
	key, err := rsa.GenerateKey(cryptorand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	return key
}

func verifyJWT(t *testing.T, token string, pub *rsa.PublicKey) map[string]any {
	t.Helper()
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("expected 3 segments, got %d", len(parts))
	}
	h := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		t.Fatal(err)
	}
	if err := rsa.VerifyPKCS1v15(pub, crypto.SHA256, h[:], sig); err != nil {
		t.Fatalf("signature invalid: %v", err)
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatal(err)
	}
	claims := map[string]any{}
	if err := json.Unmarshal(payload, &claims); err != nil {
		t.Fatal(err)
	}
	return claims
}

func TestSignRS256RoundTrip(t *testing.T) {
	key := testKey(t)
	token, err := signRS256(key, map[string]any{"sub": "x"})
	if err != nil {
		t.Fatal(err)
	}
	claims := verifyJWT(t, token, &key.PublicKey)
	if claims["sub"] != "x" {
		t.Fatalf("unexpected claims: %v", claims)
	}
}

func TestHandleTokenIssuesValidJWT(t *testing.T) {
	key := testKey(t)
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/api/token/powersync", handleToken(key))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/api/token/powersync", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("status %d", w.Code)
	}
	var body struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	claims := verifyJWT(t, body.Token, &key.PublicKey)
	if claims["aud"] != "powersync" || claims["sub"] != "powersync-client" {
		t.Fatalf("unexpected claims: %v", claims)
	}
	exp := int64(claims["exp"].(float64))
	iat := int64(claims["iat"].(float64))
	if exp <= iat || exp <= time.Now().Unix() {
		t.Fatalf("bad exp/iat: exp=%d iat=%d", exp, iat)
	}
}

func TestHandleJWKSPublishesSigningKey(t *testing.T) {
	key := testKey(t)
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/jwks", handleJWKS(key))
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/jwks", nil))
	if w.Code != http.StatusOK {
		t.Fatalf("status %d", w.Code)
	}
	var jwks struct {
		Keys []struct {
			Kty string `json:"kty"`
			Alg string `json:"alg"`
			Kid string `json:"kid"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &jwks); err != nil {
		t.Fatal(err)
	}
	if len(jwks.Keys) != 1 || jwks.Keys[0].Kty != "RSA" || jwks.Keys[0].Alg != "RS256" {
		t.Fatalf("unexpected jwks: %+v", jwks)
	}
	nb, err := base64.RawURLEncoding.DecodeString(jwks.Keys[0].N)
	if err != nil {
		t.Fatal(err)
	}
	eb, err := base64.RawURLEncoding.DecodeString(jwks.Keys[0].E)
	if err != nil {
		t.Fatal(err)
	}
	pub := &rsa.PublicKey{N: new(big.Int).SetBytes(nb), E: int(new(big.Int).SetBytes(eb).Int64())}
	token, err := signRS256(key, map[string]any{"sub": "x"})
	if err != nil {
		t.Fatal(err)
	}
	verifyJWT(t, token, pub)
}

// A silently regenerated key would invalidate every client's PowerSync token
// at once, so the persisted key must survive a restart byte-for-byte.
func TestLoadOrGenerateKeyPersistsAcrossRestarts(t *testing.T) {
	keyFile := t.TempDir() + "/powersync_key.pem"
	first, err := loadOrGenerateKeyAt(keyFile)
	if err != nil {
		t.Fatal(err)
	}
	second, err := loadOrGenerateKeyAt(keyFile)
	if err != nil {
		t.Fatal(err)
	}
	if first.N.Cmp(second.N) != 0 || first.D.Cmp(second.D) != 0 {
		t.Fatal("reloaded key differs from the persisted key")
	}
}

func TestLoadOrGenerateKeyRecoversFromCorruptFile(t *testing.T) {
	keyFile := t.TempDir() + "/powersync_key.pem"
	if err := os.WriteFile(keyFile, []byte("not a pem"), 0600); err != nil {
		t.Fatal(err)
	}
	key, err := loadOrGenerateKeyAt(keyFile)
	if err != nil || key == nil {
		t.Fatalf("key = %v, err = %v", key, err)
	}
	// The regenerated key must be persisted so the next restart reuses it.
	reloaded, err := loadOrGenerateKeyAt(keyFile)
	if err != nil {
		t.Fatal(err)
	}
	if key.N.Cmp(reloaded.N) != 0 {
		t.Fatal("regenerated key was not persisted for the next restart")
	}
}

func TestPrepareHTTPServerReturnsKeyAndListenErrorsSynchronously(t *testing.T) {
	config := httpServerConfig{MetricsCredential: strings.Repeat("m", 32)}
	keyErr := errors.New("key unavailable")
	listenCalled := false
	_, err := prepareHTTPServer(nil, nil, config,
		func() (*rsa.PrivateKey, error) { return nil, keyErr },
		func(string, string) (net.Listener, error) {
			listenCalled = true
			return nil, nil
		})
	if !errors.Is(err, keyErr) {
		t.Fatalf("key preparation error = %v, want wrapped %v", err, keyErr)
	}
	if listenCalled {
		t.Fatal("HTTP listener was opened after key preparation failed")
	}

	listenErr := errors.New("address in use")
	_, err = prepareHTTPServer(nil, nil, config,
		func() (*rsa.PrivateKey, error) { return testKey(t), nil },
		func(network, address string) (net.Listener, error) {
			if network != "tcp" || address != "0.0.0.0:8080" {
				t.Fatalf("listen target = %s %s", network, address)
			}
			return nil, listenErr
		})
	if !errors.Is(err, listenErr) {
		t.Fatalf("HTTP listen error = %v, want wrapped %v", err, listenErr)
	}
}

func TestTrackedHTTPHandlerWaitsForActiveHandler(t *testing.T) {
	started := make(chan struct{})
	release := make(chan struct{})
	handlerDone := make(chan struct{})
	tracked := newTrackedHTTPHandler(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		close(started)
		<-release
		close(handlerDone)
	}))
	go tracked.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/blocked", nil))
	<-started
	waitDone := make(chan struct{})
	go func() {
		tracked.stopAndWait()
		close(waitDone)
	}()
	select {
	case <-waitDone:
		t.Fatal("handler tracker returned while an active handler was blocked")
	default:
	}
	close(release)
	select {
	case <-handlerDone:
	case <-time.After(time.Second):
		t.Fatal("blocked HTTP handler did not finish")
	}
	select {
	case <-waitDone:
	case <-time.After(time.Second):
		t.Fatal("handler tracker did not return after handler completion")
	}
}

func TestHandleMetricsWritesLiveHubCounters(t *testing.T) {
	gin.SetMode(gin.TestMode)
	hub := newLiveHub(newHubSource(), 2)
	r := gin.New()
	r.GET("/metrics", handleMetrics(hub))

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/metrics", nil))

	if w.Code != http.StatusOK {
		t.Fatalf("status %d", w.Code)
	}
	body := w.Body.String()
	for _, metric := range []string{
		"router_live_streams",
		"router_live_channels",
		"router_live_evicted_subscribers_total",
		"router_goroutines",
	} {
		if !strings.Contains(body, metric) {
			t.Fatalf("missing metric %q in %q", metric, body)
		}
	}
}

func TestHTTPRoutesUseIndependentRateBuckets(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := newHTTPRouter(nil, newLiveHub(newHubSource(), 2), testKey(t), httpServerConfig{MetricsCredential: strings.Repeat("m", 32)})

	for requestNumber := 1; requestNumber <= httpTokenRateLimit+1; requestNumber++ {
		response := httptest.NewRecorder()
		request := httptest.NewRequest(http.MethodGet, "/api/token/powersync", nil)
		router.ServeHTTP(response, request)
		want := http.StatusOK
		if requestNumber > httpTokenRateLimit {
			want = http.StatusTooManyRequests
		}
		if response.Code != want {
			t.Fatalf("token request %d status = %d, want %d", requestNumber, response.Code, want)
		}
	}

	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/.well-known/jwks.json", nil))
	if response.Code != http.StatusOK {
		t.Fatalf("JWKS route consumed token-route quota: status=%d", response.Code)
	}
}

func TestMetricsRequiresConfiguredCredential(t *testing.T) {
	t.Setenv(metricsCredentialEnv, "")
	if _, err := metricsCredentialFromEnv(); err == nil {
		t.Fatal("empty metrics credential was accepted")
	}
	t.Setenv(metricsCredentialEnv, "too-short")
	if _, err := metricsCredentialFromEnv(); err == nil {
		t.Fatal("short metrics credential was accepted")
	}

	credential := strings.Repeat("s", 32)
	t.Setenv(metricsCredentialEnv, credential)
	loaded, err := metricsCredentialFromEnv()
	if err != nil || loaded != credential {
		t.Fatalf("metricsCredentialFromEnv() = (%q, %v)", loaded, err)
	}

	gin.SetMode(gin.TestMode)
	router := newHTTPRouter(nil, newLiveHub(newHubSource(), 2), testKey(t), httpServerConfig{MetricsCredential: loaded})
	for _, test := range []struct {
		name          string
		authorization string
		want          int
	}{
		{name: "missing", want: http.StatusUnauthorized},
		{name: "wrong", authorization: "Bearer " + strings.Repeat("x", 32), want: http.StatusUnauthorized},
		{name: "valid", authorization: "Bearer " + credential, want: http.StatusOK},
	} {
		t.Run(test.name, func(t *testing.T) {
			response := httptest.NewRecorder()
			request := httptest.NewRequest(http.MethodGet, "/metrics?token="+credential, nil)
			if test.authorization != "" {
				request.Header.Set("Authorization", test.authorization)
			}
			router.ServeHTTP(response, request)
			if response.Code != test.want {
				t.Fatalf("status = %d, want %d; body=%q", response.Code, test.want, response.Body.String())
			}
			if test.want != http.StatusOK && strings.Contains(response.Body.String(), "router_goroutines") {
				t.Fatal("unauthorized response disclosed metrics")
			}
		})
	}
}

func TestHTTPServerConfigFromEnvValidatesBeforeStartup(t *testing.T) {
	t.Setenv(metricsCredentialEnv, strings.Repeat("s", 32))
	t.Setenv(trustedProxiesEnv, "10.0.0.0/8, 192.0.2.10, 198.51.100.27/24")

	config, err := httpServerConfigFromEnv()
	if err != nil {
		t.Fatal(err)
	}
	if config.MetricsCredential != strings.Repeat("s", 32) {
		t.Fatalf("metrics credential = %q", config.MetricsCredential)
	}
	want := []netip.Prefix{
		netip.MustParsePrefix("10.0.0.0/8"),
		netip.MustParsePrefix("192.0.2.10/32"),
		netip.MustParsePrefix("198.51.100.0/24"),
	}
	if len(config.TrustedProxies) != len(want) {
		t.Fatalf("trusted proxies = %v, want %v", config.TrustedProxies, want)
	}
	for i := range want {
		if config.TrustedProxies[i] != want[i] {
			t.Fatalf("trusted proxy %d = %v, want %v", i, config.TrustedProxies[i], want[i])
		}
	}

	t.Setenv(metricsCredentialEnv, "short")
	if _, err := httpServerConfigFromEnv(); err == nil {
		t.Fatal("short metrics token was accepted")
	}
	t.Setenv(metricsCredentialEnv, strings.Repeat("s", 32))
	t.Setenv(trustedProxiesEnv, "not-an-ip")
	if _, err := httpServerConfigFromEnv(); err == nil {
		t.Fatal("invalid trusted proxy was accepted")
	}

	for _, unsafe := range []string{
		"0.0.0.0/0", "::/0", "0.0.0.0", "::",
		"::ffff:0:0/96", "0.1.2.3/8",
	} {
		t.Run("reject unsafe proxy "+unsafe, func(t *testing.T) {
			t.Setenv(trustedProxiesEnv, unsafe)
			if _, err := httpServerConfigFromEnv(); err == nil {
				t.Fatalf("unsafe trusted proxy %q was accepted", unsafe)
			}
		})
	}
}

func TestDirectHTTPClientCannotRotateRateBucketWithForwardedFor(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := newHTTPRouter(nil, newLiveHub(newHubSource(), 2), testKey(t), httpServerConfig{
		MetricsCredential: strings.Repeat("m", 32),
		TokenRateLimit:    1,
	})
	for requestNumber, forwarded := range []string{"198.51.100.1", "198.51.100.2"} {
		response := httptest.NewRecorder()
		request := httptest.NewRequest(http.MethodGet, "/api/token/powersync", nil)
		request.RemoteAddr = "192.0.2.44:4321"
		request.Header.Set("X-Forwarded-For", forwarded)
		router.ServeHTTP(response, request)
		want := http.StatusOK
		if requestNumber == 1 {
			want = http.StatusTooManyRequests
		}
		if response.Code != want {
			t.Fatalf("request %d rotating X-Forwarded-For status = %d, want %d", requestNumber+1, response.Code, want)
		}
	}
}

func TestHTTPRateLimitUsesSocketPeerUnlessProxyIsTrusted(t *testing.T) {
	gin.SetMode(gin.TestMode)
	credential := strings.Repeat("m", 32)
	testCases := []struct {
		name            string
		trustedProxies  []netip.Prefix
		firstForwarded  string
		secondForwarded string
		wantSecond      int
	}{
		{name: "untrusted proxy header ignored", firstForwarded: "198.51.100.1", secondForwarded: "198.51.100.2", wantSecond: http.StatusTooManyRequests},
		{name: "trusted proxy separates clients", trustedProxies: []netip.Prefix{netip.MustParsePrefix("192.0.2.10/32")}, firstForwarded: "198.51.100.1", secondForwarded: "198.51.100.2", wantSecond: http.StatusOK},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			router := newHTTPRouter(nil, newLiveHub(newHubSource(), 2), testKey(t), httpServerConfig{
				MetricsCredential: credential,
				TrustedProxies:    tc.trustedProxies,
				TokenRateLimit:    1,
			})
			request := func(forwarded string) *httptest.ResponseRecorder {
				response := httptest.NewRecorder()
				req := httptest.NewRequest(http.MethodGet, "/api/token/powersync", nil)
				req.RemoteAddr = "192.0.2.10:4321"
				req.Header.Set("X-Forwarded-For", forwarded)
				router.ServeHTTP(response, req)
				return response
			}
			if got := request(tc.firstForwarded).Code; got != http.StatusOK {
				t.Fatalf("first status = %d", got)
			}
			if got := request(tc.secondForwarded).Code; got != tc.wantSecond {
				t.Fatalf("second status = %d, want %d", got, tc.wantSecond)
			}
		})
	}
}

func TestMetricsAuthenticationPrecedesPrincipalRateLimit(t *testing.T) {
	gin.SetMode(gin.TestMode)
	credential := strings.Repeat("m", 32)
	router := newHTTPRouter(nil, newLiveHub(newHubSource(), 2), testKey(t), httpServerConfig{
		MetricsCredential: credential,
		MetricsRateLimit:  1,
	})

	for range 3 {
		response := httptest.NewRecorder()
		request := httptest.NewRequest(http.MethodGet, "/metrics", nil)
		request.Header.Set("Authorization", "Bearer wrong")
		router.ServeHTTP(response, request)
		if response.Code != http.StatusUnauthorized {
			t.Fatalf("unauthorized status = %d", response.Code)
		}
	}

	request := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	request.Header.Set("Authorization", "bEaReR\t"+credential)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("authorized status after failures = %d", response.Code)
	}
	response = httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusTooManyRequests {
		t.Fatalf("second authorized status = %d, want 429", response.Code)
	}
}

func TestMetricsBearerParsingAndSecurityHeaders(t *testing.T) {
	gin.SetMode(gin.TestMode)
	credential := strings.Repeat("m", 32)
	for _, tc := range []struct {
		name   string
		header string
		want   int
	}{
		{name: "case insensitive with spaces", header: "bEaReR   " + credential, want: http.StatusOK},
		{name: "tab separator", header: "Bearer\t" + credential, want: http.StatusOK},
		{name: "empty", header: "Bearer ", want: http.StatusUnauthorized},
		{name: "extra token", header: "Bearer " + credential + " extra", want: http.StatusUnauthorized},
		{name: "leading whitespace", header: " Bearer " + credential, want: http.StatusUnauthorized},
		{name: "trailing whitespace", header: "Bearer " + credential + " ", want: http.StatusUnauthorized},
		{name: "query credential rejected", header: "", want: http.StatusUnauthorized},
	} {
		t.Run(tc.name, func(t *testing.T) {
			router := newHTTPRouter(nil, newLiveHub(newHubSource(), 2), testKey(t), httpServerConfig{MetricsCredential: credential})
			response := httptest.NewRecorder()
			request := httptest.NewRequest(http.MethodGet, "/metrics?token="+credential, nil)
			if tc.header != "" {
				request.Header.Set("Authorization", tc.header)
			}
			router.ServeHTTP(response, request)
			if response.Code != tc.want {
				t.Fatalf("status = %d, want %d", response.Code, tc.want)
			}
			if got := response.Header().Get("Cache-Control"); got != "no-store" {
				t.Fatalf("Cache-Control = %q", got)
			}
			if tc.want == http.StatusUnauthorized && response.Header().Get("WWW-Authenticate") != "Bearer" {
				t.Fatalf("WWW-Authenticate = %q", response.Header().Get("WWW-Authenticate"))
			}
		})
	}
}

func TestSafeAccessLoggerNeverLogsRawQuery(t *testing.T) {
	gin.SetMode(gin.TestMode)
	var output bytes.Buffer
	router := gin.New()
	router.Use(safeAccessLogger(&output))
	router.GET("/probe", func(c *gin.Context) { c.Status(http.StatusNoContent) })
	secret := "credential-that-must-not-be-logged"
	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/probe?token="+secret, nil))
	if strings.Contains(output.String(), secret) || strings.Contains(output.String(), "token=") {
		t.Fatalf("safe logger exposed query: %q", output.String())
	}
	for _, want := range []string{"GET", "/probe", "204"} {
		if !strings.Contains(output.String(), want) {
			t.Fatalf("safe logger output %q missing %q", output.String(), want)
		}
	}
}

func TestProductionSentryMiddlewareScrubsMetricsQueryFromEventsAndTransactions(t *testing.T) {
	gin.SetMode(gin.TestMode)
	previousClient := sentry.CurrentHub().Client()
	t.Setenv("SENTRY_DSN", "https://key@example.com/1")
	t.Setenv("SENTRY_TRACES_SAMPLE_RATE", "1")
	flush := obs.Init("router-test")
	defer func() {
		flush()
		sentry.CurrentHub().BindClient(previousClient)
	}()

	options := sentry.CurrentHub().Client().Options()
	transport := &sentry.MockTransport{}
	options.Transport = transport
	client, err := sentry.NewClient(options)
	if err != nil {
		t.Fatal(err)
	}
	sentry.CurrentHub().BindClient(client)

	credential := strings.Repeat("m", 32)
	router := newHTTPRouter(nil, nil, testKey(t), httpServerConfig{MetricsCredential: credential})
	secret := "query-secret-must-never-reach-sentry"
	request := httptest.NewRequest(http.MethodGet, "/metrics?token="+secret, nil)
	request.Header.Set("Authorization", "Bearer "+credential)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusInternalServerError {
		t.Fatalf("panic probe status = %d, want 500", response.Code)
	}

	var sawError, sawTransaction bool
	for _, event := range transport.Events() {
		serialized, err := json.Marshal(event)
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(string(serialized), secret) {
			t.Fatalf("Sentry payload exposed query credential: %s", serialized)
		}
		if event.Type == "transaction" {
			sawTransaction = true
		} else {
			sawError = true
		}
		if event.Request != nil {
			if event.Request.Method != http.MethodGet || !strings.HasSuffix(event.Request.URL, "/metrics") {
				t.Fatalf("request path/method not preserved: %+v", event.Request)
			}
			if event.Request.QueryString != "" {
				t.Fatalf("Sentry query string = %q", event.Request.QueryString)
			}
		}
	}
	if !sawError || !sawTransaction {
		t.Fatalf("captured event types: error=%v transaction=%v events=%d", sawError, sawTransaction, len(transport.Events()))
	}
}
