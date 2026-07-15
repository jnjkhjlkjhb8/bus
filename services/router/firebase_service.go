package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/appcheck"
	pb "github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

const (
	appCheckMetadataKey      = "x-firebase-appcheck"
	installIDMetadataKey     = "x-install-id"
	installSecretMetadataKey = "x-install-secret"
)

type firebasePersistence interface {
	UpsertDevice(context.Context, *pb.DeviceIdentity, *pb.DevicePrefs, []byte) (*pb.DeviceState, bool, error)
	AuthorizeInstall(context.Context, string, []byte) (bool, error)
	SetRouteSubscription(context.Context, string, string, string, bool) error
	CreateArrivalReminder(context.Context, firebaseArrivalReminder) error
	CancelArrivalReminder(context.Context, string, string) (bool, error)
	ListDeviceState(context.Context, string) (*pb.DeviceState, error)
}

// FirebaseServer implements the device-registration and arrival-reminder RPCs.
// It authenticates each caller against a per-installation secret hash carried in
// gRPC metadata (see installationSecretHash) rather than any Firebase identity.
// now is injectable so tests can control reminder expiry checks; it defaults to
// time.Now when nil.
type FirebaseServer struct {
	pb.UnimplementedFirebase_ServiceServer
	store firebasePersistence
	now   func() time.Time
}

// UpsertDevice registers or updates a device installation and its notification
// preferences. It requires android/ios platform and an fcm_token whenever push
// is enabled. The install secret from metadata must match any existing row, or
// the store reports the row as unauthorized and PermissionDenied is returned.
// The fcm_token is cleared from the response so it is never echoed back.
func (s *FirebaseServer) UpsertDevice(ctx context.Context, request *pb.UpsertDeviceRequest) (*pb.DeviceState, error) {
	identity, prefs := request.GetIdentity(), request.GetPrefs()
	if identity == nil || prefs == nil || !validText(identity.GetInstallId(), 128) || !validText(identity.GetPlatform(), 16) {
		return nil, status.Error(codes.InvalidArgument, "identity and preferences are required")
	}
	if identity.Platform != "android" && identity.Platform != "ios" {
		return nil, status.Error(codes.InvalidArgument, "platform must be android or ios")
	}
	if prefs.PushEnabled && !validText(identity.FcmToken, 4096) {
		return nil, status.Error(codes.InvalidArgument, "fcm_token is required when push is enabled")
	}
	secretHash, err := installationSecretHash(ctx, identity.InstallId)
	if err != nil {
		return nil, err
	}
	state, authorized, err := s.store.UpsertDevice(ctx, identity, prefs, secretHash)
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to save device")
	}
	if !authorized {
		return nil, status.Error(codes.PermissionDenied, "installation credential does not match")
	}
	state.Identity.FcmToken = ""
	return state, nil
}

// SetRouteSubscription enables or disables push subscription for one route.
// Only bus routes are accepted; any other route_type returns FailedPrecondition.
// The caller is authorized against its install secret before the store is touched.
func (s *FirebaseServer) SetRouteSubscription(ctx context.Context, request *pb.RouteSubscriptionRequest) (*pb.Ack, error) {
	if !validText(request.GetInstallId(), 128) || !validRoute(request.GetRouteType()) || !validText(request.GetRouteKey(), 256) {
		return nil, status.Error(codes.InvalidArgument, "install_id, route_type, and route_key are required")
	}
	if request.RouteType != "bus" {
		return nil, status.Error(codes.FailedPrecondition, "route subscriptions are supported for bus routes only")
	}
	if err := s.authorizeInstall(ctx, request.InstallId); err != nil {
		return nil, err
	}
	if err := s.store.SetRouteSubscription(ctx, request.InstallId, request.RouteType, request.RouteKey, request.Enabled); err != nil {
		return nil, status.Error(codes.Internal, "failed to save route subscription")
	}
	return &pb.Ack{Ok: true}, nil
}

