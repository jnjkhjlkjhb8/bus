package main

import (
	"context"
	"crypto/sha256"
	"errors"
	"strings"
	"testing"
	"time"

	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

const (
	testInstallSecret  = "0123456789abcdef0123456789abcdef"
	wrongInstallSecret = "fedcba9876543210fedcba9876543210"
)

type fakeFirebasePersistence struct {
	device        *pb.DeviceState
	subscription  *pb.RouteSubscriptionRequest
	reminder      firebaseArrivalReminder
	cancelledID   string
	cancelledBy   string
	secretHash    []byte
	cancelMissing bool
}

func (f *fakeFirebasePersistence) UpsertDevice(_ context.Context, identity *pb.DeviceIdentity, prefs *pb.DevicePrefs, secretHash []byte) (*pb.DeviceState, bool, error) {
	if len(f.secretHash) != 0 && string(f.secretHash) != string(secretHash) {
		return nil, false, nil
	}
	f.secretHash = append([]byte(nil), secretHash...)
	f.device = &pb.DeviceState{Identity: identity, Prefs: prefs}
	return f.device, true, nil
}

func (f *fakeFirebasePersistence) AuthorizeInstall(_ context.Context, installID string, secretHash []byte) (bool, error) {
	return f.device != nil && f.device.Identity.InstallId == installID && string(f.secretHash) == string(secretHash), nil
}

func (f *fakeFirebasePersistence) SetRouteSubscription(_ context.Context, installID, routeType, routeKey string, enabled bool) error {
	f.subscription = &pb.RouteSubscriptionRequest{InstallId: installID, RouteType: routeType, RouteKey: routeKey, Enabled: enabled}
	return nil
}

func (f *fakeFirebasePersistence) CreateArrivalReminder(_ context.Context, reminder firebaseArrivalReminder) error {
	f.reminder = reminder
	return nil
}

func (f *fakeFirebasePersistence) CancelArrivalReminder(_ context.Context, reminderID, installID string) (bool, error) {
	f.cancelledID, f.cancelledBy = reminderID, installID
	return !f.cancelMissing, nil
}

func (f *fakeFirebasePersistence) ListDeviceState(_ context.Context, installID string) (*pb.DeviceState, error) {
	if f.device == nil || f.device.Identity.InstallId != installID {
		return nil, errFirebaseNotFound
	}
	return f.device, nil
}

func TestFirebaseServiceDeviceSubscriptionAndReminder(t *testing.T) {
	store := &fakeFirebasePersistence{}
	now := time.Unix(1_800_000_000, 0)
	server := &FirebaseServer{store: store, now: func() time.Time { return now }}

	ctx := installationContext("install-1", testInstallSecret)
	state, err := server.UpsertDevice(ctx, &pb.UpsertDeviceRequest{
		Identity: &pb.DeviceIdentity{InstallId: "install-1", FcmToken: "token", Platform: "android", AppVersion: "1.0.0"},
		Prefs:    &pb.DevicePrefs{PushEnabled: true},
	})
	if err != nil || state.GetIdentity().GetInstallId() != "install-1" {
		t.Fatalf("UpsertDevice() = (%v, %v)", state, err)
	}
	wantHash := sha256.Sum256([]byte(testInstallSecret))
	if string(store.secretHash) != string(wantHash[:]) || state.GetIdentity().GetFcmToken() != "" {
		t.Fatalf("secret hash or response token is unsafe: hash=%x state=%v", store.secretHash, state)
	}
	store.device.Identity.FcmToken = "private-token"
	listed, err := server.ListDeviceState(ctx, &pb.DeviceRequest{InstallId: "install-1"})
	if err != nil || listed.GetIdentity().GetFcmToken() != "" {
		t.Fatalf("ListDeviceState() = (%v, %v), token must be blank", listed, err)
	}

	for _, enabled := range []bool{true, false} {
		_, err = server.SetRouteSubscription(ctx, &pb.RouteSubscriptionRequest{
			InstallId: "install-1", RouteType: "bus", RouteKey: "route-1", Enabled: enabled,
		})
		if err != nil || store.subscription.GetEnabled() != enabled {
			t.Fatalf("SetRouteSubscription(%v) error = %v, stored = %v", enabled, err, store.subscription)
		}
	}

	expires := now.Add(time.Hour)
	reminder, err := server.CreateArrivalReminder(ctx, &pb.CreateArrivalReminderRequest{
		InstallId: "install-1", RouteType: "bus", RouteKey: "route-1", StopKey: "stop-1",
		Direction: "0", LeadMinutes: 5, ExpiresAtUnix: expires.Unix(),
	})
	if err != nil {
		t.Fatalf("CreateArrivalReminder() error = %v", err)
	}
	if reminder.GetReminderId() == "" || store.reminder.Status != reminderPending || store.reminder.FireAt != nil || !store.reminder.ExpiresAt.Equal(expires) {
		t.Fatalf("stored reminder = %#v, response = %v", store.reminder, reminder)
	}

	_, err = server.CancelArrivalReminder(ctx, &pb.CancelArrivalReminderRequest{ReminderId: reminder.ReminderId, InstallId: "install-1"})
	if err != nil || store.cancelledID != reminder.ReminderId || store.cancelledBy != "install-1" {
		t.Fatalf("CancelArrivalReminder() error = %v, id = %q, owner = %q", err, store.cancelledID, store.cancelledBy)
	}

	// Rail reminders fire on a schedule: the server derives fire_at = arrival
	// (expires_at) − lead so the reminder cron can dispatch it without a live ETA.
	railExpires := now.Add(time.Hour)
	railReminder, err := server.CreateArrivalReminder(ctx, &pb.CreateArrivalReminderRequest{
		InstallId: "install-1", RouteType: "tra", RouteKey: "1120", StopKey: "南港",
		Direction: "0", LeadMinutes: 3, ExpiresAtUnix: railExpires.Unix(),
	})
	if err != nil {
		t.Fatalf("CreateArrivalReminder(tra) error = %v", err)
	}
	wantFireAt := railExpires.Add(-3 * time.Minute)
	if railReminder.GetReminderId() == "" || store.reminder.RouteType != "tra" ||
		store.reminder.FireAt == nil || !store.reminder.FireAt.Equal(wantFireAt) {
		t.Fatalf("stored rail reminder = %#v", store.reminder)
	}
}

func TestFirebaseServiceNormalizesArrivalReminderPlate(t *testing.T) {
	store := &fakeFirebasePersistence{
		device: &pb.DeviceState{Identity: &pb.DeviceIdentity{InstallId: "install-1"}},
	}
	wantHash := sha256.Sum256([]byte(testInstallSecret))
	store.secretHash = wantHash[:]
	now := time.Unix(1_800_000_000, 0)
	server := &FirebaseServer{store: store, now: func() time.Time { return now }}

	reminder, err := server.CreateArrivalReminder(
		installationContext("install-1", testInstallSecret),
		&pb.CreateArrivalReminderRequest{
			InstallId: "install-1", RouteType: "bus", RouteKey: "route-1", StopKey: "stop-1",
			Direction: "0", LeadMinutes: 5, ExpiresAtUnix: now.Add(time.Hour).Unix(), Plate: "  kka-1288  ",
		},
	)
	if err != nil {
		t.Fatalf("CreateArrivalReminder() error = %v", err)
	}
	if store.reminder.Plate != "KKA-1288" || reminder.GetPlate() != "KKA-1288" {
		t.Fatalf("stored plate = %q, response plate = %q, want normalized KKA-1288", store.reminder.Plate, reminder.GetPlate())
	}
}

func TestFirebaseServiceRejectsInvalidArrivalReminderPlate(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)
	for _, plate := range []string{"KKA/1288", "-KKA1288", "KKA--1288", strings.Repeat("A", 33)} {
		t.Run(plate, func(t *testing.T) {
			store := &fakeFirebasePersistence{}
			server := &FirebaseServer{store: store, now: func() time.Time { return now }}
			_, err := server.CreateArrivalReminder(context.Background(), &pb.CreateArrivalReminderRequest{
				InstallId: "install-1", RouteType: "bus", RouteKey: "route-1", StopKey: "stop-1",
				Direction: "0", LeadMinutes: 5, ExpiresAtUnix: now.Add(time.Hour).Unix(), Plate: plate,
			})
			if status.Code(err) != codes.InvalidArgument {
				t.Fatalf("plate %q code = %v, want %v", plate, status.Code(err), codes.InvalidArgument)
			}
			if store.reminder.ReminderID != "" {
				t.Fatalf("invalid plate %q reached persistence: %#v", plate, store.reminder)
			}
		})
	}
}

