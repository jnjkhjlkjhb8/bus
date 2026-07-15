package notify

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
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
	finalized                                               map[string]bool
	claimIDs                                                []string
	firedIDs                                                []string
	releasedIDs                                             []string
	releaseErr                                              error
	releaseChanged                                          *bool
	invalidated                                             []string
	rejectCanceledTransitions                               bool
	finalizationDeadlines                                   []time.Duration
	missingFinalizationDeadline                             bool
	invalidateErr                                           error
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
func (s *fakeNotificationStore) claim(ctx context.Context, id string, _ time.Time) (bool, error) {
	s.claimIDs = append(s.claimIDs, id)
	if s.rejectCanceledTransitions && ctx.Err() != nil {
		return false, ctx.Err()
	}
	if s.claimed[id] || s.finalized[id] {
		return false, nil
	}
	s.claimed[id] = true
	return true, nil
}
func (s *fakeNotificationStore) recordFinalizationDeadline(ctx context.Context) {
	deadline, ok := ctx.Deadline()
	if !ok {
		s.missingFinalizationDeadline = true
		return
	}
	s.finalizationDeadlines = append(s.finalizationDeadlines, time.Until(deadline))
}
func (s *fakeNotificationStore) release(ctx context.Context, id string) (bool, error) {
	s.releasedIDs = append(s.releasedIDs, id)
	s.recordFinalizationDeadline(ctx)
	if s.rejectCanceledTransitions && ctx.Err() != nil {
		return false, ctx.Err()
	}
	if s.releaseErr != nil {
		return false, s.releaseErr
	}
	changed := true
	if s.releaseChanged != nil {
		changed = *s.releaseChanged
	}
	if changed {
		s.claimed[id] = false
	}
	return changed, nil
}
func (s *fakeNotificationStore) fired(ctx context.Context, id string, _ time.Time) (bool, error) {
	s.recordFinalizationDeadline(ctx)
	if s.rejectCanceledTransitions && ctx.Err() != nil {
		return false, ctx.Err()
	}
	s.firedIDs = append(s.firedIDs, id)
	s.claimed[id] = false
	if s.finalized == nil {
		s.finalized = make(map[string]bool)
	}
	s.finalized[id] = true
	return true, nil
}
func (s *fakeNotificationStore) invalidate(ctx context.Context, token string) error {
	s.recordFinalizationDeadline(ctx)
	if s.rejectCanceledTransitions && ctx.Err() != nil {
		return ctx.Err()
	}
	s.invalidated = append(s.invalidated, token)
	return s.invalidateErr
}

type fakeFCM struct {
	messages []*messaging.Message
	err      error
	errs     map[string]error
	send     func(context.Context, *messaging.Message) error
}

func (f *fakeFCM) Send(ctx context.Context, m *messaging.Message) error {
	f.messages = append(f.messages, m)
	if f.send != nil {
		return f.send(ctx, m)
	}
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

func TestArrivalsReleasesWithDetachedContextAndStopsAfterParentCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	first := ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S1", Direction: "0", ETASeconds: 60}
	second := ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S2", Direction: "0", ETASeconds: 120}
	store := &fakeNotificationStore{
		claimed:                   map[string]bool{},
		rejectCanceledTransitions: true,
		matches: []arrivalMatch{
			{reminder: arrivalReminder{id: "r1", token: "first", routeType: "bus", routeKey: "R", stopKey: "S1", direction: "0", leadMinutes: 5}, arrival: first},
			{reminder: arrivalReminder{id: "r2", token: "second", routeType: "bus", routeKey: "R", stopKey: "S2", direction: "0", leadMinutes: 5}, arrival: second},
		},
	}
	sender := &fakeFCM{send: func(ctx context.Context, _ *messaging.Message) error {
		cancel()
		return ctx.Err()
	}}

	err := NewDispatcher(store, sender).Arrivals(ctx, []ArrivalEvent{first, second})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("Arrivals() error = %v, want context canceled", err)
	}
	if store.claimed["r1"] || len(store.releasedIDs) != 1 || store.releasedIDs[0] != "r1" {
		t.Fatalf("first reminder remained claimed: claimed=%v released=%v", store.claimed, store.releasedIDs)
	}
	if len(store.claimIDs) != 1 || store.claimIDs[0] != "r1" || len(sender.messages) != 1 {
		t.Fatalf("processed new reminder after cancellation: claims=%v sends=%d", store.claimIDs, len(sender.messages))
	}
	if store.missingFinalizationDeadline || len(store.finalizationDeadlines) != 1 || store.finalizationDeadlines[0] <= 0 || store.finalizationDeadlines[0] > arrivalFinalizationTimeout {
		t.Fatalf("release finalization deadlines = %v missing=%v, want one bounded deadline", store.finalizationDeadlines, store.missingFinalizationDeadline)
	}
}