// CreateArrivalReminder registers a one-shot arrival reminder for a bus stop.
// It rejects non-bus routes, directions other than "0"/"1", lead times outside
// 1..120 minutes, and expiry timestamps not in the future (measured against
// s.now). It generates a UUIDv4 reminder ID and persists the reminder as pending.
func (s *FirebaseServer) CreateArrivalReminder(ctx context.Context, request *pb.CreateArrivalReminderRequest) (*pb.ArrivalReminder, error) {
	if !validText(request.GetInstallId(), 128) || !validRoute(request.GetRouteType()) ||
		!validText(request.GetRouteKey(), 256) || !validText(request.GetStopKey(), 256) || !validText(request.GetDirection(), 32) {
		return nil, status.Error(codes.InvalidArgument, "install_id, route, stop, and direction are required")
	}
	switch request.RouteType {
	case "bus", "tra", "thsr":
	default:
		return nil, status.Error(codes.FailedPrecondition, "arrival reminders are supported for bus and rail routes only")
	}
	if request.Direction != "0" && request.Direction != "1" {
		return nil, status.Error(codes.InvalidArgument, "direction must be 0 or 1")
	}
	if request.LeadMinutes < 1 || request.LeadMinutes > 120 {
		return nil, status.Error(codes.InvalidArgument, "lead_minutes must be between 1 and 120")
	}
	plate := strings.ToUpper(strings.TrimSpace(request.GetPlate()))
	if !validNormalizedPlate(plate) {
		return nil, status.Error(codes.InvalidArgument, "plate must contain only letters, digits, and single hyphen separators")
	}
	now := s.now
	if now == nil {
		now = time.Now
	}
	expiresAt := time.Unix(request.ExpiresAtUnix, 0)
	if !expiresAt.After(now()) {
		return nil, status.Error(codes.InvalidArgument, "expires_at_unix must be in the future")
	}
	if err := s.authorizeInstall(ctx, request.InstallId); err != nil {
		return nil, err
	}
	reminderID, err := newReminderID()
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to create reminder ID")
	}
	stored := firebaseArrivalReminder{
		ReminderID: reminderID, InstallID: request.InstallId, RouteType: request.RouteType, RouteKey: request.RouteKey,
		StopKey: request.StopKey, Direction: request.Direction, LeadMinutes: request.LeadMinutes,
		ExpiresAt: expiresAt, Status: reminderPending, Plate: plate,
	}
	// Rail arrival times are known at creation, so fire on a schedule (arrival
	// minus lead). Bus has no known arrival time and fires off the live ETA, so
	// it leaves fire_at NULL and is dispatched from busEta instead.
	if request.RouteType == "tra" || request.RouteType == "thsr" {
		fireAt := expiresAt.Add(-time.Duration(request.LeadMinutes) * time.Minute)
		stored.FireAt = &fireAt
	}
	if err := s.store.CreateArrivalReminder(ctx, stored); err != nil {
		return nil, status.Error(codes.Internal, "failed to save arrival reminder")
	}
	return &pb.ArrivalReminder{
		ReminderId: reminderID, InstallId: request.InstallId, RouteType: request.RouteType, RouteKey: request.RouteKey,
		StopKey: request.StopKey, Direction: request.Direction, LeadMinutes: request.LeadMinutes, ExpiresAtUnix: request.ExpiresAtUnix,
		Plate: plate,
	}, nil
}

// CancelArrivalReminder cancels a caller's pending reminder. It returns NotFound
// when no matching pending reminder exists (already fired, already cancelled, or
// owned by a different install). The caller is authorized first.
func (s *FirebaseServer) CancelArrivalReminder(ctx context.Context, request *pb.CancelArrivalReminderRequest) (*pb.Ack, error) {
	if !validText(request.GetReminderId(), 64) || !validText(request.GetInstallId(), 128) {
		return nil, status.Error(codes.InvalidArgument, "reminder_id and install_id are required")
	}
	if err := s.authorizeInstall(ctx, request.InstallId); err != nil {
		return nil, err
	}
	cancelled, err := s.store.CancelArrivalReminder(ctx, request.ReminderId, request.InstallId)
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to cancel arrival reminder")
	}
	if !cancelled {
		return nil, status.Error(codes.NotFound, "pending arrival reminder not found")
	}
	return &pb.Ack{Ok: true}, nil
}