func TestFirebaseServiceRejectsWrongInstallationCredential(t *testing.T) {
	store := &fakeFirebasePersistence{}
	server := &FirebaseServer{store: store, now: time.Now}
	request := &pb.UpsertDeviceRequest{
		Identity: &pb.DeviceIdentity{InstallId: "install-1", Platform: "ios"},
		Prefs:    &pb.DevicePrefs{},
	}
	if _, err := server.UpsertDevice(installationContext("install-1", testInstallSecret), request); err != nil {
		t.Fatal(err)
	}
	if _, err := server.UpsertDevice(installationContext("install-1", wrongInstallSecret), request); status.Code(err) != codes.PermissionDenied {
		t.Fatalf("upsert conflict code = %v, want %v", status.Code(err), codes.PermissionDenied)
	}
	_, err := server.SetRouteSubscription(installationContext("install-1", wrongInstallSecret), &pb.RouteSubscriptionRequest{
		InstallId: "install-1", RouteType: "bus", RouteKey: "route-1", Enabled: true,
	})
	if status.Code(err) != codes.PermissionDenied {
		t.Fatalf("wrong secret code = %v, want %v", status.Code(err), codes.PermissionDenied)
	}
	_, err = server.SetRouteSubscription(installationContext("other-install", testInstallSecret), &pb.RouteSubscriptionRequest{
		InstallId: "install-1", RouteType: "bus", RouteKey: "route-1", Enabled: true,
	})
	if status.Code(err) != codes.PermissionDenied {
		t.Fatalf("cross-install code = %v, want %v", status.Code(err), codes.PermissionDenied)
	}
}

