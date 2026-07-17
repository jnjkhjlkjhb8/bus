package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/go-resty/resty/v2"
)

// stubBooking builds a bookingProxy whose upstream clients point at a fake TDX
// that echoes the given handler, so the exchange path is exercised without real
// credentials or network.
func stubBooking(t *testing.T, handler http.HandlerFunc) (*bookingProxy, *httptest.Server) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		handler(w, r)
	}))
	t.Cleanup(srv.Close)
	client := resty.New().SetBaseURL(srv.URL)
	return &bookingProxy{tra: client, thsr: client}, srv
}

func bookingRouter(booking *bookingProxy) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/api/booking/deeplink", handleBookingDeeplink(booking))
	return r
}

func getBooking(r *gin.Engine, query string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodGet, "/api/booking/deeplink?"+query, nil)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, req)
	return rec
}

func TestBookingRoute(t *testing.T) {
	b := &bookingProxy{tra: resty.New(), thsr: resty.New()}
	cases := []struct {
		agency, kind string
		wantOK       bool
		wantPath     string
	}{
		{"tra", "direct", true, "/booking/deeplink/direct/tra"},
		{"tra", "web", true, "/booking/deeplink/web/tra"},
		{"hsr", "direct", true, "/booking/deeplink/direct/hsr"},
		{"hsr", "web", true, "/booking/deeplink/web/hsr"},
		{"tra", "store", false, ""},
		{"bus", "web", false, ""},
	}
	for _, tc := range cases {
		_, path, ok := b.route(tc.agency, tc.kind)
		if ok != tc.wantOK || path != tc.wantPath {
			t.Errorf("route(%q,%q) = (%q,%v), want (%q,%v)", tc.agency, tc.kind, path, ok, tc.wantPath, tc.wantOK)
		}
	}
}

func TestBookingDeeplinkSuccess(t *testing.T) {
	var gotPath, gotStart string
	booking, _ := stubBooking(t, func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotStart = r.URL.Query().Get("start_station")
		_, _ = w.Write([]byte(`{"result":"success","data":{"deeplink":"https://maas.transportdata.tw/x?token=abc","expired":"2026-07-18 04:13:20"}}`))
	})
	rec := getBooking(bookingRouter(booking),
		"agency=tra&kind=direct&start_station=%E8%87%BA%E5%8C%97&end_station=%E9%AB%98%E9%9B%84&train_date=2026-07-18&train_number=103")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (body %s)", rec.Code, rec.Body.String())
	}
	if gotPath != "/booking/deeplink/direct/tra" || gotStart != "臺北" {
		t.Fatalf("upstream got path=%q start=%q", gotPath, gotStart)
	}
	var out map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out["url"], "token=abc") {
		t.Fatalf("url = %q", out["url"])
	}
}

func TestBookingDeeplinkUpstreamFailure(t *testing.T) {
	booking, _ := stubBooking(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"result":"fail","error":{"msg":"no such train"}}`))
	})
	rec := getBooking(bookingRouter(booking),
		"agency=tra&kind=web&start_station=a&end_station=b&train_date=2026-07-18&train_number=103")
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", rec.Code)
	}
}

// The upstream body is the only thing that distinguishes a rejected station
// name from an unsubscribed API, so a failed exchange must carry it out to the
// log line rather than collapsing to a bare status.
func TestBookingExchangeErrorCarriesUpstreamDetail(t *testing.T) {
	booking, _ := stubBooking(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"result":"fail","error":{"msg":"no such train"}}`))
	})
	_, _, err := booking.exchange(t.Context(), booking.tra, "/booking/deeplink/web/tra", "a", "b", "2026-07-18", "103")
	if err == nil {
		t.Fatal("exchange succeeded, want failure")
	}
	// `result` stays empty here: resty only unmarshals SetResult on 2xx, which
	// is precisely why the raw body has to be logged alongside it.
	for _, want := range []string{"status=403", "no such train"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error %q is missing %q", err, want)
		}
	}
}

func TestBookingDeeplinkBadRequests(t *testing.T) {
	booking, _ := stubBooking(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"result":"success","data":{"deeplink":"x"}}`))
	})
	r := bookingRouter(booking)
	bad := []string{
		"agency=tra&kind=store&start_station=a&end_station=b&train_date=2026-07-18&train_number=103", // bad kind
		"agency=tra&kind=web&start_station=a&end_station=b&train_date=20260718&train_number=103",     // bad date
		"agency=tra&kind=web&start_station=a&end_station=b&train_date=2026-07-18&train_number=abc",   // bad train
		"agency=tra&kind=web&start_station=&end_station=b&train_date=2026-07-18&train_number=103",    // empty station
	}
	for _, q := range bad {
		if rec := getBooking(r, q); rec.Code != http.StatusBadRequest {
			t.Errorf("query %q: status = %d, want 400", q, rec.Code)
		}
	}
}

func TestBookingDeeplinkUnavailableWhenNil(t *testing.T) {
	rec := getBooking(bookingRouter(nil),
		"agency=tra&kind=web&start_station=a&end_station=b&train_date=2026-07-18&train_number=103")
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", rec.Code)
	}
}