// ListDeviceState returns the stored preferences for a device. It returns
// NotFound when the install has no row. As with UpsertDevice, the fcm_token is
// stripped from the response.
func (s *FirebaseServer) ListDeviceState(ctx context.Context, request *pb.DeviceRequest) (*pb.DeviceState, error) {
	if !validText(request.GetInstallId(), 128) {
		return nil, status.Error(codes.InvalidArgument, "install_id is required")
	}
	if err := s.authorizeInstall(ctx, request.InstallId); err != nil {
		return nil, err
	}
	state, err := s.store.ListDeviceState(ctx, request.InstallId)
	if errors.Is(err, errFirebaseNotFound) {
		return nil, status.Error(codes.NotFound, "device not found")
	}
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to load device")
	}
	state.Identity.FcmToken = ""
	return state, nil
}

func (s *FirebaseServer) authorizeInstall(ctx context.Context, installID string) error {
	secretHash, err := installationSecretHash(ctx, installID)
	if err != nil {
		return err
	}
	authorized, err := s.store.AuthorizeInstall(ctx, installID, secretHash)
	if err != nil {
		return status.Error(codes.Internal, "failed to verify installation credential")
	}
	if !authorized {
		return status.Error(codes.PermissionDenied, "installation credential does not match")
	}
	return nil
}

func installationSecretHash(ctx context.Context, installID string) ([]byte, error) {
	metadataInstallID, ok := installationCallerID(ctx)
	secrets := metadata.ValueFromIncomingContext(ctx, installSecretMetadataKey)
	if !ok || metadataInstallID != installID || len(secrets) != 1 || !validText(secrets[0], 256) || len(secrets[0]) < 32 {
		return nil, status.Error(codes.PermissionDenied, "valid installation credential required")
	}
	hash := sha256.Sum256([]byte(secrets[0]))
	return hash[:], nil
}

// installationCallerID extracts the stable installation identifier used to
// avoid grouping distinct app installations behind the same carrier NAT into
// one rate-limit bucket. Authentication still happens independently through
// installationSecretHash and App Check; this value is only a fairness key.
func installationCallerID(ctx context.Context) (string, bool) {
	values := metadata.ValueFromIncomingContext(ctx, installIDMetadataKey)
	if len(values) != 1 || !validText(values[0], 128) {
		return "", false
	}
	return values[0], true
}

func validText(value string, max int) bool {
	return value != "" && len(value) <= max && strings.TrimSpace(value) == value
}

func validNormalizedPlate(plate string) bool {
	if plate == "" {
		return true
	}
	if len(plate) > 32 || plate[0] == '-' || plate[len(plate)-1] == '-' {
		return false
	}
	previousHyphen := false
	for _, char := range plate {
		switch {
		case char >= 'A' && char <= 'Z', char >= '0' && char <= '9':
			previousHyphen = false
		case char == '-' && !previousHyphen:
			previousHyphen = true
		default:
			return false
		}
	}
	return true
}

func validRoute(routeType string) bool {
	switch routeType {
	case "bus", "mrt", "tra", "thsr":
		return true
	default:
		return false
	}
}

func newReminderID() (string, error) {
	var id [16]byte
	if _, err := rand.Read(id[:]); err != nil {
		return "", err
	}
	id[6] = id[6]&0x0f | 0x40
	id[8] = id[8]&0x3f | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", id[0:4], id[4:6], id[6:8], id[8:10], id[10:16]), nil
}

type appCheckVerifier interface {
	VerifyToken(context.Context, string) error
}

type firebaseAppCheckVerifier struct{ client *appcheck.Client }

