package main

import (
	"crypto"
	cryptorand "crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
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
		"router_live_dropped_frames_total",
		"router_goroutines",
	} {
		if !strings.Contains(body, metric) {
			t.Fatalf("missing metric %q in %q", metric, body)
		}
	}
}
