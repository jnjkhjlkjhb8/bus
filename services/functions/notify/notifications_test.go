package notify

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
)

type fakeNotificationStore struct {
	tokens                                                  []deviceToken
	reminders                                               []arrivalReminder
	matches                                                 []arrivalMatch
	batchCalls                                              int
	batchErr                                                error
	due                                                     []arrivalReminder
	claimed                                                 map[string]bool
	firedIDs                                                []string
	releasedIDs                                             []string
	releaseErr                                              error
	invalidated                                             []string
	wantRouteType, wantRouteKey, wantStopKey, wantDirection string
}

func (s *fakeNotificationStore) activeRemindersForArrivals(_ context.Context, events []ArrivalEvent, _ time.Time) ([]arrivalMatch, error) {
	s.batchCalls++
	if s.matches != nil || s.batchErr != nil {
		return s.matches, s.batchErr
	}
	var matches []arrivalMatch
	for _, event := range events {
		if event.RouteType != s.wantRouteType || event.RouteKey != s.wantRouteKey || event.StopKey != s.wantStopKey || event.Direction != s.wantDirection {
			continue
		}
		for _, reminder := range s.reminders {
			if reminder.routeType == "" {
				reminder.routeType = event.RouteType
			}
			if reminder.routeKey == "" {
				reminder.routeKey = event.RouteKey
			}
			if reminder.stopKey == "" {
				reminder.stopKey = event.StopKey
			}
			if reminder.direction == "" {
				reminder.direction = event.Direction
			}
			matches = append(matches, arrivalMatch{reminder: reminder, arrival: event})
		}
	}
	return matches, nil
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
func (s *fakeNotificationStore) claim(_ context.Context, id string, _ time.Time) (bool, error) {
	if s.claimed[id] {
		return false, nil
	}
	s.claimed[id] = true
	return true, nil
}
func (s *fakeNotificationStore) release(_ context.Context, id string) (bool, error) {
	s.releasedIDs = append(s.releasedIDs, id)
	return s.releaseErr == nil, s.releaseErr
}
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
	errs     map[string]error
}

func (f *fakeFCM) Send(_ context.Context, m *messaging.Message) error {
	f.messages = append(f.messages, m)
	if err, ok := f.errs[m.Token]; ok {
		return err
	}
	return f.err
}

func mustDispatchArrival(t *testing.T, d *Dispatcher, event ArrivalEvent) {
	t.Helper()
	if err := d.Arrivals(context.Background(), []ArrivalEvent{event}); err != nil {
		t.Fatalf("Arrivals() error = %v", err)
	}
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
	mustDispatchArrival(t, d, ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 301})
	if len(sender.messages) != 0 {
		t.Fatal("sent above threshold")
	}
	mustDispatchArrival(t, d, ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 300})
	mustDispatchArrival(t, d, ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 100})
	if len(sender.messages) != 1 || len(store.firedIDs) != 1 {
		t.Fatalf("sent=%d fired=%v", len(sender.messages), store.firedIDs)
	}
	m := sender.messages[0]
	if m.Data["kind"] != "arrival_reminder" || m.Notification.Title != "即將到站" || m.Android == nil || m.APNS == nil {
		t.Fatalf("message=%+v", m)
	}
}

func TestArrivalsMatchesRemindersByCompositeIdentity(t *testing.T) {
	events := []ArrivalEvent{
		{RouteType: "bus", RouteKey: "R", StopKey: "S1", Direction: "0", ETASeconds: 60, ArrivingPlate: "BUS-1"},
		{RouteType: "bus", RouteKey: "R", StopKey: "S2", Direction: "1", ETASeconds: 240, ArrivingPlate: "BUS-2"},
	}
	store := &fakeNotificationStore{
		claimed: map[string]bool{},
		matches: []arrivalMatch{
			{reminder: arrivalReminder{id: "r1", token: "token-1", routeType: "bus", routeKey: "R", stopKey: "S1", direction: "0", leadMinutes: 1}, arrival: events[0]},
			{reminder: arrivalReminder{id: "r2", token: "token-2", routeType: "bus", routeKey: "R", stopKey: "S2", direction: "1", leadMinutes: 5}, arrival: events[1]},
		},
	}
	sender := &fakeFCM{}
	if err := NewDispatcher(store, sender).Arrivals(context.Background(), events); err != nil {
		t.Fatalf("Arrivals() error = %v", err)
	}
	if store.batchCalls != 1 || len(sender.messages) != 2 || len(store.firedIDs) != 2 {
		t.Fatalf("batch calls = %d, sent = %d, fired = %v", store.batchCalls, len(sender.messages), store.firedIDs)
	}
	if sender.messages[0].Token != "token-1" || sender.messages[0].Data["body"] != "預計 1 分鐘後到站" ||
		sender.messages[1].Token != "token-2" || sender.messages[1].Data["body"] != "預計 4 分鐘後到站" {
		t.Fatalf("messages were cross-matched: first=%+v second=%+v", sender.messages[0], sender.messages[1])
	}
}

