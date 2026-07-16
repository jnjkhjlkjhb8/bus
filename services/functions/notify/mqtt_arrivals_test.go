package notify

import (
	"context"
	"errors"
	"testing"
	"time"
)

// realTimeNearStopFixture mirrors the TDX v2 RealTimeNearStop payload shape:
// full vehicle records with A2EventType 1 = 進站 (entering the stop) and
// 0 = 離站 (leaving it). The 離站 record at TPE43241 shares the matched
// reminder's stop, pinning the polarity branch at the stop that matters.
const realTimeNearStopFixture = `[
	{"PlateNumb":" kka-6157 ","OperatorID":"100","RouteUID":"TPE157462","RouteID":"157462",
	 "RouteName":{"Zh_tw":"307","En":"307"},"SubRouteUID":"TPE157462","SubRouteID":"157462",
	 "Direction":0,"StopUID":"TPE43241","StopID":"43241","StopName":{"Zh_tw":"民生社區","En":"Minsheng Community"},
	 "StopSequence":12,"DutyStatus":0,"BusStatus":0,"A2EventType":1,
	 "GPSTime":"2026-07-16T08:10:00+08:00","SrcUpdateTime":"2026-07-16T08:10:05+08:00","UpdateTime":"2026-07-16T08:10:06+08:00"},
	{"PlateNumb":"KKA-9999","SubRouteUID":"TPE157462","Direction":0,"StopUID":"TPE43240","A2EventType":0},
	{"PlateNumb":"KKA-8888","SubRouteUID":"TPE157462","Direction":0,"StopUID":"TPE43241","A2EventType":0},
	{"PlateNumb":"KKA-0000","SubRouteUID":"TPE157462","Direction":0,"A2EventType":1},
	{"PlateNumb":"KKA-1111","SubRouteUID":"","Direction":0,"StopUID":"TPE43242","A2EventType":1},
	{"PlateNumb":"KKA-2222","SubRouteUID":"TPE157462","StopUID":"TPE43243","A2EventType":1}
]`

func TestNearStopArrivalEventsDerivesEnteringStopOnly(t *testing.T) {
	events := nearStopArrivalEvents("v2/Bus/RealTimeNearStop/City/Taipei/157462", []byte(realTimeNearStopFixture))
	if len(events) != 1 {
		t.Fatalf("events = %+v, want exactly the one entering-stop record with full identity", events)
	}
	want := ArrivalEvent{
		RouteType: "bus", RouteKey: "TPE157462", StopKey: "TPE43241",
		Direction: "0", ETASeconds: 0, ArrivingPlate: "KKA-6157",
	}
	if events[0] != want {
		t.Fatalf("event = %+v, want %+v", events[0], want)
	}
}

func TestNearStopArrivalEventsAcceptsSingleObject(t *testing.T) {
	events := nearStopArrivalEvents("v2/Bus/RealTimeNearStop/City/Taipei/157462",
		[]byte(`{"PlateNumb":"AAA-1","SubRouteUID":"TPE1","Direction":1,"StopUID":"TPE2","A2EventType":1}`))
	if len(events) != 1 || events[0].Direction != "1" || events[0].RouteKey != "TPE1" || events[0].StopKey != "TPE2" {
		t.Fatalf("events = %+v, want one event from the single-object payload", events)
	}
}

// TestNearStopArrivalEventsInterCityUsesCanonicalIdentity runs the payload
// through the same canonicalization step mqtthandle applies before dispatch,
// so InterCity events carry the canonical subroute+direction identity that
// stored reminders and the cron dispatch path key on.
func TestNearStopArrivalEventsInterCityUsesCanonicalIdentity(t *testing.T) {
	topic := "v2/Bus/RealTimeNearStop/InterCity"
	payload := canonicalInterCityBusPayload(topic, []byte(
		`[{"PlateNumb":"KKA-1","SubRouteUID":"THB902302","Direction":9,"StopUID":"THB123","A2EventType":1}]`))
	events := nearStopArrivalEvents(topic, payload)
	if len(events) != 1 || events[0].RouteKey != "THB9023" || events[0].Direction != "1" {
		t.Fatalf("events = %+v, want canonical THB9023 direction 1", events)
	}
}

func TestNearStopArrivalEventsIgnoresOtherTopicsAndBadPayloads(t *testing.T) {
	if got := nearStopArrivalEvents("v2/Bus/News/City/Taipei", []byte(realTimeNearStopFixture)); got != nil {
		t.Fatalf("non-NearStop topic derived events: %+v", got)
	}
	if got := nearStopArrivalEvents("v2/Bus/RealTimeNearStop/City/Taipei/1", []byte(`not json`)); got != nil {
		t.Fatalf("malformed payload derived events: %+v", got)
	}
}

// TestDispatchNearStopArrivalsSwallowsDispatchErrors guards the MQTT handler
// contract: a failing reminder lookup is logged and absorbed — the cache path
// and the handler's ack must never observe it.
func TestDispatchNearStopArrivalsSwallowsDispatchErrors(t *testing.T) {
	store := &fakeNotificationStore{claimed: map[string]bool{}, activeBus: true, batchErr: errors.New("db down")}
	dispatcher := NewDispatcher(store, &fakeFCM{})
	dispatchNearStopArrivals("v2/Bus/RealTimeNearStop/City/Taipei/157462", []byte(realTimeNearStopFixture), dispatcher)
	if store.batchCalls != 1 {
		t.Fatalf("batchCalls = %d, want 1 (events reached the dispatcher despite the error)", store.batchCalls)
	}
	// A nil dispatcher (push disabled) must be equally safe.
	dispatchNearStopArrivals("v2/Bus/RealTimeNearStop/City/Taipei/157462", []byte(realTimeNearStopFixture), nil)
}

