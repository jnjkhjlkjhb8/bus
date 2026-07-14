package shared

import (
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/go-redis/redis"
	"github.com/go-resty/resty/v2"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
	"golang.org/x/sync/singleflight"
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
	tokenHTTP     *http.Client
	store         TDXStore
	imsKey        func(name string) string
	sinceFallback func(name string) string
	tokenRefresh  singleflight.Group
	// tokenURL is the OAuth token endpoint. It defaults to tdxTokenURL and is a
	// field only so unit tests can point the client_credentials exchange at an
	// httptest server; production never overrides it.
	tokenURL string
}

// NewTDXClient builds a TDX client for the basic conditional-GET API: base URL,
// response compression negotiation, a 30s timeout, transport/429 retries, a
// per-request bearer token from Store, and a 401 handler that drops both token
// keys so the retry re-authenticates. TDX API docs: https://tdx.transportdata.tw/
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
		tokenHTTP:     &http.Client{Timeout: 30 * time.Second},
	}
	c.http = resty.New().
		SetBaseURL(base).
		SetHeader("Content-Type", "application/json").
		SetHeader("Accept-Encoding", "gzip").
		SetDoNotParseResponse(true).
		SetTimeout(30 * time.Second).
		SetRetryCount(5).
		SetRetryWaitTime(1 * time.Second).
		SetRetryMaxWaitTime(5 * time.Second).
		AddRetryCondition(c.retryOn).
		OnBeforeRequest(func(_ *resty.Client, req *resty.Request) error {
			token, err := c.Token(req.Context())
			if err != nil {
				return err
			}
			req.SetAuthToken(token)
			return nil
		})
	return c
}

// retryOn retries on any transport error or HTTP 429. A 401 additionally drops
// both the namespaced and legacy token keys so the retry re-authenticates rather
// than resending the rejected token.
func (c *TDXClient) retryOn(r *resty.Response, err error) bool {
	if err != nil {
		if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
			return false
		}
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
// it installs the shared bearer-token auth hook and a finite timeout, leaving
// retry conditions to the caller. This keeps the token exchange in one place
// while letting each family keep its own request shape.
func (c *TDXClient) NewAuthedClient(baseURL string) *resty.Client {
	return resty.New().
		SetBaseURL(baseURL).
		SetTimeout(30 * time.Second).
		OnBeforeRequest(func(_ *resty.Client, req *resty.Request) error {
			token, err := c.Token(req.Context())
			if err != nil {
				return err
			}
			req.SetAuthToken(token)
			return nil
		})
}

// Token returns a TDX OAuth bearer token, preferring the cached value in Redis
// (namespaced key, then legacy key). On a cache miss it does a client_credentials
// exchange using TDX_CLIENT_ID / TDX_CLIENT_SECRET and caches the token for 6
// hours. Concurrent cache misses share a single exchange. The cache is checked
// again inside the singleflight call so a waiter cannot start a redundant
// exchange after another caller has already populated it.
func (c *TDXClient) Token(ctx context.Context) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	if token, err := c.cachedToken(); err != nil || token != "" {
		return token, err
	}
	result := c.tokenRefresh.DoChan("refresh", func() (any, error) {
		if token, err := c.cachedToken(); err != nil || token != "" {
			return token, err
		}
		refreshCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		return c.exchangeToken(refreshCtx)
	})
	select {
	case <-ctx.Done():
		return "", ctx.Err()
	case res := <-result:
		if res.Err != nil {
			return "", res.Err
		}
		token, ok := res.Val.(string)
		if !ok || token == "" {
			return "", errors.New("tdx token exchange returned an empty token")
		}
		return token, nil
	}
}

func (c *TDXClient) cachedToken() (string, error) {
	token, err := c.store.Get(TDXTokenKey)
	if err != nil {
		return "", fmt.Errorf("read cached TDX token: %w", err)
	}
	if token != "" {
		return token, nil
	}
	token, err = c.store.Get(TDXTokenKeyLegacy)
	if err != nil {
		return "", fmt.Errorf("read legacy cached TDX token: %w", err)
	}
	return token, nil
}

