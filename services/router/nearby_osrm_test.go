package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-resty/resty/v2"
)

func TestOSRMWalkingRouterPreservesOrderAndNullableCells(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path != "/table/v1/foot/121.500000,25.000000;121.510000,25.010000;121.520000,25.020000" {
			t.Errorf("path = %q", r.URL.Path)
		}
		if got := r.URL.Query().Get("sources"); got != "0" {
			t.Errorf("sources = %q, want 0", got)
		}
		if got := r.URL.Query().Get("destinations"); got != "1;2" {
			t.Errorf("destinations = %q, want 1;2", got)
		}
		if got := r.URL.Query().Get("annotations"); got != "duration,distance" {
			t.Errorf("annotations = %q", got)
		}
		_, _ = w.Write([]byte(`{"code":"Ok","durations":[[300,null]],"distances":[[450,null]]}`))
	}))
	defer server.Close()

	router := NewOSRMWalkingRouter(resty.New(), server.URL)
	got, err := router.RouteMany(context.Background(), GeoPoint{Lon: 121.5, Lat: 25}, []GeoPoint{
		{Lon: 121.51, Lat: 25.01},
		{Lon: 121.52, Lat: 25.02},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].DurationSeconds == nil || *got[0].DurationSeconds != 300 || got[1].DurationSeconds != nil {
		t.Fatalf("metrics = %+v, want ordered duration then null", got)
	}
}

func TestOSRMWalkingRouterPropagatesContextCancellation(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-r.Context().Done()
	}))
	defer server.Close()

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := NewOSRMWalkingRouter(resty.New(), server.URL).RouteMany(ctx, GeoPoint{}, []GeoPoint{{Lon: 1, Lat: 1}})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want context.Canceled", err)
	}
}
