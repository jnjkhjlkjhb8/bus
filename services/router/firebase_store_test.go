package main

import (
	"context"
	"testing"
	"time"

	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	pgxmock "github.com/pashagolub/pgxmock/v4"
)

func TestFirebaseStoreSQL(t *testing.T) {
	ctx := context.Background()
	mock, err := pgxmock.NewPool()
	if err != nil {
		t.Fatal(err)
	}
	defer mock.Close()
	store := &firebaseStore{db: mock}
	secretHash := []byte("01234567890123456789012345678901")

	identity := &pb.DeviceIdentity{InstallId: "install-1", FcmToken: "token-1", Platform: "android", AppVersion: "1.0"}
	prefs := &pb.DevicePrefs{PushEnabled: true}
	mock.ExpectExec("INSERT INTO firebase_device.*WHERE firebase_device.install_secret_hash = EXCLUDED.install_secret_hash").
		WithArgs("install-1", "token-1", "android", "1.0", true, secretHash).
		WillReturnResult(pgxmock.NewResult("INSERT", 1))
	if _, authorized, err := store.UpsertDevice(ctx, identity, prefs, secretHash); err != nil || !authorized {
		t.Fatal(err)
	}
	mock.ExpectExec("INSERT INTO firebase_device.*WHERE firebase_device.install_secret_hash = EXCLUDED.install_secret_hash").
		WithArgs("install-1", "token-1", "android", "1.0", true, []byte("wrong")).
		WillReturnResult(pgxmock.NewResult("INSERT", 0))
	if _, authorized, err := store.UpsertDevice(ctx, identity, prefs, []byte("wrong")); err != nil || authorized {
		t.Fatalf("conflicting upsert authorized=%v error=%v", authorized, err)
	}

	mock.ExpectQuery("SELECT install_secret_hash FROM firebase_device").
		WithArgs("install-1").
		WillReturnRows(pgxmock.NewRows([]string{"install_secret_hash"}).AddRow(secretHash))
	if authorized, err := store.AuthorizeInstall(ctx, "install-1", secretHash); err != nil || !authorized {
		t.Fatalf("AuthorizeInstall() = (%v, %v)", authorized, err)
	}
	mock.ExpectQuery("SELECT install_secret_hash FROM firebase_device").
		WithArgs("install-1").
		WillReturnRows(pgxmock.NewRows([]string{"install_secret_hash"}).AddRow(secretHash))
	if authorized, err := store.AuthorizeInstall(ctx, "install-1", []byte("fedcba9876543210fedcba9876543210")); err != nil || authorized {
		t.Fatalf("wrong-secret AuthorizeInstall() = (%v, %v)", authorized, err)
	}
	mock.ExpectQuery("SELECT platform, app_version.*FROM firebase_device").
		WithArgs("install-1").
		WillReturnRows(pgxmock.NewRows([]string{
			"platform", "app_version", "push_enabled",
		}).AddRow("android", "1.0", true))
	state, err := store.ListDeviceState(ctx, "install-1")
	if err != nil || state.GetIdentity().GetFcmToken() != "" {
		t.Fatalf("ListDeviceState() = (%v, %v)", state, err)
	}

	// The whole scope goes down as two parallel arrays in one statement, so the
	// delete of what is gone and the insert of what is new cannot half-apply.
	mock.ExpectExec("DELETE FROM firebase_route_subscription.*INSERT INTO firebase_route_subscription").
		WithArgs("install-1", []string{"bus", "tra"}, []string{"route-1", "*"}).
		WillReturnResult(pgxmock.NewResult("INSERT", 2))
	if err := store.ReplaceRouteSubscriptions(ctx, "install-1", []*pb.RouteSubscription{
		{RouteType: "bus", RouteKey: "route-1"},
		{RouteType: "tra", RouteKey: "*"},
	}); err != nil {
		t.Fatal(err)
	}
	// An empty scope still runs: the delete is what clears the device.
	mock.ExpectExec("DELETE FROM firebase_route_subscription.*INSERT INTO firebase_route_subscription").
		WithArgs("install-1", []string{}, []string{}).
		WillReturnResult(pgxmock.NewResult("INSERT", 0))
	if err := store.ReplaceRouteSubscriptions(ctx, "install-1", nil); err != nil {
		t.Fatal(err)
	}

	expires := time.Unix(1_800_003_600, 0)
	reminder := FirebaseArrivalReminder{
		ReminderID: "reminder-1", InstallID: "install-1", RouteType: "bus", RouteKey: "route-1",
		StopKey: "stop-1", Direction: "0", LeadMinutes: 5, ExpiresAt: expires, Status: ReminderPending, Plate: "AAA-1234",
	}
	mock.ExpectExec("INSERT INTO firebase_arrival_reminder").
		WithArgs("reminder-1", "install-1", "bus", "route-1", "stop-1", "0", int32(5), (*time.Time)(nil), expires, ReminderPending, "AAA-1234").
		WillReturnResult(pgxmock.NewResult("INSERT", 1))
	if err := store.CreateArrivalReminder(ctx, reminder); err != nil {
		t.Fatal(err)
	}

	mock.ExpectExec("UPDATE firebase_arrival_reminder[[:space:]]+SET status = 'cancelled'.*install_id = \\$2 AND status = 'pending'").
		WithArgs("reminder-1", "install-1").
		WillReturnResult(pgxmock.NewResult("UPDATE", 1))
	cancelled, err := store.CancelArrivalReminder(ctx, "reminder-1", "install-1")
	if err != nil || !cancelled {
		t.Fatalf("CancelArrivalReminder() = (%v, %v)", cancelled, err)
	}
	mock.ExpectExec("UPDATE firebase_arrival_reminder[[:space:]]+SET status = 'cancelled'.*install_id = \\$2 AND status = 'pending'").
		WithArgs("reminder-1", "other-install").
		WillReturnResult(pgxmock.NewResult("UPDATE", 0))
	cancelled, err = store.CancelArrivalReminder(ctx, "reminder-1", "other-install")
	if err != nil || cancelled {
		t.Fatalf("wrong-owner CancelArrivalReminder() = (%v, %v)", cancelled, err)
	}

	now := time.Unix(1_800_000_000, 0)
	mock.ExpectQuery("FROM firebase_arrival_reminder r.*r.status = 'pending'.*r.expires_at > \\$5").
		WithArgs("bus", "route-1", "stop-1", "0", now).
		WillReturnRows(pgxmock.NewRows([]string{
			"reminder_id", "install_id", "fcm_token", "route_type", "route_key", "stop_key", "direction", "lead_minutes", "fire_at", "expires_at", "status",
		}).AddRow("reminder-1", "install-1", "token-1", "bus", "route-1", "stop-1", "0", int32(5), nil, expires, ReminderPending))
	active, err := store.ListActiveArrivalReminders(ctx, "bus", "route-1", "stop-1", "0", now)
	if err != nil || len(active) != 1 || active[0].Token != "token-1" || active[0].LeadMinutes != 5 {
		t.Fatalf("ListActiveArrivalReminders() = (%#v, %v)", active, err)
	}
	mock.ExpectQuery("FROM firebase_arrival_reminder r.*r.status = 'pending'.*r.expires_at > \\$5").
		WithArgs("bus", "route-1", "stop-1", "0", now).
		WillReturnRows(pgxmock.NewRows([]string{
			"reminder_id", "install_id", "fcm_token", "route_type", "route_key", "stop_key", "direction", "lead_minutes", "fire_at", "expires_at", "status",
		}).AddRow("reminder-1", "install-1", "token-1", "bus", "route-1", "stop-1", "0", "invalid", nil, expires, ReminderPending))
	if _, err := store.ListActiveArrivalReminders(ctx, "bus", "route-1", "stop-1", "0", now); err == nil {
		t.Fatal("ListActiveArrivalReminders() scan error = nil")
	}

	mock.ExpectExec("UPDATE firebase_arrival_reminder SET status = 'sending'.*status = 'pending'.*expires_at > \\$2").
		WithArgs("reminder-1", now).
		WillReturnResult(pgxmock.NewResult("UPDATE", 0))
	claimed, err := store.ClaimArrivalReminder(ctx, "reminder-1", now)
	if err != nil || claimed {
		t.Fatalf("cancel-first ClaimArrivalReminder() = (%v, %v)", claimed, err)
	}

	mock.ExpectExec("UPDATE firebase_arrival_reminder SET status = 'sending'.*status = 'pending'.*expires_at > \\$2").
		WithArgs("reminder-2", now).
		WillReturnResult(pgxmock.NewResult("UPDATE", 1))
	claimed, err = store.ClaimArrivalReminder(ctx, "reminder-2", now)
	if err != nil || !claimed {
		t.Fatalf("ClaimArrivalReminder() = (%v, %v)", claimed, err)
	}
	mock.ExpectExec("UPDATE firebase_arrival_reminder SET status = 'sending'.*status = 'pending'.*expires_at > \\$2").
		WithArgs("reminder-2", now).
		WillReturnResult(pgxmock.NewResult("UPDATE", 0))
	claimed, err = store.ClaimArrivalReminder(ctx, "reminder-2", now)
	if err != nil || claimed {
		t.Fatalf("duplicate ClaimArrivalReminder() = (%v, %v)", claimed, err)
	}
	mock.ExpectExec("UPDATE firebase_arrival_reminder SET status = 'pending'.*status = 'sending'").
		WithArgs("reminder-2").
		WillReturnResult(pgxmock.NewResult("UPDATE", 1))
	if released, err := store.ReleaseArrivalReminder(ctx, "reminder-2"); err != nil || !released {
		t.Fatalf("ReleaseArrivalReminder() = (%v, %v)", released, err)
	}
	mock.ExpectExec("UPDATE firebase_arrival_reminder SET status = 'sending'.*status = 'pending'.*expires_at > \\$2").
		WithArgs("reminder-2", now).
		WillReturnResult(pgxmock.NewResult("UPDATE", 1))
	if claimed, err = store.ClaimArrivalReminder(ctx, "reminder-2", now); err != nil || !claimed {
		t.Fatalf("second ClaimArrivalReminder() = (%v, %v)", claimed, err)
	}

	firedAt := now.Add(time.Minute)
	mock.ExpectExec("UPDATE firebase_arrival_reminder SET status = 'fired', fired_at = \\$2.*status = 'sending'").
		WithArgs("reminder-2", firedAt).
		WillReturnResult(pgxmock.NewResult("UPDATE", 1))
	if fired, err := store.MarkReminderFired(ctx, "reminder-2", firedAt); err != nil || !fired {
		t.Fatalf("MarkReminderFired() = (%v, %v)", fired, err)
	}
	mock.ExpectExec("UPDATE firebase_arrival_reminder SET status = 'fired', fired_at = \\$2.*status = 'sending'").
		WithArgs("reminder-2", firedAt).
		WillReturnResult(pgxmock.NewResult("UPDATE", 0))
	if fired, err := store.MarkReminderFired(ctx, "reminder-2", firedAt); err != nil || fired {
		t.Fatalf("duplicate MarkReminderFired() = (%v, %v)", fired, err)
	}

	mock.ExpectExec("UPDATE firebase_device SET fcm_token = '', push_enabled = FALSE.*WHERE fcm_token = \\$1").
		WithArgs("token-1").
		WillReturnResult(pgxmock.NewResult("UPDATE", 1))
	if deleted, err := store.DeleteInvalidToken(ctx, "token-1"); err != nil || !deleted {
		t.Fatalf("DeleteInvalidToken() = (%v, %v)", deleted, err)
	}

	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatal(err)
	}
}
