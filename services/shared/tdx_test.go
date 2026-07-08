package shared

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// memTDXStore is an in-memory TDXStore that records deletes, so tests can assert
// the token cache, the IMS marker, and the 401 dual-delete without a live Redis.
type memTDXStore struct {
	mu   sync.Mutex
	data map[string]string
	dels [][]string
}

func newMemTDXStore() *memTDXStore { return &memTDXStore{data: map[string]string{}} }

func (m *memTDXStore) Get(key string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.data[key], nil
}

func (m *memTDXStore) Set(key, value string, _ time.Duration) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.data[key] = value
	return nil
}

func (m *memTDXStore) Del(keys ...string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.dels = append(m.dels, keys)
	for _, k := range keys {
		delete(m.data, k)
	}
	return nil
}

func (m *memTDXStore) get(key string) string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.data[key]
}

func legacyIMSKey(name string) string { return TDXLegacyIMSKey(name) }

// TestTokenRefreshAndCache proves Token does a client_credentials exchange on a
// cold cache, caches the result, and serves the cache on the next call without a
// second exchange.
func TestTokenRefreshAndCache(t *testing.T) {
	var hits int32
	tokenSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		atomic.AddInt32(&hits, 1)
		_, _ = w.Write([]byte(`{"access_token":"tok-123"}`))
	}))
	defer tokenSrv.Close()

	store := newMemTDXStore()
	c := NewTDXClient(TDXConfig{Store: store, IMSKey: legacyIMSKey})
	c.tokenURL = tokenSrv.URL

	if got := c.Token(); got != "tok-123" {
		t.Fatalf("Token() = %q, want tok-123", got)
	}
	if store.get(TDXTokenKey) != "tok-123" {
		t.Fatalf("token not cached under %s: %q", TDXTokenKey, store.get(TDXTokenKey))
	}
	if got := c.Token(); got != "tok-123" {
		t.Fatalf("cached Token() = %q, want tok-123", got)
	}
	if n := atomic.LoadInt32(&hits); n != 1 {
		t.Fatalf("token endpoint hit %d times, want 1 (second call must serve cache)", n)
	}
}

// TestGet304LeavesMarker proves a 304 Not-Modified returns modified=false with no
// error and no decoder, and does not touch the cached If-Modified-Since marker.
func TestGet304LeavesMarker(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotModified)
	}))
	defer srv.Close()

	store := newMemTDXStore()
	store.data[TDXTokenKey] = "tok"
	store.data[TDXLegacyIMSKey("thing")] = "MARKER-OLD"
	c := NewTDXClient(TDXConfig{Store: store, IMSKey: legacyIMSKey, BaseURL: srv.URL})

	dec, modified, closeFn, err := c.Get("/x", "thing")
	if err != nil {
		t.Fatalf("Get on 304 returned error: %v", err)
	}
	if modified {
		t.Fatal("Get on 304 reported modified=true")
	}
	if dec != nil || closeFn != nil {
		t.Fatal("Get on 304 must return nil decoder and nil close")
	}
	if store.get(TDXLegacyIMSKey("thing")) != "MARKER-OLD" {
		t.Fatalf("304 overwrote IMS marker: %q", store.get(TDXLegacyIMSKey("thing")))
	}
}

