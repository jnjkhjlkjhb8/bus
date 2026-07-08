package shared

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
)

// This file is the single TDX HTTP client shared by both binaries. It owns the
// OAuth token refresh, the conditional-GET (If-Modified-Since) + 304 rule, the
// 4xx/429/401-retry handling, and the auth'd resty client construction. Before
// it, functions and router each carried their own callApi/getToken copies that
// had drifted: the router's had no 4xx guard (a 500 cached a bad Last-Modified
// marker and decoded an error body) and only knew the legacy token key. Both
// call patterns are served here, so neither binary constructs a TDX client or
// token exchange inline anymore.

// TDX endpoints and token lifetime.
const (
	tdxBasicBaseURL = "https://tdx.transportdata.tw/api/basic"
	tdxTokenURL     = "https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token"
	tdxTokenTTL     = 6 * time.Hour
)

// TDXStore is the small Redis surface the TDX client needs: the auth-token cache
// (read/write/delete) and the If-Modified-Since markers (read/write). It is an
// interface so unit tests can substitute an in-memory fake for the token-refresh,
// 304, and 401 re-auth paths without a live Redis. *redis.Client satisfies it
// through RedisTDXStore. Get returns ("", nil) — not an error — for a missing
// key, matching how the client treats a cold cache.
type TDXStore interface {
	Get(key string) (string, error)
	Set(key, value string, ttl time.Duration) error
	Del(keys ...string) error
}

// RedisTDXStore adapts *redis.Client to TDXStore, translating a missing key
// (redis.Nil) into an empty value so the client's cold-cache handling stays in
// one place.
type RedisTDXStore struct {
	RC *redis.Client
}

// Get returns the cached value, or "" when the key is absent.
func (s RedisTDXStore) Get(key string) (string, error) {
	v, err := s.RC.Get(key).Result()
	if err == redis.Nil {
		return "", nil
	}
	return v, err
}

// Set writes value under key with the given TTL (0 = no expiry).
func (s RedisTDXStore) Set(key, value string, ttl time.Duration) error {
	return s.RC.Set(key, value, ttl).Err()
}

// Del removes the given keys.
func (s RedisTDXStore) Del(keys ...string) error {
	return s.RC.Del(keys...).Err()
}

// TDXConfig configures a TDXClient. Store is required. IMSKey maps a fetch name
// to its If-Modified-Since cache key; the two binaries namespace it differently
// (raw vs legacy), so it is injected. SinceFallback supplies an IMS value when
// the cache is cold and returns "" for none — it may be nil. BaseURL overrides
// the TDX basic API base (used by the MaaS family).
type TDXConfig struct {
	Store         TDXStore
	IMSKey        func(name string) string
	SinceFallback func(name string) string
	BaseURL       string
}

// TDXClient performs authenticated TDX requests. The zero value is not usable;
// construct one with NewTDXClient.
type TDXClient struct {
	http          *resty.Client
	store         TDXStore
	imsKey        func(name string) string
	sinceFallback func(name string) string
	// tokenURL is the OAuth token endpoint. It defaults to tdxTokenURL and is a
	// field only so unit tests can point the client_credentials exchange at an
	// httptest server; production never overrides it.
	tokenURL string
}

// NewTDXClient builds a TDX client for the basic conditional-GET API: base URL,
// Brotli/gzip decoding left to the caller (responses are not parsed), a 30s
// timeout, transport/429 retries, a per-request bearer token from Store, and a
// 401 handler that drops both token keys so the retry re-authenticates. TDX API
// docs: https://tdx.transportdata.tw/
func NewTDXClient(cfg TDXConfig) *TDXClient {
	base := cfg.BaseURL
	if base == "" {
		base = tdxBasicBaseURL
	}
	c := &TDXClient{
		store:         cfg.Store,
		imsKey:        cfg.IMSKey,
		sinceFallback: cfg.SinceFallback,
		tokenURL:      tdxTokenURL,
	}
	c.http = resty.New().
		SetBaseURL(base).
		SetHeader("Content-Type", "application/json").
		SetHeader("Content-Encoding", "br,gzip").
		SetDoNotParseResponse(true).
		SetTimeout(30 * time.Second).
		SetRetryCount(5).
		SetRetryWaitTime(1 * time.Second).
		SetRetryMaxWaitTime(5 * time.Second).
		AddRetryCondition(c.retryOn).
		OnBeforeRequest(func(_ *resty.Client, req *resty.Request) error {
			req.SetAuthToken(c.Token())
			return nil
		})
	return c
}

