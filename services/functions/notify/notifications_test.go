package notify

import (
	"context"
	"errors"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
)

type fakeNotificationStore struct {
	tokens                                                  []deviceToken
	reminders                                               []arrivalReminder
	due                                                     []arrivalReminder
	claimed                                                 map[string]bool
	firedIDs                                                []string
	invalidated                                             []string
	wantRouteType, wantRouteKey, wantStopKey, wantDirection string
}

func (s *fakeNotificationStore) dueScheduledReminders(context.Context, time.Time) ([]arrivalReminder, error) {
	return s.due, nil
}

func (s *fakeNotificationStore) subscribedTokens(_ context.Context, routeType, routeKey string) ([]deviceToken, error) {
	if routeType != s.wantRouteType || routeKey != s.wantRouteKey {
		return nil, nil
	}
	return s.tokens, nil
}
func (s *fakeNotificationStore) activeReminders(_ context.Context, routeType, routeKey, stopKey, direction string, _ time.Time) ([]arrivalReminder, error) {
	if routeType != s.wantRouteType || routeKey != s.wantRouteKey || stopKey != s.wantStopKey || direction != s.wantDirection {
		return nil, nil
	}
	return s.reminders, nil
}
func (s *fakeNotificationStore) claim(_ context.Context, id string, _ time.Time) (bool, error) {
	if s.claimed[id] {
		return false, nil
	}
	s.claimed[id] = true
	return true, nil
}
func (s *fakeNotificationStore) release(context.Context, string) (bool, error) { return true, nil }
func (s *fakeNotificationStore) fired(_ context.Context, id string, _ time.Time) (bool, error) {
	s.firedIDs = append(s.firedIDs, id)
	return true, nil
}
func (s *fakeNotificationStore) invalidate(_ context.Context, token string) error {
	s.invalidated = append(s.invalidated, token)
	return nil
}

type fakeFCM struct {
	messages []*messaging.Message
	err      error
}

func (f *fakeFCM) Send(_ context.Context, m *messaging.Message) error {
	f.messages = append(f.messages, m)
	return f.err
}

func TestFirebaseDisabledInDev(t *testing.T) {
	t.Setenv("FIREBASE_ENABLED", "true")
	t.Setenv("APP_ENV", "dev")
	sender, err := NewFirebaseSender(context.Background())
	if err != nil || sender != nil {
		t.Fatalf("sender=%v err=%v", sender, err)
	}
}

func TestRouteAlertMatchingAndDedupe(t *testing.T) {
	store := &fakeNotificationStore{tokens: []deviceToken{{"a"}, {"a"}, {"b"}}, claimed: map[string]bool{}, wantRouteType: "bus", wantRouteKey: "R1"}
	sender := &fakeFCM{}
	d := NewDispatcher(store, sender)
	d.routeAlert(context.Background(), "bus", "R1", "延誤")
	if len(sender.messages) != 2 {
		t.Fatalf("sent=%d", len(sender.messages))
	}
	for _, m := range sender.messages {
		if m.Data["route_key"] != "R1" || m.Data["kind"] != "route_alert" || m.Data["title"] == "" || m.Data["body"] == "" {
			t.Fatalf("data=%v", m.Data)
		}
	}
}

func TestArrivalThresholdClaimAndNoDuplicate(t *testing.T) {
	store := &fakeNotificationStore{claimed: map[string]bool{}, reminders: []arrivalReminder{{id: "r1", token: "t", routeType: "bus", routeKey: "R", stopKey: "S", direction: "0", leadMinutes: 5}}, wantRouteType: "bus", wantRouteKey: "R", wantStopKey: "S", wantDirection: "0"}
	sender := &fakeFCM{}
	d := NewDispatcher(store, sender)
	d.Arrival(context.Background(), "bus", "R", "S", "0", 301)
	if len(sender.messages) != 0 {
		t.Fatal("sent above threshold")
	}
	d.Arrival(context.Background(), "bus", "R", "S", "0", 300)
	d.Arrival(context.Background(), "bus", "R", "S", "0", 100)
	if len(sender.messages) != 1 || len(store.firedIDs) != 1 {
		t.Fatalf("sent=%d fired=%v", len(sender.messages), store.firedIDs)
	}
	m := sender.messages[0]
	if m.Data["kind"] != "arrival_reminder" || m.Notification.Title != "即將到站" || m.Android == nil || m.APNS == nil {
		t.Fatalf("message=%+v", m)
	}
}