func TestArrivalPinnedFiresOnlyForMatchingPlate(t *testing.T) {
	store := &fakeNotificationStore{claimed: map[string]bool{}, reminders: []arrivalReminder{{id: "r1", token: "t", routeType: "bus", routeKey: "R", stopKey: "S", direction: "0", leadMinutes: 5, plate: "KKA-1288"}}, wantRouteType: "bus", wantRouteKey: "R", wantStopKey: "S", wantDirection: "0"}
	sender := &fakeFCM{}
	d := NewDispatcher(store, sender)

	// Within lead, but a different bus is arriving: no push.
	mustDispatchArrival(t, d, ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 60, ArrivingPlate: "OTHER-9999"})
	if len(sender.messages) != 0 {
		t.Fatalf("fired for wrong plate: sent=%d", len(sender.messages))
	}
	// The pinned plate arrives: push.
	mustDispatchArrival(t, d, ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 60, ArrivingPlate: "KKA-1288"})
	if len(sender.messages) != 1 || len(store.firedIDs) != 1 {
		t.Fatalf("pinned plate did not fire: sent=%d fired=%v", len(sender.messages), store.firedIDs)
	}
}

func TestArrivalPinnedDoesNotFireWhenArrivingPlateEmpty(t *testing.T) {
	store := &fakeNotificationStore{claimed: map[string]bool{}, reminders: []arrivalReminder{{id: "r1", token: "t", routeType: "bus", routeKey: "R", stopKey: "S", direction: "0", leadMinutes: 5, plate: "KKA-1288"}}, wantRouteType: "bus", wantRouteKey: "R", wantStopKey: "S", wantDirection: "0"}
	sender := &fakeFCM{}
	mustDispatchArrival(t, NewDispatcher(store, sender), ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 60})
	if len(sender.messages) != 0 {
		t.Fatalf("pinned reminder fired on empty arriving plate: sent=%d", len(sender.messages))
	}
}

func TestArrivalUnpinnedIgnoresArrivingPlate(t *testing.T) {
	store := &fakeNotificationStore{claimed: map[string]bool{}, reminders: []arrivalReminder{{id: "r1", token: "t", routeType: "bus", routeKey: "R", stopKey: "S", direction: "0", leadMinutes: 5}}, wantRouteType: "bus", wantRouteKey: "R", wantStopKey: "S", wantDirection: "0"}
	sender := &fakeFCM{}
	mustDispatchArrival(t, NewDispatcher(store, sender), ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 60, ArrivingPlate: "ANY-0000"})
	if len(sender.messages) != 1 {
		t.Fatalf("legacy reminder must fire regardless of plate: sent=%d", len(sender.messages))
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

func TestInterCityRouteAlertsUseCanonicalSubrouteIdentity(t *testing.T) {
	got := routeAlerts("v2/Bus/News/InterCity", []byte(`[
		{"SubRouteUID":"THB902301","Description":"outbound"},
		{"SubRouteUID":"THB902302","Description":"inbound"}
	]`))
	if len(got) != 2 {
		t.Fatalf("alerts = %+v", got)
	}
	for i := range got {
		if got[i].routeKey != "THB9023" {
			t.Fatalf("alert[%d] routeKey = %q, want canonical THB9023", i, got[i].routeKey)
		}
	}
}

func TestInterCityVehicleMQTTUsesRESTCanonicalIdentity(t *testing.T) {
	payload := canonicalInterCityBusPayload("v2/Bus/RealTimeNearStop/InterCity", []byte(`[
		{"PlateNumb":"KKA-1","SubRouteUID":"THB902301","Direction":9},
		{"PlateNumb":"KKA-2","SubRouteUID":"THB902302","Direction":9}
	]`))
	var got []struct {
		SubRouteUID string `json:"SubRouteUID"`
		Direction   uint8  `json:"Direction"`
	}
	if err := json.Unmarshal(payload, &got); err != nil {
		t.Fatalf("decode canonical payload: %v", err)
	}
	if len(got) != 2 || got[0].SubRouteUID != "THB9023" || got[0].Direction != 0 || got[1].SubRouteUID != "THB9023" || got[1].Direction != 1 {
		t.Fatalf("canonical vehicle payload = %+v", got)
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
			mustDispatchArrival(t, d, ArrivalEvent{RouteType: routeType, RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 60})
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
	mustDispatchArrival(t, NewDispatcher(store, sender), ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 1})
	if len(sender.messages) != 0 {
		t.Fatal("sent cancelled reminder")
	}
}

func TestArrivalTransientSendFailureReleasesClaim(t *testing.T) {
	sendErr := errors.New("temporary FCM outage")
	store := &fakeNotificationStore{
		claimed:       map[string]bool{},
		reminders:     []arrivalReminder{{id: "r1", token: "token", leadMinutes: 5}},
		wantRouteType: "bus", wantRouteKey: "R", wantStopKey: "S", wantDirection: "0",
	}
	sender := &fakeFCM{err: sendErr}
	if err := NewDispatcher(store, sender).Arrivals(context.Background(), []ArrivalEvent{{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 60}}); !errors.Is(err, sendErr) {
		t.Fatalf("Arrivals() error = %v, want %v", err, sendErr)
	}
	if len(store.releasedIDs) != 1 || store.releasedIDs[0] != "r1" {
		t.Fatalf("released reminders = %v, want [r1]", store.releasedIDs)
	}
}

func TestArrivalsReturnsTransientSendAndReleaseFailures(t *testing.T) {
	sendErr := errors.New("temporary FCM outage")
	releaseErr := errors.New("release update failed")
	event := ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 60}
	store := &fakeNotificationStore{
		claimed:    map[string]bool{},
		releaseErr: releaseErr,
		matches: []arrivalMatch{{
			reminder: arrivalReminder{id: "r1", token: "token", routeType: "bus", routeKey: "R", stopKey: "S", direction: "0", leadMinutes: 5},
			arrival:  event,
		}},
	}
	err := NewDispatcher(store, &fakeFCM{err: sendErr}).Arrivals(context.Background(), []ArrivalEvent{event})
	if !errors.Is(err, sendErr) || !errors.Is(err, releaseErr) {
		t.Fatalf("Arrivals() error = %v, want send %v and release %v", err, sendErr, releaseErr)
	}
	if len(store.releasedIDs) != 1 || store.releasedIDs[0] != "r1" {
		t.Fatalf("released reminders = %v, want [r1]", store.releasedIDs)
	}
}