// TestGet4xxDoesNotCacheMarker is the regression guard for the router's old bug:
// a 5xx/4xx must return a TDXStatusError, not decode the error body, and must
// leave the previous If-Modified-Since marker intact.
func TestGet4xxDoesNotCacheMarker(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Last-Modified", "SHOULD-NOT-CACHE")
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"error":"boom"}`))
	}))
	defer srv.Close()

	store := newMemTDXStore()
	store.data[TDXTokenKey] = "tok"
	store.data[TDXLegacyIMSKey("thing")] = "MARKER-OLD"
	c := NewTDXClient(TDXConfig{Store: store, IMSKey: legacyIMSKey, BaseURL: srv.URL})

	dec, modified, closeFn, err := c.Get("/x", "thing")
	var statusErr *TDXStatusError
	if !errors.As(err, &statusErr) {
		t.Fatalf("Get on 500 returned err %v, want *TDXStatusError", err)
	}
	if statusErr.Status != http.StatusInternalServerError {
		t.Fatalf("TDXStatusError.Status = %d, want 500", statusErr.Status)
	}
	if modified || dec != nil || closeFn != nil {
		t.Fatal("Get on 500 must return no decoder, no close, modified=false")
	}
	if store.get(TDXLegacyIMSKey("thing")) != "MARKER-OLD" {
		t.Fatalf("500 cached a bad IMS marker: %q", store.get(TDXLegacyIMSKey("thing")))
	}
}

// TestGet401ReAuths proves a 401 drops both token keys and retries with a freshly
// exchanged token, so a stale token self-heals on the next attempt.
func TestGet401ReAuths(t *testing.T) {
	tokenSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"access_token":"fresh-tok"}`))
	}))
	defer tokenSrv.Close()

	var attempts int32
	apiSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if atomic.AddInt32(&attempts, 1) == 1 {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		_, _ = w.Write([]byte(`[{"ok":true}]`))
	}))
	defer apiSrv.Close()

	store := newMemTDXStore()
	store.data[TDXTokenKey] = "stale-tok"
	c := NewTDXClient(TDXConfig{Store: store, IMSKey: legacyIMSKey, BaseURL: apiSrv.URL})
	c.tokenURL = tokenSrv.URL

	dec, modified, closeFn, err := c.Get("/x", "thing")
	if err != nil {
		t.Fatalf("Get across a 401 retry returned error: %v", err)
	}
	if !modified || dec == nil {
		t.Fatal("Get after re-auth must return fresh data")
	}
	if closeFn != nil {
		closeFn()
	}
	if n := atomic.LoadInt32(&attempts); n != 2 {
		t.Fatalf("API attempts = %d, want 2 (401 then retry)", n)
	}
	if len(store.dels) == 0 {
		t.Fatal("401 did not delete the token keys")
	}
	sawBothKeys := false
	for _, d := range store.dels {
		if len(d) == 2 && d[0] == TDXTokenKey && d[1] == TDXTokenKeyLegacy {
			sawBothKeys = true
		}
	}
	if !sawBothKeys {
		t.Fatalf("401 delete did not drop both token keys, dels=%v", store.dels)
	}
	if store.get(TDXTokenKey) != "fresh-tok" {
		t.Fatalf("token after re-auth = %q, want fresh-tok", store.get(TDXTokenKey))
	}
}

// TestGetIntoCommitsBeforeMarker proves GetInto advances the IMS marker only
// after commit succeeds, and leaves it untouched when commit fails, so a failed
// durable write refetches next run instead of being masked by a later 304.
func TestGetIntoCommitsBeforeMarker(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Last-Modified", "MARKER-NEW")
		_, _ = w.Write([]byte(`[1,2,3]`))
	}))
	defer srv.Close()

	commitErr := errors.New("commit failed")

	// Commit fails: marker must stay empty.
	failStore := newMemTDXStore()
	failStore.data[TDXTokenKey] = "tok"
	fc := NewTDXClient(TDXConfig{Store: failStore, IMSKey: legacyIMSKey, BaseURL: srv.URL})
	modified, err := fc.GetInto("/x", "thing", func([]byte) error { return commitErr })
	if !errors.Is(err, commitErr) {
		t.Fatalf("GetInto returned err %v, want commitErr", err)
	}
	if !modified {
		t.Fatal("GetInto with fresh data must report modified=true even on commit failure")
	}
	if failStore.get(TDXLegacyIMSKey("thing")) != "" {
		t.Fatalf("failed commit advanced the IMS marker: %q", failStore.get(TDXLegacyIMSKey("thing")))
	}

	// Commit succeeds: marker advances and commit sees the body.
	okStore := newMemTDXStore()
	okStore.data[TDXTokenKey] = "tok"
	oc := NewTDXClient(TDXConfig{Store: okStore, IMSKey: legacyIMSKey, BaseURL: srv.URL})
	var seen string
	modified, err = oc.GetInto("/x", "thing", func(b []byte) error { seen = string(b); return nil })
	if err != nil || !modified {
		t.Fatalf("GetInto ok path: modified=%v err=%v", modified, err)
	}
	if seen != "[1,2,3]" {
		t.Fatalf("commit body = %q, want [1,2,3]", seen)
	}
	if okStore.get(TDXLegacyIMSKey("thing")) != "MARKER-NEW" {
		t.Fatalf("successful commit did not advance IMS marker: %q", okStore.get(TDXLegacyIMSKey("thing")))
	}
}