func TestRouteAlertsRequireIdentity(t *testing.T) {
	if got := routeAlerts("v2/Bus/News/City/Taipei", []byte(`{"Description":"x"}`)); len(got) != 0 {
		t.Fatalf("got=%v", got)
	}
	got := routeAlerts("v2/Bus/News/City/Taipei", []byte(`[{"SubRouteUID":"R1","Description":"x"},{"SubRouteUID":"R1","Description":"x"}]`))
	if len(got) != 1 || got[0].routeKey != "R1" {
		t.Fatalf("got=%v", got)
	}
	if got := routeAlerts("v3/Rail/TRA/Alert", []byte(`{"TrainNo":"123","Description":"x"}`)); len(got) != 0 {
		t.Fatalf("train-level alert leaked: %v", got)
	}
	if got := routeAlerts("v2/Rail/Metro/Alert/TRTC", []byte(`{"LineID":"BL","Description":"x"}`)); len(got) != 0 {
		t.Fatalf("non-bus alert leaked: %v", got)
	}
}

func TestRouteAlertStaysBusOnly(t *testing.T) {
	// Service-alert pushes remain bus-only; a non-bus routeAlert is a no-op.
	store := &fakeNotificationStore{
		tokens:        []deviceToken{{"token"}},
		claimed:       map[string]bool{},
		wantRouteType: "tra",
		wantRouteKey:  "123",
	}
	sender := &fakeFCM{}
	NewDispatcher(store, sender).routeAlert(context.Background(), "tra", "123", "延誤")
	if len(sender.messages) != 0 {
		t.Fatalf("non-bus route alert sent=%d", len(sender.messages))
	}
}

func TestArrivalFiresForNonBusTypes(t *testing.T) {
	// Arrival reminders are transport-agnostic: metro/TRA/THSR fire the same way
	// as bus once their ETA source computes a usable etaSeconds.
	for _, routeType := range []string{"mrt", "tra", "thsr"} {
		t.Run(routeType, func(t *testing.T) {
			store := &fakeNotificationStore{
				claimed:       map[string]bool{},
				reminders:     []arrivalReminder{{id: "r1", token: "t", routeType: routeType, routeKey: "R", stopKey: "S", direction: "0", leadMinutes: 5}},
				wantRouteType: routeType,
				wantRouteKey:  "R",
				wantStopKey:   "S",
				wantDirection: "0",
			}
			sender := &fakeFCM{}
			d := NewDispatcher(store, sender)
			d.Arrival(context.Background(), routeType, "R", "S", "0", 60)
			if len(sender.messages) != 1 || len(store.firedIDs) != 1 {
				t.Fatalf("sent=%d fired=%v", len(sender.messages), store.firedIDs)
			}
			if store.firedIDs[0] != "r1" || sender.messages[0].Data["route_type"] != routeType {
				t.Fatalf("message=%+v fired=%v", sender.messages[0].Data, store.firedIDs)
			}
		})
	}
}

func TestFireScheduledClaimsSendsAndFires(t *testing.T) {
	store := &fakeNotificationStore{
		claimed: map[string]bool{},
		due:     []arrivalReminder{{id: "r1", token: "t", routeType: "tra", routeKey: "1120", stopKey: "南港", direction: "0", leadMinutes: 3}},
	}
	sender := &fakeFCM{}
	d := NewDispatcher(store, sender)
	d.FireScheduled(context.Background())
	if len(sender.messages) != 1 || len(store.firedIDs) != 1 {
		t.Fatalf("sent=%d fired=%v", len(sender.messages), store.firedIDs)
	}
	m := sender.messages[0]
	if m.Data["kind"] != "arrival_reminder" || m.Data["route_type"] != "tra" || m.Notification.Title != "即將到站" {
		t.Fatalf("message=%+v", m.Data)
	}
	// A later tick that still sees the (unremoved) reminder must not resend it:
	// the claim guard prevents duplicate pushes across ticks.
	d.FireScheduled(context.Background())
	if len(sender.messages) != 1 {
		t.Fatalf("resent claimed reminder: sent=%d", len(sender.messages))
	}
}