func TestArrivalsStartsFinalizationDeadlineAfterSendReturns(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	event := ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 60}
	store := &fakeNotificationStore{
		claimed: map[string]bool{}, rejectCanceledTransitions: true,
		matches: []arrivalMatch{{
			reminder: arrivalReminder{id: "r1", token: "token", routeType: "bus", routeKey: "R", stopKey: "S", direction: "0", leadMinutes: 5},
			arrival:  event,
		}},
	}
	timeout := 5 * time.Millisecond
	sender := &fakeFCM{send: func(ctx context.Context, _ *messaging.Message) error {
		time.Sleep(2 * timeout)
		cancel()
		return ctx.Err()
	}}
	dispatcher := NewDispatcher(store, sender)
	dispatcher.finalizationTimeout = timeout

	err := dispatcher.Arrivals(ctx, []ArrivalEvent{event})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("Arrivals() error = %v, want context canceled", err)
	}
	if store.claimed["r1"] || len(store.releasedIDs) != 1 {
		t.Fatalf("reminder remained claimed after slow send: claimed=%v released=%v", store.claimed, store.releasedIDs)
	}
	if store.missingFinalizationDeadline || len(store.finalizationDeadlines) != 1 || store.finalizationDeadlines[0] <= 0 {
		t.Fatalf("release finalization deadlines = %v missing=%v, want deadline starting after send", store.finalizationDeadlines, store.missingFinalizationDeadline)
	}
}

func TestArrivalsMarksFiredWithDetachedContextAfterParentCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	first := ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S1", Direction: "0", ETASeconds: 60}
	second := ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S2", Direction: "0", ETASeconds: 120}
	store := &fakeNotificationStore{
		claimed:                   map[string]bool{},
		rejectCanceledTransitions: true,
		matches: []arrivalMatch{
			{reminder: arrivalReminder{id: "r1", token: "first", routeType: "bus", routeKey: "R", stopKey: "S1", direction: "0", leadMinutes: 5}, arrival: first},
			{reminder: arrivalReminder{id: "r2", token: "second", routeType: "bus", routeKey: "R", stopKey: "S2", direction: "0", leadMinutes: 5}, arrival: second},
		},
	}
	sender := &fakeFCM{send: func(context.Context, *messaging.Message) error {
		cancel()
		return nil
	}}

	err := NewDispatcher(store, sender).Arrivals(ctx, []ArrivalEvent{first, second})
	if !errors.Is(err, context.Canceled) || len(store.firedIDs) != 1 || store.firedIDs[0] != "r1" || store.claimed["r1"] {
		t.Fatalf("error=%v fired=%v claimed=%v, want canceled with r1 finalized", err, store.firedIDs, store.claimed)
	}
	if len(store.claimIDs) != 1 || len(sender.messages) != 1 {
		t.Fatalf("processed new reminder after cancellation: claims=%v sends=%d", store.claimIDs, len(sender.messages))
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
	err := NewDispatcher(store, sender).Arrivals(context.Background(), []ArrivalEvent{{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 1}})
	if !errors.Is(err, sendErr) {
		t.Fatalf("Arrivals() error = %v, want invalid-token send error %v", err, sendErr)
	}
	if len(store.invalidated) != 1 || len(store.releasedIDs) != 1 || len(store.firedIDs) != 0 || store.claimed["r1"] {
		t.Fatalf("invalidated=%v released=%v fired=%v claimed=%v", store.invalidated, store.releasedIDs, store.firedIDs, store.claimed)
	}
}