func (c *TDXClient) exchangeToken(ctx context.Context) (string, error) {
	form := url.Values{
		"grant_type":    {"client_credentials"},
		"client_id":     {os.Getenv("TDX_CLIENT_ID")},
		"client_secret": {os.Getenv("TDX_CLIENT_SECRET")},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.tokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return "", fmt.Errorf("build TDX token request: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := c.tokenHTTP.Do(req)
	if err != nil {
		return "", fmt.Errorf("exchange TDX token: %w", err)
	}
	body, readErr := io.ReadAll(resp.Body)
	closeErr := resp.Body.Close()
	if readErr != nil || closeErr != nil {
		return "", errors.Join(readErr, closeErr)
	}
	if resp.StatusCode >= http.StatusBadRequest {
		return "", fmt.Errorf("exchange TDX token: status %d", resp.StatusCode)
	}
	var payload struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return "", fmt.Errorf("decode TDX token response: %w", err)
	}
	if payload.AccessToken == "" {
		return "", errors.New("TDX token response is missing access_token")
	}
	if err := c.store.Set(TDXTokenKey, payload.AccessToken, tdxTokenTTL); err != nil {
		return "", fmt.Errorf("cache TDX token: %w", err)
	}
	return payload.AccessToken, nil
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

// TDXFetch is one conditional response. Ack advances its Last-Modified marker;
// consumers call it only after the payload has decoded and its Redis pipeline
// has committed. Close always returns the response-body close error.
type TDXFetch struct {
	Decoder  *json.Decoder
	Modified bool
	Ack      func() error
	Close    func() error
}

type tdxResponseBody struct {
	io.Reader
	close func() error
}

func (b *tdxResponseBody) Close() error { return b.close() }

func decodedTDXBody(resp *resty.Response) (io.ReadCloser, error) {
	raw := resp.RawResponse.Body
	switch strings.ToLower(strings.TrimSpace(resp.Header().Get("Content-Encoding"))) {
	case "", "identity":
		return raw, nil
	case "gzip":
		reader, err := gzip.NewReader(raw)
		if err != nil {
			return nil, errors.Join(err, raw.Close())
		}
		return &tdxResponseBody{
			Reader: reader,
			close: func() error {
				return errors.Join(reader.Close(), raw.Close())
			},
		}, nil
	default:
		return nil, errors.Join(
			fmt.Errorf("unsupported TDX content encoding %q", resp.Header().Get("Content-Encoding")),
			raw.Close(),
		)
	}
}

func noopTDXFetch() *TDXFetch {
	return &TDXFetch{
		Ack:   func() error { return nil },
		Close: func() error { return nil },
	}
}

// Get is the streaming conditional GET. A successful response does not advance
// its marker until the returned fetch's Ack is called. A 304 returns a
// Modified=false fetch with safe no-op Ack and Close functions.
func (c *TDXClient) Get(ctx context.Context, url, name string) (*TDXFetch, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	resp, err := c.http.R().
		SetContext(ctx).
		SetHeader("If-Modified-Since", c.since(name)).
		Get(url)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode() == http.StatusNotModified {
		if cerr := resp.RawResponse.Body.Close(); cerr != nil {
			return nil, cerr
		}
		obs.Logf("[TDX] action=fetch event=not_modified name=%s", name)
		return noopTDXFetch(), nil
	}
	if resp.StatusCode() >= http.StatusBadRequest {
		statusErr := &TDXStatusError{Name: name, Status: resp.StatusCode()}
		return nil, errors.Join(statusErr, resp.RawResponse.Body.Close())
	}
	body, err := decodedTDXBody(resp)
	if err != nil {
		return nil, err
	}
	marker := resp.Header().Get("Last-Modified")
	return &TDXFetch{
		Decoder:  json.NewDecoder(body),
		Modified: true,
		Ack: func() error {
			if err := c.store.Set(c.imsKey(name), marker, 0); err != nil {
				return fmt.Errorf("ack TDX marker %s: %w", name, err)
			}
			return nil
		},
		Close: body.Close,
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
		statusErr := &TDXStatusError{Name: name, Status: resp.StatusCode()}
		return false, errors.Join(statusErr, resp.RawResponse.Body.Close())
	}
	responseBody, err := decodedTDXBody(resp)
	if err != nil {
		return false, err
	}
	body, rerr := io.ReadAll(responseBody)
	if cerr := responseBody.Close(); rerr != nil || cerr != nil {
		return false, errors.Join(rerr, cerr)
	}
	if commit != nil {
		if cerr := commit(body); cerr != nil {
			return true, cerr
		}
	}
	return true, c.cacheIMS(name, resp)
}

// cacheIMS stores the response's Last-Modified header under name's IMS key so the
// next request can send it as If-Modified-Since.
func (c *TDXClient) cacheIMS(name string, resp *resty.Response) error {
	if err := c.store.Set(c.imsKey(name), resp.Header().Get("Last-Modified"), 0); err != nil {
		return fmt.Errorf("cache TDX marker %s: %w", name, err)
	}
	return nil
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