func TestRouteAlertDedupeAcrossMessages(t *testing.T) {
	store := &fakeNotificationStore{tokens: []deviceToken{{"token"}}, claimed: map[string]bool{}, wantRouteType: "bus", wantRouteKey: "R1"}
	sender := &fakeFCM{}
	dispatcher := NewDispatcher(store, sender)
	claimed := map[string]bool{}
	claim := func(key string, _ time.Duration) bool {
		if claimed[key] {
			return false
		}
		claimed[key] = true
		return true
	}
	alerts := routeAlerts("v2/Bus/News/City/Taipei", []byte(`{"SubRouteUID":"R1","NewsID":"A1","Description":"x"}`))
	dispatchRouteAlerts(context.Background(), alerts, claim, dispatcher)
	dispatchRouteAlerts(context.Background(), alerts, claim, dispatcher)
	if len(sender.messages) != 1 {
		t.Fatalf("sent=%d", len(sender.messages))
	}
}

func TestRouteAlertDedupeDoesNotCollideAcrossRoutes(t *testing.T) {
	claimed := map[string]bool{}
	claim := func(key string, _ time.Duration) bool {
		if claimed[key] {
			return false
		}
		claimed[key] = true
		return true
	}
	store := &fakeNotificationStore{tokens: []deviceToken{{"token"}}, claimed: map[string]bool{}}
	sender := &fakeFCM{}
	dispatcher := NewDispatcher(store, sender)
	for _, routeKey := range []string{"R1", "R2"} {
		store.wantRouteType, store.wantRouteKey = "bus", routeKey
		dispatchRouteAlerts(context.Background(), []normalizedRouteAlert{{
			routeType: "bus", routeKey: routeKey, body: "x", id: "A1",
		}}, claim, dispatcher)
	}
	if len(sender.messages) != 2 {
		t.Fatalf("same alert ID on different routes sent=%d", len(sender.messages))
	}
}

func TestArrivalCancelledBeforeClaimDoesNotSend(t *testing.T) {
	store := &fakeNotificationStore{claimed: map[string]bool{"r1": true}, reminders: []arrivalReminder{{id: "r1", token: "t", leadMinutes: 5}}, wantRouteType: "bus", wantRouteKey: "R", wantStopKey: "S", wantDirection: "0"}
	sender := &fakeFCM{}
	NewDispatcher(store, sender).Arrival(context.Background(), "bus", "R", "S", "0", 1)
	if len(sender.messages) != 0 {
		t.Fatal("sent cancelled reminder")
	}
}

func TestInvalidTokenCleanupAndAtMostOnce(t *testing.T) {
	sendErr := errors.New("invalid token")
	old := isInvalidFCMToken
	isInvalidFCMToken = func(err error) bool { return errors.Is(err, sendErr) }
	t.Cleanup(func() { isInvalidFCMToken = old })
	store := &fakeNotificationStore{claimed: map[string]bool{}, reminders: []arrivalReminder{{id: "r1", token: "bad", leadMinutes: 5}}, wantRouteType: "bus", wantRouteKey: "R", wantStopKey: "S", wantDirection: "0"}
	sender := &fakeFCM{err: sendErr}
	NewDispatcher(store, sender).Arrival(context.Background(), "bus", "R", "S", "0", 1)
	if len(store.invalidated) != 1 || len(store.firedIDs) != 0 || !store.claimed["r1"] {
		t.Fatalf("invalidated=%v fired=%v claimed=%v", store.invalidated, store.firedIDs, store.claimed)
	}
}