// The credential gate must reject requests that carry no installation metadata
// at all, or a secret below the 32-byte minimum — both would otherwise let an
// anonymous caller mutate another install's subscriptions and reminders.
func TestFirebaseServiceRejectsMissingOrShortCredentials(t *testing.T) {
	store := &fakeFirebasePersistence{}
	server := &FirebaseServer{store: store, now: time.Now}
	if _, err := server.UpsertDevice(installationContext("install-1", testInstallSecret), &pb.UpsertDeviceRequest{
		Identity: &pb.DeviceIdentity{InstallId: "install-1", Platform: "ios"},
		Prefs:    &pb.DevicePrefs{},
	}); err != nil {
		t.Fatal(err)
	}

	subscription := &pb.RouteSubscriptionRequest{InstallId: "install-1", RouteType: "bus", RouteKey: "route-1", Enabled: true}
	tests := []struct {
		name string
		ctx  context.Context
	}{
		{"no metadata", context.Background()},
		{"secret below minimum length", installationContext("install-1", "short-secret")},
		{"metadata install mismatch", installationContext("install-2", testInstallSecret)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := server.SetRouteSubscription(tt.ctx, subscription)
			if status.Code(err) != codes.PermissionDenied {
				t.Fatalf("code = %v, want %v", status.Code(err), codes.PermissionDenied)
			}
			_, err = server.CancelArrivalReminder(tt.ctx, &pb.CancelArrivalReminderRequest{ReminderId: "id", InstallId: "install-1"})
			if status.Code(err) != codes.PermissionDenied {
				t.Fatalf("cancel code = %v, want %v", status.Code(err), codes.PermissionDenied)
			}
		})
	}
	if store.subscription != nil || store.cancelledID != "" {
		t.Fatalf("store mutated by unauthorized calls: sub=%v cancelled=%q", store.subscription, store.cancelledID)
	}
}

