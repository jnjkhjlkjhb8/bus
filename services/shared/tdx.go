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
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/obs"
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
	if errors.Is(err, redis.Nil) {
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
	maxRetries    int
	retryWait     time.Duration
	retryMaxWait  time.Duration
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
		maxRetries:    5,
		retryWait:     time.Second,
		retryMaxWait:  5 * time.Second,
	}
	c.http = resty.New().
		SetBaseURL(base).
		SetHeader("Content-Type", "application/json").
		SetHeader("Accept-Encoding", "gzip").
		SetDoNotParseResponse(true).
		SetTimeout(30 * time.Second).
		OnBeforeRequest(func(_ *resty.Client, req *resty.Request) error {
			token, err := c.Token(req.Context())
			if err != nil {
				return &TDXAuthError{Err: err}
			}
			req.SetAuthToken(token)
			return nil
		})
	return c
}

// TDXAuthError marks failures from the shared token/cache hook. Callers with
// their own retry policy (such as MaaS) must not retry these non-transport
// failures.
type TDXAuthError struct {
	Err error
}

func (e *TDXAuthError) Error() string { return e.Err.Error() }
func (e *TDXAuthError) Unwrap() error { return e.Err }

// IsTDXAuthError reports whether err came from the shared auth hook.
func IsTDXAuthError(err error) bool {
	var authErr *TDXAuthError
	return errors.As(err, &authErr)
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
				return &TDXAuthError{Err: err}
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
func (c *TDXClient) since(name string) (string, error) {
	v, err := c.store.Get(c.imsKey(name))
	if err != nil {
		return "", fmt.Errorf("read TDX marker %s: %w", name, err)
	}
	if v == "" && c.sinceFallback != nil {
		v = c.sinceFallback(name)
	}
	return v, nil
}

func drainAndCloseResponse(resp *resty.Response) error {
	if resp == nil || resp.RawResponse == nil || resp.RawResponse.Body == nil {
		return nil
	}
	_, readErr := io.Copy(io.Discard, resp.RawResponse.Body)
	return errors.Join(readErr, resp.RawResponse.Body.Close())
}

func (c *TDXClient) retryDecision(resp *resty.Response, requestErr error) (bool, error) {
	if requestErr != nil {
		if errors.Is(requestErr, context.Canceled) || errors.Is(requestErr, context.DeadlineExceeded) || IsTDXAuthError(requestErr) {
			return false, nil
		}
		return true, nil
	}
	if resp == nil {
		return false, nil
	}
	switch resp.StatusCode() {
	case http.StatusUnauthorized:
		if err := c.store.Del(TDXTokenKey, TDXTokenKeyLegacy); err != nil {
			return false, fmt.Errorf("invalidate rejected TDX token: %w", err)
		}
		return true, nil
	case http.StatusTooManyRequests:
		return true, nil
	default:
		return false, nil
	}
}

func (c *TDXClient) retryDelay(attempt int) time.Duration {
	delay := c.retryWait
	for i := 0; i < attempt && delay < c.retryMaxWait; i++ {
		if delay > c.retryMaxWait/2 {
			return c.retryMaxWait
		}
		delay *= 2
	}
	if delay > c.retryMaxWait {
		return c.retryMaxWait
	}
	return delay
}

// get performs bounded retries while retaining ownership of every streaming
// response body. Intermediate bodies are drained and closed before another
// attempt; final bodies remain owned by Get/GetInto.
func (c *TDXClient) get(ctx context.Context, url, marker string) (*resty.Response, error) {
	for attempt := 0; ; attempt++ {
		resp, requestErr := c.http.R().
			SetContext(ctx).
			SetHeader("If-Modified-Since", marker).
			Get(url)
		retry, decisionErr := c.retryDecision(resp, requestErr)
		if decisionErr != nil {
			return nil, errors.Join(decisionErr, drainAndCloseResponse(resp))
		}
		if !retry {
			if requestErr != nil {
				return nil, errors.Join(requestErr, drainAndCloseResponse(resp))
			}
			return resp, nil
		}
		if attempt >= c.maxRetries {
			if requestErr != nil {
				return nil, errors.Join(requestErr, drainAndCloseResponse(resp))
			}
			return resp, nil
		}
		if err := drainAndCloseResponse(resp); err != nil {
			return nil, err
		}
		delay := c.retryDelay(attempt)
		if delay <= 0 {
			continue
		}
		timer := time.NewTimer(delay)
		select {
		case <-timer.C:
		case <-ctx.Done():
			if !timer.Stop() {
				<-timer.C
			}
			return nil, ctx.Err()
		}
	}
}

// TDXFetch is one conditional response. Ack advances its Last-Modified marker;
// consumers call it only after the payload has decoded and its Redis pipeline
// has committed. Invalidate clears a stale conditional marker so the next call
// is forced to fetch a full frame. Close drains the decoded stream before
// closing it, surfacing gzip checksum/truncation failures even when a consumer
// stopped decoding early.
type TDXFetch struct {
	Decoder    *json.Decoder
	Modified   bool
	Ack        func() error
	Close      func() error
	Invalidate func() error
}

type tdxResponseBody struct {
	io.Reader
	close func() error
}

func (b *tdxResponseBody) Close() error {
	_, readErr := io.Copy(io.Discard, b.Reader)
	return errors.Join(readErr, b.close())
}

func decodedTDXBody(resp *resty.Response) (io.ReadCloser, error) {
	raw := resp.RawResponse.Body
	switch strings.ToLower(strings.TrimSpace(resp.Header().Get("Content-Encoding"))) {
	case "", "identity":
		return &tdxResponseBody{Reader: raw, close: raw.Close}, nil
	case "gzip":
		reader, err := gzip.NewReader(raw)
		if err != nil {
			return nil, errors.Join(err, drainAndCloseResponse(resp))
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
			drainAndCloseResponse(resp),
		)
	}
}

func noopTDXFetch(invalidate func() error) *TDXFetch {
	return &TDXFetch{
		Ack:        func() error { return nil },
		Close:      func() error { return nil },
		Invalidate: invalidate,
	}
}

// Get is the streaming conditional GET. A successful response does not advance
// its marker until the returned fetch's Ack is called. A 304 returns a
// Modified=false fetch with safe no-op Ack and Close functions.
func (c *TDXClient) Get(ctx context.Context, url, name string) (*TDXFetch, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	marker, err := c.since(name)
	if err != nil {
		return nil, err
	}
	resp, err := c.get(ctx, url, marker)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode() == http.StatusNotModified {
		if cerr := drainAndCloseResponse(resp); cerr != nil {
			return nil, cerr
		}
		obs.Logf("[TDX] action=fetch event=not_modified name=%s", name)
		return noopTDXFetch(func() error {
			if err := c.store.Del(c.imsKey(name)); err != nil {
				return fmt.Errorf("invalidate TDX marker %s: %w", name, err)
			}
			return nil
		}), nil
	}
	if resp.StatusCode() >= http.StatusBadRequest {
		statusErr := &TDXStatusError{Name: name, Status: resp.StatusCode()}
		return nil, errors.Join(statusErr, drainAndCloseResponse(resp))
	}
	responseMarker := strings.TrimSpace(resp.Header().Get("Last-Modified"))
	if responseMarker == "" {
		return nil, errors.Join(
			fmt.Errorf("tdx %s: successful response missing Last-Modified", name),
			drainAndCloseResponse(resp),
		)
	}
	body, err := decodedTDXBody(resp)
	if err != nil {
		return nil, err
	}
	return &TDXFetch{
		Decoder:  json.NewDecoder(body),
		Modified: true,
		Ack: func() error {
			if err := c.store.Set(c.imsKey(name), responseMarker, 0); err != nil {
				return fmt.Errorf("ack TDX marker %s: %w", name, err)
			}
			return nil
		},
		Close: body.Close,
		Invalidate: func() error {
			if err := c.store.Del(c.imsKey(name)); err != nil {
				return fmt.Errorf("invalidate TDX marker %s: %w", name, err)
			}
			return nil
		},
	}, nil
}

// TDXIntoCommit is the durable callback input for GetInto. Marker is the fresh
// response's Last-Modified value and must be committed with Body when the
// caller's durable store uses the marker to validate later 304 responses. Body
// remains owned by GetInto; the callback may seek it but must not close it.
type TDXIntoCommit struct {
	Body   io.ReadSeeker
	Marker string
}

// TDXIntoResult describes a completed conditional request. Marker is the fresh
// Last-Modified value for a 200 response and the If-Modified-Since value that
// produced a 304 response. Invalidate deletes that conditional marker, allowing
// a caller whose durable state disagrees with a 304 to force one full refetch.
type TDXIntoResult struct {
	Modified   bool
	Marker     string
	Invalidate func() error
}

// GetInto is the disk-spooled conditional GET for callers that must durably
// handle the whole body before the If-Modified-Since marker advances (the
// raw_tdx landing). Fresh response bytes are streamed into a temporary file so
// large static datasets do not require an equally large heap allocation. The
// file is rewound before commit and remains owned by GetInto; commit may seek it
// for transaction retries but must not close it. The marker advances only after
// commit succeeds, so a failed durable write refetches on the next run.
func (c *TDXClient) GetInto(ctx context.Context, url, name string, commit func(TDXIntoCommit) error) (result TDXIntoResult, err error) {
	if ctx == nil {
		ctx = context.Background()
	}
	marker, err := c.since(name)
	if err != nil {
		return result, err
	}
	invalidate := func() error {
		if err := c.store.Del(c.imsKey(name)); err != nil {
			return fmt.Errorf("invalidate TDX marker %s: %w", name, err)
		}
		return nil
	}
	resp, err := c.get(ctx, url, marker)
	if err != nil {
		return result, err
	}
	if resp.StatusCode() == http.StatusNotModified {
		if cerr := drainAndCloseResponse(resp); cerr != nil {
			return result, cerr
		}
		obs.Logf("[TDX] action=fetch event=not_modified name=%s", name)
		return TDXIntoResult{Marker: marker, Invalidate: invalidate}, nil
	}
	if resp.StatusCode() >= http.StatusBadRequest {
		statusErr := &TDXStatusError{Name: name, Status: resp.StatusCode()}
		return result, errors.Join(statusErr, drainAndCloseResponse(resp))
	}
	responseMarker := strings.TrimSpace(resp.Header().Get("Last-Modified"))
	if responseMarker == "" {
		return result, errors.Join(
			fmt.Errorf("tdx %s: successful response missing Last-Modified", name),
			drainAndCloseResponse(resp),
		)
	}
	result = TDXIntoResult{Modified: true, Marker: responseMarker, Invalidate: invalidate}
	responseBody, err := decodedTDXBody(resp)
	if err != nil {
		return result, err
	}
	spool, err := os.CreateTemp("", "tdx-response-*.json")
	if err != nil {
		return result, errors.Join(fmt.Errorf("create TDX response spool: %w", err), responseBody.Close())
	}
	spoolName := spool.Name()
	spoolOpen := true
	spoolPresent := true
	defer func() {
		if spoolOpen {
			err = errors.Join(err, spool.Close())
		}
		if spoolPresent {
			err = errors.Join(err, os.Remove(spoolName))
		}
	}()
	_, copyErr := io.Copy(spool, responseBody)
	if closeErr := responseBody.Close(); copyErr != nil || closeErr != nil {
		return result, errors.Join(copyErr, closeErr)
	}
	if _, err := spool.Seek(0, io.SeekStart); err != nil {
		return result, fmt.Errorf("rewind TDX response spool: %w", err)
	}
	if commit != nil {
		if cerr := commit(TDXIntoCommit{Body: spool, Marker: responseMarker}); cerr != nil {
			return result, cerr
		}
	}
	if closeErr := spool.Close(); closeErr != nil {
		return result, fmt.Errorf("close TDX response spool: %w", closeErr)
	}
	spoolOpen = false
	if removeErr := os.Remove(spoolName); removeErr != nil {
		return result, fmt.Errorf("remove TDX response spool: %w", removeErr)
	}
	spoolPresent = false
	return result, c.cacheIMS(name, responseMarker)
}

// cacheIMS stores the response's Last-Modified header under name's IMS key so the
// next request can send it as If-Modified-Since.
func (c *TDXClient) cacheIMS(name, marker string) error {
	if err := c.store.Set(c.imsKey(name), marker, 0); err != nil {
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
