package main

import (
	"errors"
	"testing"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/obs"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func TestMakeThatSame(t *testing.T) {
	cases := []struct {
		input, want string
	}{
		{"THB123401", "THB1234"},
		{"THB123402", "THB1234"},
		{"TPE1234", "TPE1234"},
	}
	for _, tc := range cases {
		got := makethatsame(tc.input)
		if got != tc.want {
			t.Errorf("makethatsame(%q) = %q, want %q", tc.input, got, tc.want)
		}
	}
}

func TestBusRouteEtaKeyUsesNormalizedRouteUID(t *testing.T) {
	got := busRouteEtaKey("THB123401")
	want := "bus_eta_route:THB1234"
	if got != want {
		t.Fatalf("busRouteEtaKey() = %q, want %q", got, want)
	}
}

func TestUsableBusEtaPayloadRejectsEmptyPayload(t *testing.T) {
	if usableBusEtaPayload(nil) {
		t.Fatal("nil payload should not be sent")
	}
	if usableBusEtaPayload([]byte{}) {
		t.Fatal("empty payload should not be sent")
	}
	if !usableBusEtaPayload([]byte{1}) {
		t.Fatal("non-empty payload should be sent")
	}
}

func TestGrpcStatusFor(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want codes.Code
	}{
		{"pgx no rows", pgx.ErrNoRows, codes.NotFound},
		{"redis nil", redis.Nil, codes.NotFound},
		{"obs not found", obs.NotFound(errors.New("missing")), codes.NotFound},
		{"other", errors.New("boom"), codes.Internal},
	}
	for _, tc := range cases {
		if got := status.Code(grpcStatusFor(tc.err, "not found")); got != tc.want {
			t.Fatalf("%s got %v want %v", tc.name, got, tc.want)
		}
	}
}
