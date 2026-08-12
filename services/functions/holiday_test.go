package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestIsHolidayFallback(t *testing.T) {
	storeHolidaySnapshot(nil)
	sat := time.Date(2026, 6, 13, 12, 0, 0, 0, _taipei)
	sun := time.Date(2026, 6, 14, 12, 0, 0, 0, _taipei)
	mon := time.Date(2026, 6, 15, 12, 0, 0, 0, _taipei)
	if !isHoliday(sat) {
		t.Error("Saturday should be holiday")
	}
	if !isHoliday(sun) {
		t.Error("Sunday should be holiday")
	}
	if isHoliday(mon) {
		t.Error("Monday should not be holiday")
	}
}

func TestRefreshHolidaysKeepsLastGoodOnFailure(t *testing.T) {
	storeHolidaySnapshot(map[string]bool{"2026-01-01": true})
	t.Cleanup(func() { storeHolidaySnapshot(nil) })
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "unavailable", http.StatusServiceUnavailable)
	}))
	defer server.Close()

	err := refreshHolidays(context.Background(), server.Client(), server.URL)
	if err == nil {
		t.Fatal("HTTP 503 returned nil error")
	}
	if !isHoliday(time.Date(2026, 1, 1, 12, 0, 0, 0, _taipei)) {
		t.Fatal("failed refresh replaced last-good snapshot")
	}
}

func TestRefreshHolidaysHonorsContextDeadline(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		<-r.Context().Done()
	}))
	defer server.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()

	err := refreshHolidays(ctx, server.Client(), server.URL)
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("refresh error = %v, want deadline exceeded", err)
	}
}

func TestRefreshHolidaysSwapsCompleteSnapshot(t *testing.T) {
	storeHolidaySnapshot(nil)
	t.Cleanup(func() { storeHolidaySnapshot(nil) })
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("date,a,b,holiday\n20260101,x,x,是\n20260620,x,x,否\n"))
	}))
	defer server.Close()

	if err := refreshHolidays(context.Background(), server.Client(), server.URL); err != nil {
		t.Fatalf("refresh: %v", err)
	}
	if !isHoliday(time.Date(2026, 1, 1, 12, 0, 0, 0, _taipei)) {
		t.Fatal("explicit holiday missing")
	}
	if isHoliday(time.Date(2026, 6, 20, 12, 0, 0, 0, _taipei)) {
		t.Fatal("explicit weekend working day ignored")
	}
}

func TestIsHolidayFromMap(t *testing.T) {
	storeHolidaySnapshot(map[string]bool{
		"2026-01-01": true,
		"2026-06-15": false,
	})
	newYear := time.Date(2026, 1, 1, 12, 0, 0, 0, _taipei)
	monday := time.Date(2026, 6, 15, 12, 0, 0, 0, _taipei)
	if !isHoliday(newYear) {
		t.Error("New Year should be holiday")
	}
	if isHoliday(monday) {
		t.Error("Normal Monday should not be holiday")
	}
	missingSaturday := time.Date(2026, 6, 20, 12, 0, 0, 0, _taipei)
	if !isHoliday(missingSaturday) {
		t.Error("Saturday absent from loaded snapshot should use weekend fallback")
	}
	storeHolidaySnapshot(nil)
}
