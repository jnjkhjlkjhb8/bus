package main

import (
	"context"
	"encoding/json"
	"os"
	"testing"

	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/pashagolub/pgxmock/v4"
)

func TestResolveBusNotificationIdentityUnique(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	db.ExpectQuery("FROM bus_subroutes").
		WithArgs("台北車站", "西門站", "307", "307", "307").
		WillReturnRows(pgxmock.NewRows([]string{"sub_route_uid", "direction", "departure_stop_uid", "arrival_stop_uid"}).
			AddRow("TPE3070", int32(0), "TPE100", "TPE200"))

	got := resolveBusNotificationIdentity(context.Background(), db, tdxSection{
		Departure: tdxPlaceInfo{Place: tdxPlace{Name: "台北車站"}},
		Arrival:   tdxPlaceInfo{Place: tdxPlace{Name: "西門站"}},
		Transport: tdxTransport{Mode: "HighwayBus", Name: "307", ShortName: "307", Number: "307"},
	})

	want := &pb.NotificationIdentity{
		RouteType:        "bus",
		RouteKey:         "TPE3070",
		Direction:        "0",
		DepartureStopKey: "TPE100",
		ArrivalStopKey:   "TPE200",
		Supported:        true,
	}
	if got.String() != want.String() {
		t.Fatalf("got %v want %v", got, want)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
func TestResolveBusNotificationIdentityAmbiguous(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	db.ExpectQuery("FROM bus_subroutes").
		WithArgs("台北車站", "西門站", "307", "307", "").
		WillReturnRows(pgxmock.NewRows([]string{"sub_route_uid", "direction", "departure_stop_uid", "arrival_stop_uid"}).
			AddRow("TPE3070", int32(0), "TPE100", "TPE200").
			AddRow("NWT3070", int32(0), "NWT100", "NWT200"))

	got := resolveBusNotificationIdentity(context.Background(), db, tdxSection{
		Departure: tdxPlaceInfo{Place: tdxPlace{Name: "台北車站"}},
		Arrival:   tdxPlaceInfo{Place: tdxPlace{Name: "西門站"}},
		Transport: tdxTransport{Mode: "BUS", Name: "307", ShortName: "307"},
	})
	if got.GetSupported() {
		t.Fatalf("ambiguous match must be unsupported: %v", got)
	}
}

func TestResolveBusNotificationIdentityNoMatchAndNonBus(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	db.ExpectQuery("FROM bus_subroutes").
		WithArgs("不存在", "西門站", "307", "", "").
		WillReturnRows(pgxmock.NewRows([]string{"sub_route_uid", "direction", "departure_stop_uid", "arrival_stop_uid"}))

	got := resolveBusNotificationIdentity(context.Background(), db, tdxSection{
		Departure: tdxPlaceInfo{Place: tdxPlace{Name: "不存在"}},
		Arrival:   tdxPlaceInfo{Place: tdxPlace{Name: "西門站"}},
		Transport: tdxTransport{Mode: "BUS", Name: "307"},
	})
	if got.GetSupported() {
		t.Fatalf("no match must be unsupported: %v", got)
	}

	got = resolveBusNotificationIdentity(context.Background(), db, tdxSection{
		Transport: tdxTransport{Mode: "MRT", Name: "板南線"},
	})
	if got.GetSupported() {
		t.Fatalf("non-bus mode must be unsupported: %v", got)
	}
}