// retryOn retries on any transport error or HTTP 429. A 401 additionally drops
// both the namespaced and legacy token keys so the retry re-authenticates rather
// than resending the rejected token.
func (c *TDXClient) retryOn(r *resty.Response, err error) bool {
	if err != nil {
		return true
	}
	if r.StatusCode() == http.StatusUnauthorized {
		if derr := c.store.Del(TDXTokenKey, TDXTokenKeyLegacy); derr != nil {
			obs.Logf("[TDX] action=token event=invalidate_error error=%v", derr)
		}
		return true
	}
	return r.StatusCode() == http.StatusTooManyRequests
}

// NewAuthedClient builds a resty client for a TDX API family with a different
// base URL and retry policy than the basic conditional-GET client (e.g. MaaS):
// it installs only the shared bearer-token auth hook, leaving base URL, timeouts,
// and retry conditions to the caller. This keeps the token exchange in one place
// while letting each family keep its own request shape.
func (c *TDXClient) NewAuthedClient(baseURL string) *resty.Client {
	return resty.New().
		SetBaseURL(baseURL).
		OnBeforeRequest(func(_ *resty.Client, req *resty.Request) error {
			req.SetAuthToken(c.Token())
			return nil
		})
}

// Token returns a TDX OAuth bearer token, preferring the cached value in Redis
// (namespaced key, then legacy key). On a cache miss it does a client_credentials
// exchange using TDX_CLIENT_ID / TDX_CLIENT_SECRET and caches the token for 6
// hours. Any failure is logged and returns "" — the caller then sends an
// unauthenticated request that TDX rejects with 401, which triggers a token
// refresh on retry. Token endpoint: tdxTokenURL.
func (c *TDXClient) Token() string {
	if v, err := c.store.Get(TDXTokenKey); err == nil && v != "" {
		return v
	}
	if v, err := c.store.Get(TDXTokenKeyLegacy); err == nil && v != "" {
		return v
	}
	resp, err := resty.New().R().
		SetHeader("content-type", "application/x-www-form-urlencoded").
		SetFormData(map[string]string{
			"grant_type":    "client_credentials",
			"client_id":     os.Getenv("TDX_CLIENT_ID"),
			"client_secret": os.Getenv("TDX_CLIENT_SECRET"),
		}).
		Post(c.tokenURL)
	if err != nil {
		obs.Logf("[TDX] action=token event=fetch_error error=%v", err)
		return ""
	}
	var mp map[string]any
	if err := json.Unmarshal(resp.Body(), &mp); err != nil {
		obs.Logf("[TDX] action=token event=parse_error error=%v", err)
		return ""
	}
	token, ok := mp["access_token"].(string)
	if !ok || token == "" {
		obs.Logf("[TDX] action=token event=missing_access_token")
		return ""
	}
	if err := c.store.Set(TDXTokenKey, token, tdxTokenTTL); err != nil {
		obs.Logf("[TDX] action=token event=cache_error error=%v", err)
	}
	return token
}

// since resolves the If-Modified-Since value for name: the cached marker, or the
// SinceFallback (a DB-derived timestamp) when the cache is cold. A nil fallback
// or an empty cache with no fallback yields "" (fetch everything).
func (c *TDXClient) since(name string) string {
	v, _ := c.store.Get(c.imsKey(name))
	if v == "" && c.sinceFallback != nil {
		v = c.sinceFallback(name)
	}
	return v
}