func TestArrivalsContinuesBatchAfterTransientSendFailure(t *testing.T) {
	sendErr := errors.New("temporary FCM outage")
	first := ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S1", Direction: "0", ETASeconds: 60}
	second := ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S2", Direction: "0", ETASeconds: 120}
	store := &fakeNotificationStore{
		claimed: map[string]bool{},
		matches: []arrivalMatch{
			{reminder: arrivalReminder{id: "r1", token: "bad", routeType: "bus", routeKey: "R", stopKey: "S1", direction: "0", leadMinutes: 5}, arrival: first},
			{reminder: arrivalReminder{id: "r2", token: "good", routeType: "bus", routeKey: "R", stopKey: "S2", direction: "0", leadMinutes: 5}, arrival: second},
		},
	}
	sender := &fakeFCM{errs: map[string]error{"bad": sendErr}}
	err := NewDispatcher(store, sender).Arrivals(context.Background(), []ArrivalEvent{first, second})
	if !errors.Is(err, sendErr) {
		t.Fatalf("Arrivals() error = %v, want %v", err, sendErr)
	}
	if len(store.releasedIDs) != 1 || store.releasedIDs[0] != "r1" || len(store.firedIDs) != 1 || store.firedIDs[0] != "r2" {
		t.Fatalf("released = %v, fired = %v; later reminder was not completed", store.releasedIDs, store.firedIDs)
	}
}

func TestInvalidTokenCleanupAndAtMostOnce(t *testing.T) {
	sendErr := errors.New("invalid token")
	old := isInvalidFCMToken
	isInvalidFCMToken = func(err error) bool { return errors.Is(err, sendErr) }
	t.Cleanup(func() { isInvalidFCMToken = old })
	store := &fakeNotificationStore{claimed: map[string]bool{}, reminders: []arrivalReminder{{id: "r1", token: "bad", leadMinutes: 5}}, wantRouteType: "bus", wantRouteKey: "R", wantStopKey: "S", wantDirection: "0"}
	sender := &fakeFCM{err: sendErr}
	mustDispatchArrival(t, NewDispatcher(store, sender), ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 1})
	if len(store.invalidated) != 1 || len(store.firedIDs) != 0 || !store.claimed["r1"] {
		t.Fatalf("invalidated=%v fired=%v claimed=%v", store.invalidated, store.firedIDs, store.claimed)
	}
}