func TestDispatchNearStopArrivalsSendsMatchedReminder(t *testing.T) {
	store := &fakeNotificationStore{
		claimed:       map[string]bool{},
		activeBus:     true,
		reminders:     []arrivalReminder{{id: "r1", token: "t", leadMinutes: 5}},
		wantRouteType: "bus", wantRouteKey: "TPE157462", wantStopKey: "TPE43241", wantDirection: "0",
	}
	sender := &fakeFCM{}
	dispatcher := NewDispatcher(store, sender)
	dispatchNearStopArrivals("v2/Bus/RealTimeNearStop/City/Taipei/157462", []byte(realTimeNearStopFixture), dispatcher)
	if len(sender.messages) != 1 {
		t.Fatalf("sent = %d, want 1 push for the entering-stop event", len(sender.messages))
	}
	if len(store.firedIDs) != 1 || store.firedIDs[0] != "r1" {
		t.Fatalf("firedIDs = %v, want [r1]", store.firedIDs)
	}
	// The MQTT trigger's ETA 0 renders as the entering-stop copy, not
	// 「預計 0 分鐘後到站」.
	if body := sender.messages[0].Notification.Body; body != "即將進站" {
		t.Fatalf("push body = %q, want 即將進站 for a zero-ETA near-stop event", body)
	}
}

// TestDispatchNearStopArrivalsGateSkipsPostgresWhenNoReminders covers the
// firehose pre-gate: with no active bus reminders anywhere, a near-stop
// message must cost one cached existence probe, not a reminder query.
func TestDispatchNearStopArrivalsGateSkipsPostgresWhenNoReminders(t *testing.T) {
	store := &fakeNotificationStore{claimed: map[string]bool{}, activeBus: false}
	dispatcher := NewDispatcher(store, &fakeFCM{})
	for range 3 {
		dispatchNearStopArrivals("v2/Bus/RealTimeNearStop/City/Taipei/157462", []byte(realTimeNearStopFixture), dispatcher)
	}
	if store.batchCalls != 0 {
		t.Fatalf("batchCalls = %d, want 0 (gate closed, Postgres reminder query skipped)", store.batchCalls)
	}
	if store.activeBusCalls != 1 {
		t.Fatalf("activeBusCalls = %d, want 1 (probe cached within its TTL)", store.activeBusCalls)
	}
}

func TestHasBusArrivalWorkRefreshesAfterTTL(t *testing.T) {
	store := &fakeNotificationStore{claimed: map[string]bool{}, activeBus: false}
	dispatcher := NewDispatcher(store, &fakeFCM{})
	current := time.Unix(1_800_000_000, 0)
	dispatcher.now = func() time.Time { return current }

	if dispatcher.hasBusArrivalWork(context.Background()) {
		t.Fatal("gate open with no active reminders")
	}
	// Within the TTL the cached answer is reused, even after it changed in the
	// database.
	store.activeBus = true
	current = current.Add(busReminderFlagTTL - time.Second)
	if dispatcher.hasBusArrivalWork(context.Background()) {
		t.Fatal("gate refreshed before the TTL elapsed")
	}
	// Past the TTL the flag is re-probed and the new reminder is seen.
	current = current.Add(2 * time.Second)
	if !dispatcher.hasBusArrivalWork(context.Background()) {
		t.Fatal("gate stayed closed after TTL expiry with an active reminder")
	}
	if store.activeBusCalls != 2 {
		t.Fatalf("activeBusCalls = %d, want 2 (initial probe + one post-TTL refresh)", store.activeBusCalls)
	}
}

// TestHasBusArrivalWorkFailsOpenOnProbeError: a database blip during the
// existence probe must not suppress deliveries — the gate opens and the
// result stays uncached so the next check re-probes.
func TestHasBusArrivalWorkFailsOpenOnProbeError(t *testing.T) {
	store := &fakeNotificationStore{claimed: map[string]bool{}, activeBusErr: errors.New("db down")}
	dispatcher := NewDispatcher(store, &fakeFCM{})
	if !dispatcher.hasBusArrivalWork(context.Background()) {
		t.Fatal("gate closed on probe error — a blip would suppress deliveries")
	}
	store.activeBusErr = nil
	store.activeBus = true
	if !dispatcher.hasBusArrivalWork(context.Background()) {
		t.Fatal("gate closed after probe recovery")
	}
	if store.activeBusCalls != 2 {
		t.Fatalf("activeBusCalls = %d, want 2 (error result not cached)", store.activeBusCalls)
	}
}

// TestMQTTArrivalDispatchStaysUnderReclaimBound extends the reclaim-safety
// argument to the MQTT trigger: its dispatch bound plus the finalization
// window must stay below ReminderClaimTimeout, or a reclaimer could take a
// row whose MQTT-triggered send is still in flight and double-send it.
func TestMQTTArrivalDispatchStaysUnderReclaimBound(t *testing.T) {
	if mqttArrivalDispatchTimeout+ArrivalFinalizationTimeout >= ReminderClaimTimeout {
		t.Fatalf(
			"mqttArrivalDispatchTimeout (%v) + ArrivalFinalizationTimeout (%v) must stay below ReminderClaimTimeout (%v)",
			mqttArrivalDispatchTimeout, ArrivalFinalizationTimeout, ReminderClaimTimeout,
		)
	}
}
