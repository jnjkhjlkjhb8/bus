package notify

import (
	"context"
	"encoding/json"
	"regexp"
	"testing"
	"time"

	"github.com/pashagolub/pgxmock/v4"
)

type arrivalEventsJSONMatcher struct {
	want []ArrivalEvent
}

func (m arrivalEventsJSONMatcher) Match(value any) bool {
	var payload []byte
	switch value := value.(type) {
	case string:
		payload = []byte(value)
	case []byte:
		payload = value
	default:
		return false
	}
	var got []ArrivalEvent
	if err := json.Unmarshal(payload, &got); err != nil || len(got) != len(m.want) {
		return false
	}
	for i := range got {
		if got[i] != m.want[i] {
			return false
		}
	}
	return true
}

func TestArrivalEventsJSONMatcherRejectsWrongPayload(t *testing.T) {
	want := []ArrivalEvent{
		{RouteType: "bus", RouteKey: "R1", StopKey: "S1", Direction: "0", ETASeconds: 60, ArrivingPlate: "BUS-1"},
		{RouteType: "bus", RouteKey: "R2", StopKey: "S2", Direction: "1", ETASeconds: 120, ArrivingPlate: "BUS-2"},
	}
	wrong, err := json.Marshal([]ArrivalEvent{want[1], want[0]})
	if err != nil {
		t.Fatal(err)
	}
	if (arrivalEventsJSONMatcher{want: want}).Match(string(wrong)) {
		t.Fatal("matcher accepted arrival events in the wrong order")
	}
}

func TestNotificationStoreActiveRemindersUsesOneCompositeBatchQuery(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	now := time.Unix(1_800_000_000, 0)
	events := []ArrivalEvent{
		{RouteType: "bus", RouteKey: "R", StopKey: "S1", Direction: "0", ETASeconds: 60, ArrivingPlate: "BUS-1"},
		{RouteType: "bus", RouteKey: "R", StopKey: "S2", Direction: "1", ETASeconds: 240, ArrivingPlate: "BUS-2"},
	}
	db.ExpectQuery("jsonb_to_recordset"+regexp.QuoteMeta("($1::jsonb)")+
		".*r\\.route_type=a\\.route_type AND r\\.route_key=a\\.route_key"+
		".*r\\.stop_key=a\\.stop_key AND r\\.direction=a\\.direction"+
		".*a\\.eta_seconds<=r\\.lead_minutes\\*60"+
		".*r\\.plate='' OR r\\.plate=a\\.arriving_plate").
		WithArgs(arrivalEventsJSONMatcher{want: events}, now).
		WillReturnRows(pgxmock.NewRows([]string{
			"reminder_id", "fcm_token", "route_type", "route_key", "stop_key", "direction", "lead_minutes", "plate",
			"arrival_route_type", "arrival_route_key", "arrival_stop_key", "arrival_direction", "eta_seconds", "arriving_plate",
		}).AddRow("r2", "token-2", "bus", "R", "S2", "1", 5, "BUS-2", "bus", "R", "S2", "1", int32(240), "BUS-2"))

	matches, err := (Store{db: db}).activeRemindersForArrivals(context.Background(), events, now)
	if err != nil {
		t.Fatalf("activeRemindersForArrivals() error = %v", err)
	}
	if len(matches) != 1 || matches[0].reminder.id != "r2" || matches[0].arrival != events[1] {
		t.Fatalf("matches = %#v, want reminder r2 matched to second composite event", matches)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestNotificationStoreFiltersRouteAndEnabledDevice(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	db.ExpectQuery("FROM firebase_route_subscription.*s.route_type=\\$1 AND s.route_key=\\$2.*d.push_enabled").WithArgs("bus", "R1").WillReturnRows(pgxmock.NewRows([]string{"fcm_token"}).AddRow("token"))
	got, err := (Store{db: db}).subscribedTokens(context.Background(), "bus", "R1")
	if err != nil || len(got) != 1 || got[0].token != "token" {
		t.Fatalf("got=%v err=%v", got, err)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestNotificationStoreClaimIsAtomic(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	now := time.Now()
	db.ExpectExec("UPDATE firebase_arrival_reminder SET status='sending'.*status='pending'.*expires_at>\\$2").WithArgs("r1", now).WillReturnResult(pgxmock.NewResult("UPDATE", 1))
	claimed, err := (Store{db: db}).claim(context.Background(), "r1", now)
	if err != nil || !claimed {
		t.Fatalf("claimed=%v err=%v", claimed, err)
	}
	db.ExpectExec("UPDATE firebase_arrival_reminder SET status='sending'.*status='pending'.*expires_at>\\$2").WithArgs("r1", now).WillReturnResult(pgxmock.NewResult("UPDATE", 0))
	claimed, err = (Store{db: db}).claim(context.Background(), "r1", now)
	if err != nil || claimed {
		t.Fatalf("claimed=%v err=%v", claimed, err)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}

func TestNotificationStoreFiredAndInvalidToken(t *testing.T) {
	db, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	now := time.Now()
	db.ExpectExec("UPDATE firebase_arrival_reminder SET status='fired'.*status='sending'").WithArgs("r1", now).WillReturnResult(pgxmock.NewResult("UPDATE", 1))
	fired, err := (Store{db: db}).fired(context.Background(), "r1", now)
	if err != nil || !fired {
		t.Fatalf("fired=%v err=%v", fired, err)
	}
	db.ExpectExec("UPDATE firebase_device SET fcm_token='',push_enabled=FALSE.*fcm_token=\\$1").WithArgs("bad").WillReturnResult(pgxmock.NewResult("UPDATE", 1))
	if err := (Store{db: db}).invalidate(context.Background(), "bad"); err != nil {
		t.Fatal(err)
	}
	if err := db.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