// Get is the streaming conditional GET: it issues an If-Modified-Since request
// for name's cached marker and, on fresh data (2xx), caches the new Last-Modified
// and returns a streaming JSON decoder over the response body. modified=false
// with a nil error is a 304 Not-Modified (cached data still valid); a 4xx/5xx is
// returned as an error WITHOUT advancing the marker or decoding the body, so a
// server error never caches a bad marker. close closes the response body and
// must be called; it is nil when there is nothing to close.
func (c *TDXClient) Get(url, name string) (dec *json.Decoder, modified bool, close func(), err error) {
	resp, err := c.http.R().
		SetHeader("If-Modified-Since", c.since(name)).
		Get(url)
	if err != nil {
		return nil, false, nil, err
	}
	if resp.StatusCode() == http.StatusNotModified {
		if cerr := resp.RawResponse.Body.Close(); cerr != nil {
			return nil, false, nil, cerr
		}
		obs.Logf("[TDX] action=fetch event=not_modified name=%s", name)
		return nil, false, nil, nil
	}
	if resp.StatusCode() >= http.StatusBadRequest {
		_ = resp.RawResponse.Body.Close()
		return nil, false, nil, &TDXStatusError{Name: name, Status: resp.StatusCode()}
	}
	c.cacheIMS(name, resp)
	return json.NewDecoder(resp.RawResponse.Body), true, func() {
		if cerr := resp.RawResponse.Body.Close(); cerr != nil {
			obs.Logf("[TDX] action=fetch event=close_error name=%s error=%v", name, cerr)
		}
	}, nil
}

// GetInto is the buffered conditional GET for callers that must durably handle
// the whole body before the If-Modified-Since marker advances (the raw_tdx
// landing). On fresh data it reads the entire body, calls commit, and caches the
// new Last-Modified only if commit succeeds — so a failed commit refetches next
// run instead of being masked by a later 304. modified reports whether fresh data
// was present; a commit error is returned verbatim (its own error identity is
// preserved for the caller's errors.Is checks) and leaves the marker unadvanced.
func (c *TDXClient) GetInto(url, name string, commit func(body []byte) error) (modified bool, err error) {
	resp, err := c.http.R().
		SetHeader("If-Modified-Since", c.since(name)).
		Get(url)
	if err != nil {
		return false, err
	}
	if resp.StatusCode() == http.StatusNotModified {
		if cerr := resp.RawResponse.Body.Close(); cerr != nil {
			return false, cerr
		}
		obs.Logf("[TDX] action=fetch event=not_modified name=%s", name)
		return false, nil
	}
	if resp.StatusCode() >= http.StatusBadRequest {
		_ = resp.RawResponse.Body.Close()
		return false, &TDXStatusError{Name: name, Status: resp.StatusCode()}
	}
	body, rerr := io.ReadAll(resp.RawResponse.Body)
	_ = resp.RawResponse.Body.Close()
	if rerr != nil {
		return false, rerr
	}
	if commit != nil {
		if cerr := commit(body); cerr != nil {
			return true, cerr
		}
	}
	c.cacheIMS(name, resp)
	return true, nil
}

// cacheIMS stores the response's Last-Modified header under name's IMS key so the
// next request can send it as If-Modified-Since.
func (c *TDXClient) cacheIMS(name string, resp *resty.Response) {
	if err := c.store.Set(c.imsKey(name), resp.Header().Get("Last-Modified"), 0); err != nil {
		obs.Logf("[TDX] action=fetch event=ims_cache_error name=%s error=%v", name, err)
	}
}

// TDXStatusError reports a non-success TDX HTTP status (>=400). It is returned by
// Get/GetInto so callers can distinguish an upstream error from a decode error.
type TDXStatusError struct {
	Name   string
	Status int
}

func (e *TDXStatusError) Error() string {
	return fmt.Sprintf("tdx %s: status %d", e.Name, e.Status)
}