// Cancelling a reminder that is not pending for this install (already fired,
// cancelled, or owned by someone else) must surface NotFound, not silent success.
func TestFirebaseServiceCancelReminderNotFound(t *testing.T) {
	store := &fakeFirebasePersistence{cancelMissing: true}
	server := &FirebaseServer{store: store, now: time.Now}
	ctx := installationContext("install-1", testInstallSecret)
	if _, err := server.UpsertDevice(ctx, &pb.UpsertDeviceRequest{
		Identity: &pb.DeviceIdentity{InstallId: "install-1", Platform: "ios"},
		Prefs:    &pb.DevicePrefs{},
	}); err != nil {
		t.Fatal(err)
	}
	_, err := server.CancelArrivalReminder(ctx, &pb.CancelArrivalReminderRequest{ReminderId: "gone", InstallId: "install-1"})
	if status.Code(err) != codes.NotFound {
		t.Fatalf("code = %v, want %v", status.Code(err), codes.NotFound)
	}
}

func installationContext(installID, secret string) context.Context {
	return metadata.NewIncomingContext(context.Background(), metadata.Pairs(
		installIDMetadataKey, installID,
		installSecretMetadataKey, secret,
	))
}

func TestFirebaseServiceValidation(t *testing.T) {
	server := &FirebaseServer{store: &fakeFirebasePersistence{}, now: time.Now}
	tests := []struct {
		name string
		call func() error
		want codes.Code
	}{
		{"missing identity", func() error {
			_, err := server.UpsertDevice(context.Background(), &pb.UpsertDeviceRequest{})
			return err
		}, codes.InvalidArgument},
		{"bad platform", func() error {
			_, err := server.UpsertDevice(context.Background(), &pb.UpsertDeviceRequest{Identity: &pb.DeviceIdentity{InstallId: "a", FcmToken: "b", Platform: "web"}, Prefs: &pb.DevicePrefs{}})
			return err
		}, codes.InvalidArgument},
		{"missing route", func() error {
			_, err := server.SetRouteSubscription(context.Background(), &pb.RouteSubscriptionRequest{InstallId: "a"})
			return err
		}, codes.InvalidArgument},
		{"unsupported non-bus subscription", func() error {
			_, err := server.SetRouteSubscription(context.Background(), &pb.RouteSubscriptionRequest{InstallId: "a", RouteType: "tra", RouteKey: "r"})
			return err
		}, codes.FailedPrecondition},
		{"expired reminder", func() error {
			_, err := server.CreateArrivalReminder(context.Background(), &pb.CreateArrivalReminderRequest{InstallId: "a", RouteType: "bus", RouteKey: "r", StopKey: "s", Direction: "0", LeadMinutes: 5, ExpiresAtUnix: time.Now().Add(-time.Minute).Unix()})
			return err
		}, codes.InvalidArgument},
		{"unsupported mrt reminder", func() error {
			_, err := server.CreateArrivalReminder(context.Background(), &pb.CreateArrivalReminderRequest{InstallId: "a", RouteType: "mrt", RouteKey: "r", StopKey: "s", Direction: "0", LeadMinutes: 5, ExpiresAtUnix: time.Now().Add(time.Hour).Unix()})
			return err
		}, codes.FailedPrecondition},
		{"missing cancel owner", func() error {
			_, err := server.CancelArrivalReminder(context.Background(), &pb.CancelArrivalReminderRequest{ReminderId: "id"})
			return err
		}, codes.InvalidArgument},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if code := status.Code(tt.call()); code != tt.want {
				t.Fatalf("code = %v, want %v", code, tt.want)
			}
		})
	}
}

type fakeAppCheckVerifier struct{ err error }

func (f fakeAppCheckVerifier) VerifyToken(_ context.Context, token string) error {
	if token != "valid" {
		return errors.New("invalid token")
	}
	return f.err
}

