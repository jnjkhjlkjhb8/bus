package main

import (
	"context"
	"testing"

	"github.com/go-resty/resty/v2"
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

func TestSectionFareMetroTraThsr(t *testing.T) {
	for _, tc := range []struct {
		name  string
		mode  string
		query string
		fare  int32
	}{
		{"metro", "SUBWAY", "FROM mrt_journey_matrix", 25},
		{"tra", "RAIL", "FROM tra_fares", 41},
		{"thsr", "THSR", "FROM thsr_fares", 700},
	} {
		t.Run(tc.name, func(t *testing.T) {
			db, err := pgxmock.NewPool()
			if err != nil {
				t.Fatal(err)
			}
			defer db.Close()
			db.ExpectQuery(tc.query).
				WithArgs("台北", "台中").
				WillReturnRows(pgxmock.NewRows([]string{"fare"}).AddRow(tc.fare))

			sec := tdxSection{
				Departure: tdxPlaceInfo{Place: tdxPlace{Name: "台北"}},
				Arrival:   tdxPlaceInfo{Place: tdxPlace{Name: "台中"}},
				Transport: tdxTransport{Mode: tc.mode},
			}
			got, ok := sectionFare(context.Background(), db, sec)
			if !ok || got != tc.fare {
				t.Fatalf("got=%d ok=%v want=%d", got, ok, tc.fare)
			}
			if err := db.ExpectationsWereMet(); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestSectionFareMissingLeavesUnset(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	// Non-rail mode: no query is issued and the fare stays unset.
	if fare, ok := sectionFare(context.Background(), db, tdxSection{
		Departure: tdxPlaceInfo{Place: tdxPlace{Name: "A"}},
		Arrival:   tdxPlaceInfo{Place: tdxPlace{Name: "B"}},
		Transport: tdxTransport{Mode: "BUS"},
	}); ok || fare != 0 {
		t.Fatalf("bus mode must not resolve a fare: fare=%d ok=%v", fare, ok)
	}

	// Rail mode with no matching row: fare stays unset, plan is not failed.
	db.ExpectQuery("FROM tra_fares").
		WithArgs("A", "B").
		WillReturnRows(pgxmock.NewRows([]string{"price"}))
	if fare, ok := sectionFare(context.Background(), db, tdxSection{
		Departure: tdxPlaceInfo{Place: tdxPlace{Name: "A"}},
		Arrival:   tdxPlaceInfo{Place: tdxPlace{Name: "B"}},
		Transport: tdxTransport{Mode: "TRA"},
	}); ok || fare != 0 {
		t.Fatalf("missing fare must be unset: fare=%d ok=%v", fare, ok)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestWalkDurationFallsBackWithoutOSRM(t *testing.T) {
	// A nil client or zero coordinates must report ok=false so the caller keeps
	// the fixed TDX first/last-mile estimate.
	from := &pb.Location{Lat: 25.0, Lng: 121.5}
	to := &pb.Location{Lat: 25.1, Lng: 121.6}
	if _, ok := walkDurationSeconds(context.Background(), nil, from, to); ok {
		t.Fatal("nil OSRM client must fall back")
	}
	zero := &pb.Location{}
	if _, ok := walkDurationSeconds(context.Background(), resty.New(), zero, to); ok {
		t.Fatal("zero origin must fall back")
	}
	if _, ok := walkDurationSeconds(context.Background(), resty.New(), from, zero); ok {
		t.Fatal("zero destination must fall back")
	}
}
