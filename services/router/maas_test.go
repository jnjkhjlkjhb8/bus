package main

import (
	"context"
	"testing"
	"time"

	"github.com/go-resty/resty/v2"
	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/pashagolub/pgxmock/v4"
)

func TestMaasTimeParam(t *testing.T) {
	now := time.Date(2026, 7, 11, 23, 0, 0, 0, time.Local)
	layout := "2006-01-02T15:04:05"

	// TDX requires both depart and arrival present (else 40001); every case
	// must return the two equal and non-empty.
	assertBoth := func(t *testing.T, depart, arrival, want string) {
		t.Helper()
		if depart != arrival {
			t.Fatalf("depart %q != arrival %q, TDX needs both equal", depart, arrival)
		}
		if want != "" && depart != want {
			t.Fatalf("got %q, want %q", depart, want)
		}
	}

	t.Run("arriveBy sends the requested time with padded seconds", func(t *testing.T) {
		d, a := maasTimeParam("2026-07-12", "08:30", true, now)
		assertBoth(t, d, a, "2026-07-12T08:30:00")
	})

	t.Run("future depart is passed through unchanged", func(t *testing.T) {
		d, a := maasTimeParam("2026-07-11", "23:30", false, now)
		assertBoth(t, d, a, "2026-07-11T23:30:00")
	})

	// A depart at/before now must be bumped into the future to avoid TDX 20001.
	for _, tt := range []struct{ name, date, tm string }{
		{"now", "2026-07-11", "23:00"},
		{"past", "2026-07-11", "22:00"},
	} {
		t.Run("depart "+tt.name+" is bumped into the future", func(t *testing.T) {
			d, a := maasTimeParam(tt.date, tt.tm, false, now)
			assertBoth(t, d, a, "")
			got, err := time.ParseInLocation(layout, d, time.Local)
			if err != nil {
				t.Fatalf("unparseable depart %q: %v", d, err)
			}
			if !got.After(now) {
				t.Fatalf("depart %v not after now %v", got, now)
			}
		})
	}

	t.Run("unparseable time falls through unchanged", func(t *testing.T) {
		d, a := maasTimeParam("", "", false, now)
		assertBoth(t, d, a, "T")
	})
}

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

// clampInt guards the TDX plan-request parameters; a wrong bound sends invalid
// values upstream, a broken zero-default breaks every old client that omits
// the field.
func TestClampInt(t *testing.T) {
	tests := []struct {
		name                   string
		v, min, max, def, want int32
	}{
		{"unset falls back to default when 0 invalid", 0, 1, 10, 5, 5},
		{"zero kept when 0 within range", 0, 0, 10, 5, 0},
		{"zero kept when range spans negative", 0, -5, 5, 3, 0},
		{"below min clamps up", -3, 1, 10, 5, 1},
		{"above max clamps down", 99, 1, 10, 5, 10},
		{"in range passes through", 7, 1, 10, 5, 7},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := clampInt(tt.v, tt.min, tt.max, tt.def); got != tt.want {
				t.Fatalf("clampInt(%d,%d,%d,%d) = %d, want %d", tt.v, tt.min, tt.max, tt.def, got, tt.want)
			}
		})
	}
}

// A cache-key collision between different plan requests would serve one user
// another user's journey plan; identical requests must hit the same key or the
// cache never helps.
func TestMaasKeyIdentityAndCollision(t *testing.T) {
	base := func() *pb.MaasPlanRequest {
		return &pb.MaasPlanRequest{
			FromLat: 25.0478, FromLon: 121.5170, ToLat: 25.0330, ToLon: 121.5654,
			Date: "2026-07-11", Time: "08:00", Top: 5,
		}
	}
	first, second := maasKey(base()), maasKey(base())
	if first != second {
		t.Fatal("identical requests must produce the same cache key")
	}
	mutations := map[string]func(r *pb.MaasPlanRequest){
		"destination": func(r *pb.MaasPlanRequest) { r.ToLat += 0.001 },
		"date":        func(r *pb.MaasPlanRequest) { r.Date = "2026-07-12" },
		"arrive_by":   func(r *pb.MaasPlanRequest) { r.ArriveBy = true },
		"modes":       func(r *pb.MaasPlanRequest) { r.TransitModes = []int32{3} },
	}
	seen := map[string]string{maasKey(base()): "base"}
	for name, mutate := range mutations {
		r := base()
		mutate(r)
		key := maasKey(r)
		if prev, dup := seen[key]; dup {
			t.Fatalf("cache key collision between %q and %q", name, prev)
		}
		seen[key] = name
	}
}