func TestAppCheckUnaryInterceptor(t *testing.T) {
	handler := func(context.Context, interface{}) (interface{}, error) { return "ok", nil }
	info := &grpc.UnaryServerInfo{FullMethod: pb.Firebase_Service_UpsertDevice_FullMethodName}

	t.Run("disabled bypass", func(t *testing.T) {
		got, err := appCheckUnaryInterceptor(nil, false)(context.Background(), nil, info, handler)
		if err != nil || got != "ok" {
			t.Fatalf("result = %v, error = %v", got, err)
		}
	})

	for _, tc := range []struct {
		name  string
		token string
		want  codes.Code
	}{
		{"missing", "", codes.Unauthenticated},
		{"invalid", "invalid", codes.Unauthenticated},
		{"valid", "valid", codes.OK},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx := context.Background()
			if tc.token != "" {
				ctx = metadata.NewIncomingContext(ctx, metadata.Pairs(appCheckMetadataKey, tc.token))
			}
			_, err := appCheckUnaryInterceptor(fakeAppCheckVerifier{}, true)(ctx, nil, info, handler)
			if code := status.Code(err); code != tc.want {
				t.Fatalf("code = %v, want %v", code, tc.want)
			}
		})
	}
}

func TestFirebaseEnabledFromEnv(t *testing.T) {
	for _, tc := range []struct {
		name, enabled, environment string
		want                       bool
	}{
		{"production enabled", "true", "prod", true},
		{"development bypass", "true", "dev", false},
		{"feature disabled", "false", "prod", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Setenv("FIREBASE_ENABLED", tc.enabled)
			t.Setenv("APP_ENV", tc.environment)
			if got := firebaseEnabledFromEnv(); got != tc.want {
				t.Fatalf("firebaseEnabledFromEnv() = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestFirebaseTLSCredentialsFromEnv(t *testing.T) {
	t.Run("disabled bypass", func(t *testing.T) {
		t.Setenv("FIREBASE_ENABLED", "false")
		t.Setenv("APP_ENV", "prod")
		t.Setenv("GRPC_TLS_CERT_FILE", "")
		t.Setenv("GRPC_TLS_KEY_FILE", "")
		credentials, err := firebaseTLSCredentialsFromEnv()
		if err != nil || credentials != nil {
			t.Fatalf("credentials = %v, error = %v", credentials, err)
		}
	})

	t.Run("development bypass", func(t *testing.T) {
		t.Setenv("FIREBASE_ENABLED", "true")
		t.Setenv("APP_ENV", "dev")
		t.Setenv("GRPC_TLS_CERT_FILE", "")
		t.Setenv("GRPC_TLS_KEY_FILE", "")
		credentials, err := firebaseTLSCredentialsFromEnv()
		if err != nil || credentials != nil {
			t.Fatalf("credentials = %v, error = %v", credentials, err)
		}
	})

	t.Run("production requires certificate and key", func(t *testing.T) {
		t.Setenv("FIREBASE_ENABLED", "true")
		t.Setenv("APP_ENV", "prod")
		t.Setenv("GRPC_TLS_CERT_FILE", "")
		t.Setenv("GRPC_TLS_KEY_FILE", "")
		if _, err := firebaseTLSCredentialsFromEnv(); err == nil {
			t.Fatal("firebaseTLSCredentialsFromEnv() error = nil")
		}
	})
}

type testServerStream struct {
	grpc.ServerStream
	ctx context.Context
}

func (s testServerStream) Context() context.Context { return s.ctx }

func TestAppCheckStreamInterceptor(t *testing.T) {
	info := &grpc.StreamServerInfo{FullMethod: "/Firebase_Service/futureStream"}
	handler := func(interface{}, grpc.ServerStream) error { return nil }

	missing := testServerStream{ctx: context.Background()}
	if code := status.Code(appCheckStreamInterceptor(fakeAppCheckVerifier{}, true)(nil, missing, info, handler)); code != codes.Unauthenticated {
		t.Fatalf("missing token code = %v, want %v", code, codes.Unauthenticated)
	}
	if err := appCheckStreamInterceptor(nil, false)(nil, missing, info, handler); err != nil {
		t.Fatalf("disabled interceptor error = %v", err)
	}
}