// VerifyToken checks a Firebase App Check token via the Admin SDK. The context
// is unused because the underlying appcheck client verifies offline against
// cached public keys.
func (v firebaseAppCheckVerifier) VerifyToken(_ context.Context, token string) error {
	_, err := v.client.VerifyToken(token)
	return err
}

func firebaseAppCheckFromEnv(ctx context.Context) (appCheckVerifier, bool, error) {
	enabled := firebaseEnabledFromEnv()
	if !enabled {
		return nil, false, nil
	}
	var config *firebase.Config
	if projectID := os.Getenv("FIREBASE_PROJECT_ID"); projectID != "" {
		config = &firebase.Config{ProjectID: projectID}
	}
	app, err := firebase.NewApp(ctx, config)
	if err != nil {
		return nil, false, fmt.Errorf("initialize Firebase Admin: %w", err)
	}
	client, err := app.AppCheck(ctx)
	if err != nil {
		return nil, false, fmt.Errorf("initialize Firebase App Check: %w", err)
	}
	return firebaseAppCheckVerifier{client: client}, true, nil
}

func firebaseEnabledFromEnv() bool {
	return strings.EqualFold(os.Getenv("FIREBASE_ENABLED"), "true") && !strings.EqualFold(os.Getenv("APP_ENV"), "dev")
}

// grpcTLSEnabledFromEnv reports whether the gRPC server should terminate
// TLS. This is independent of Firebase/App Check: staging and prod both
// terminate TLS at the router regardless of whether App Check enforcement
// is on, so the two concerns must not share one flag.
func grpcTLSEnabledFromEnv() bool {
	return strings.EqualFold(os.Getenv("GRPC_TLS"), "true")
}

// grpcTLSCredentialsFromEnv builds server TLS credentials when GRPC_TLS is
// enabled. It fails closed: GRPC_TLS=true without both cert and key paths
// is a startup error rather than a silent fall-back to plaintext.
func grpcTLSCredentialsFromEnv() (credentials.TransportCredentials, error) {
	if !grpcTLSEnabledFromEnv() {
		return nil, nil
	}
	certFile, keyFile := os.Getenv("GRPC_TLS_CERT_FILE"), os.Getenv("GRPC_TLS_KEY_FILE")
	if certFile == "" || keyFile == "" {
		return nil, errors.New("GRPC_TLS_CERT_FILE and GRPC_TLS_KEY_FILE are required when GRPC_TLS is enabled")
	}
	certificate, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return nil, fmt.Errorf("load gRPC TLS certificate: %w", err)
	}
	return credentials.NewTLS(&tls.Config{
		Certificates: []tls.Certificate{certificate},
		MinVersion:   tls.VersionTLS12,
	}), nil
}

func appCheckUnaryInterceptor(verifier appCheckVerifier, enabled bool) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, request interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		if !enabled || !strings.HasPrefix(info.FullMethod, "/Firebase_Service/") {
			return handler(ctx, request)
		}
		if err := verifyAppCheck(ctx, verifier); err != nil {
			return nil, err
		}
		return handler(ctx, request)
	}
}

func appCheckStreamInterceptor(verifier appCheckVerifier, enabled bool) grpc.StreamServerInterceptor {
	return func(server interface{}, stream grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) error {
		if enabled && strings.HasPrefix(info.FullMethod, "/Firebase_Service/") {
			if err := verifyAppCheck(stream.Context(), verifier); err != nil {
				return err
			}
		}
		return handler(server, stream)
	}
}

func verifyAppCheck(ctx context.Context, verifier appCheckVerifier) error {
	values := metadata.ValueFromIncomingContext(ctx, appCheckMetadataKey)
	if len(values) != 1 || values[0] == "" || verifier == nil {
		return status.Error(codes.Unauthenticated, "valid Firebase App Check token required")
	}
	if err := verifier.VerifyToken(ctx, values[0]); err != nil {
		return status.Error(codes.Unauthenticated, "valid Firebase App Check token required")
	}
	return nil
}