func TestInvalidTokenFinalizesWithDetachedContextAfterParentCancel(t *testing.T) {
	sendErr := errors.New("invalid token")
	old := isInvalidFCMToken
	isInvalidFCMToken = func(err error) bool { return errors.Is(err, sendErr) }
	t.Cleanup(func() { isInvalidFCMToken = old })
	ctx, cancel := context.WithCancel(context.Background())
	first := ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S1", Direction: "0", ETASeconds: 60}
	second := ArrivalEvent{RouteType: "bus", RouteKey: "R", StopKey: "S2", Direction: "0", ETASeconds: 120}
	store := &fakeNotificationStore{
		claimed: map[string]bool{}, rejectCanceledTransitions: true,
		matches: []arrivalMatch{
			{reminder: arrivalReminder{id: "r1", token: "bad", routeType: "bus", routeKey: "R", stopKey: "S1", direction: "0", leadMinutes: 5}, arrival: first},
			{reminder: arrivalReminder{id: "r2", token: "good", routeType: "bus", routeKey: "R", stopKey: "S2", direction: "0", leadMinutes: 5}, arrival: second},
		},
	}
	sender := &fakeFCM{send: func(context.Context, *messaging.Message) error {
		cancel()
		return sendErr
	}}

	err := NewDispatcher(store, sender).Arrivals(ctx, []ArrivalEvent{first, second})
	if !errors.Is(err, sendErr) || !errors.Is(err, context.Canceled) {
		t.Fatalf("Arrivals() error = %v, want invalid token and context canceled", err)
	}
	if len(store.invalidated) != 1 || len(store.releasedIDs) != 1 || store.claimed["r1"] {
		t.Fatalf("invalidated=%v released=%v claimed=%v", store.invalidated, store.releasedIDs, store.claimed)
	}
	if len(store.claimIDs) != 1 || len(sender.messages) != 1 {
		t.Fatalf("processed new reminder after cancellation: claims=%v sends=%d", store.claimIDs, len(sender.messages))
	}
	if store.missingFinalizationDeadline || len(store.finalizationDeadlines) != 2 {
		t.Fatalf("invalid-token finalization deadlines = %v missing=%v", store.finalizationDeadlines, store.missingFinalizationDeadline)
	}
	for _, remaining := range store.finalizationDeadlines {
		if remaining <= 0 || remaining > arrivalFinalizationTimeout {
			t.Fatalf("invalid-token finalization deadline remaining = %v, want (0, %v]", remaining, arrivalFinalizationTimeout)
		}
	}
}

func TestInvalidTokenReturnsInvalidateAndReleaseFailures(t *testing.T) {
	sendErr := errors.New("invalid token")
	invalidateErr := errors.New("invalidate failed")
	releaseErr := errors.New("release failed")
	old := isInvalidFCMToken
	isInvalidFCMToken = func(err error) bool { return errors.Is(err, sendErr) }
	t.Cleanup(func() { isInvalidFCMToken = old })
	store := &fakeNotificationStore{
		claimed: map[string]bool{}, invalidateErr: invalidateErr, releaseErr: releaseErr,
		reminders:     []arrivalReminder{{id: "r1", token: "bad", leadMinutes: 5}},
		wantRouteType: "bus", wantRouteKey: "R", wantStopKey: "S", wantDirection: "0",
	}
	err := NewDispatcher(store, &fakeFCM{err: sendErr}).Arrivals(context.Background(), []ArrivalEvent{{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 1}})
	if !errors.Is(err, sendErr) || !errors.Is(err, invalidateErr) || !errors.Is(err, releaseErr) {
		t.Fatalf("Arrivals() error = %v, want send/invalidate/release failures", err)
	}
}

func TestInvalidTokenReturnsZeroRowReleaseFailure(t *testing.T) {
	sendErr := errors.New("invalid token")
	changed := false
	old := isInvalidFCMToken
	isInvalidFCMToken = func(err error) bool { return errors.Is(err, sendErr) }
	t.Cleanup(func() { isInvalidFCMToken = old })
	store := &fakeNotificationStore{
		claimed: map[string]bool{}, releaseChanged: &changed,
		reminders:     []arrivalReminder{{id: "r1", token: "bad", leadMinutes: 5}},
		wantRouteType: "bus", wantRouteKey: "R", wantStopKey: "S", wantDirection: "0",
	}
	err := NewDispatcher(store, &fakeFCM{err: sendErr}).Arrivals(context.Background(), []ArrivalEvent{{RouteType: "bus", RouteKey: "R", StopKey: "S", Direction: "0", ETASeconds: 1}})
	if !errors.Is(err, sendErr) || !strings.Contains(err.Error(), "release arrival reminder r1 changed no rows") {
		t.Fatalf("Arrivals() error = %v, want send and zero-row release failures", err)
	}
}
