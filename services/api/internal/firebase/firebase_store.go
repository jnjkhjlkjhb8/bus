package firebase

import (
	"context"
	"crypto/subtle"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
)

var errFirebaseNotFound = errors.New("firebase record not found")

const ReminderPending = "pending"

type FirebaseArrivalReminder struct {
	ReminderID  string
	InstallID   string
	RouteType   string
	RouteKey    string
	StopKey     string
	Direction   string
	LeadMinutes int32
	FireAt      *time.Time
	ExpiresAt   time.Time
	Status      string
	Token       string
	Plate       string
	// AlightEvent is "lead", "alight", or "" for a legacy banner reminder
	// (ADR-0020). It travels back out on the push so the device knows which
	// of the two vibrations to play.
	AlightEvent string
}

type firebaseDeviceToken struct {
	InstallID string
	Token     string
}

type firebaseDB interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	Query(context.Context, string, ...any) (pgx.Rows, error)
	QueryRow(context.Context, string, ...any) pgx.Row
}

type firebaseStore struct{ db firebaseDB }

func NewFirebaseStore(db *pgxpool.Pool) *firebaseStore { return &firebaseStore{db: db} }

// UpsertDevice inserts or updates a device row. The ON CONFLICT update is gated
// on the stored install_secret_hash matching secretHash, so an existing row is
// only mutated by its original installer. The returned bool reports whether a
// row was actually written (RowsAffected == 1), i.e. whether the caller was
// authorized; a new install always writes and is authorized.
func (s *firebaseStore) UpsertDevice(ctx context.Context, identity *pb.DeviceIdentity, prefs *pb.DevicePrefs, secretHash []byte) (*pb.DeviceState, bool, error) {
	result, err := s.db.Exec(ctx, `
		INSERT INTO firebase_device
			(install_id, fcm_token, platform, app_version, push_enabled, install_secret_hash)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (install_id) DO UPDATE SET
			fcm_token = EXCLUDED.fcm_token,
			platform = EXCLUDED.platform,
			app_version = EXCLUDED.app_version,
			push_enabled = EXCLUDED.push_enabled, updated_at = NOW()
		WHERE firebase_device.install_secret_hash = EXCLUDED.install_secret_hash`,
		identity.InstallId, identity.FcmToken, identity.Platform, identity.AppVersion,
		prefs.PushEnabled, secretHash,
	)
	if err != nil {
		return nil, false, err
	}
	state := &pb.DeviceState{
		Identity: &pb.DeviceIdentity{InstallId: identity.InstallId, Platform: identity.Platform, AppVersion: identity.AppVersion},
		Prefs:    prefs,
	}
	return state, result.RowsAffected() == 1, nil
}

// AuthorizeInstall reports whether secretHash matches the hash stored for the
// install. An unknown install returns (false, nil), not an error. The comparison
// is constant-time to avoid leaking the hash through timing.
func (s *firebaseStore) AuthorizeInstall(ctx context.Context, installID string, secretHash []byte) (bool, error) {
	var storedHash []byte
	err := s.db.QueryRow(ctx, `SELECT install_secret_hash FROM firebase_device WHERE install_id = $1`, installID).Scan(&storedHash)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return len(storedHash) == len(secretHash) && subtle.ConstantTimeCompare(storedHash, secretHash) == 1, nil
}

// ReplaceRouteSubscriptions swaps a device's whole 訂閱範圍 for the one the app
// derived from its 收藏: rows the new set does not contain are deleted, and the
// new ones inserted. Both statements run against the same arrays so the set is
// replaced as a unit, which is what stops the stored scope from drifting when a
// 收藏 is removed somewhere that never told the server. An empty set clears the
// device.
func (s *firebaseStore) ReplaceRouteSubscriptions(ctx context.Context, installID string, subscriptions []*pb.RouteSubscription) error {
	types := make([]string, len(subscriptions))
	keys := make([]string, len(subscriptions))
	for i, subscription := range subscriptions {
		types[i], keys[i] = subscription.GetRouteType(), subscription.GetRouteKey()
	}
	_, err := s.db.Exec(ctx, `
		WITH desired AS (
			SELECT t AS route_type, k AS route_key
			FROM unnest($2::text[], $3::text[]) AS pair(t, k)
		), removed AS (
			DELETE FROM firebase_route_subscription s
			WHERE s.install_id = $1
			  AND NOT EXISTS (
			      SELECT 1 FROM desired d
			      WHERE d.route_type = s.route_type AND d.route_key = s.route_key)
		)
		INSERT INTO firebase_route_subscription (install_id, route_type, route_key)
		SELECT $1, route_type, route_key FROM desired
		ON CONFLICT (install_id, route_type, route_key) DO NOTHING`, installID, types, keys)
	return err
}

// CreateArrivalReminder inserts a reminder row. Token is not persisted here; it
// is joined from the device row when reminders are later listed for dispatch.
func (s *firebaseStore) CreateArrivalReminder(ctx context.Context, reminder FirebaseArrivalReminder) error {
	_, err := s.db.Exec(ctx, `
		INSERT INTO firebase_arrival_reminder
			(reminder_id, install_id, route_type, route_key, stop_key, direction, lead_minutes, fire_at, expires_at, status, plate, alight_event)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)`,
		reminder.ReminderID, reminder.InstallID, reminder.RouteType, reminder.RouteKey, reminder.StopKey,
		reminder.Direction, reminder.LeadMinutes, reminder.FireAt, reminder.ExpiresAt, reminder.Status, reminder.Plate,
		reminder.AlightEvent)
	return err
}

// CancelArrivalReminder marks a caller-owned pending reminder as cancelled. The
// returned bool is true only when exactly one pending row was updated, so an
// already-fired, already-cancelled, or foreign reminder yields false.
func (s *firebaseStore) CancelArrivalReminder(ctx context.Context, reminderID, installID string) (bool, error) {
	result, err := s.db.Exec(ctx, `
		UPDATE firebase_arrival_reminder
		SET status = 'cancelled', updated_at = NOW()
		WHERE reminder_id = $1 AND install_id = $2 AND status = 'pending'`, reminderID, installID)
	return result.RowsAffected() == 1, err
}

// CancelArrivalReminderByID cancels a pending row by id alone, with no install
// binding. Only the card's own 取消追蹤 reaches this (FDPL-65), where the caller
// is a broadcast receiver that has no access to the install credential; the
// reminder id it carries is a server-minted UUIDv4 that never left the owning
// device, so holding one is the proof of ownership the install id would have
// been. Every other cancel path goes through CancelArrivalReminder.
func (s *firebaseStore) CancelArrivalReminderByID(ctx context.Context, reminderID string) (bool, error) {
	result, err := s.db.Exec(ctx, `
		UPDATE firebase_arrival_reminder
		SET status = 'cancelled', updated_at = NOW()
		WHERE reminder_id = $1 AND status = 'pending'`, reminderID)
	return result.RowsAffected() == 1, err
}

// ListDeviceState loads a device's platform, version, and preference flags. It
// returns errFirebaseNotFound (which the service layer maps to gRPC NotFound)
// when no row exists.
func (s *firebaseStore) ListDeviceState(ctx context.Context, installID string) (*pb.DeviceState, error) {
	state := &pb.DeviceState{Identity: &pb.DeviceIdentity{InstallId: installID}, Prefs: &pb.DevicePrefs{}}
	err := s.db.QueryRow(ctx, `
		SELECT platform, app_version, push_enabled
		FROM firebase_device WHERE install_id = $1`, installID).Scan(
		&state.Identity.Platform, &state.Identity.AppVersion, &state.Prefs.PushEnabled,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, errFirebaseNotFound
	}
	return state, err
}

// ListSubscribedDevices returns the FCM tokens of devices subscribed to a route
// that still have push enabled and a non-empty token. Used by the push-dispatch
// path in the functions binary.
func (s *firebaseStore) ListSubscribedDevices(ctx context.Context, routeType, routeKey string) ([]firebaseDeviceToken, error) {
	rows, err := s.db.Query(ctx, `
		SELECT d.install_id, d.fcm_token
		FROM firebase_route_subscription s
		JOIN firebase_device d ON d.install_id = s.install_id
		WHERE s.route_type = $1 AND s.route_key = $2 AND d.push_enabled AND d.fcm_token <> ''`, routeType, routeKey)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var devices []firebaseDeviceToken
	for rows.Next() {
		var device firebaseDeviceToken
		if err := rows.Scan(&device.InstallID, &device.Token); err != nil {
			return nil, err
		}
		devices = append(devices, device)
	}
	return devices, rows.Err()
}

// ListActiveArrivalReminders returns pending, unexpired reminders for a specific
// route/stop/direction, joined to each device's FCM token. Only devices with
// push enabled and a non-empty token are included. It is the dispatcher's query
// for candidates to fire.
func (s *firebaseStore) ListActiveArrivalReminders(ctx context.Context, routeType, routeKey, stopKey, direction string, now time.Time) ([]FirebaseArrivalReminder, error) {
	rows, err := s.db.Query(ctx, `
		SELECT r.reminder_id, r.install_id, d.fcm_token, r.route_type, r.route_key, r.stop_key,
			r.direction, r.lead_minutes, r.fire_at, r.expires_at, r.status
		FROM firebase_arrival_reminder r
		JOIN firebase_device d ON d.install_id = r.install_id
		WHERE r.route_type = $1 AND r.route_key = $2 AND r.stop_key = $3 AND r.direction = $4
			AND r.status = 'pending' AND r.expires_at > $5 AND d.push_enabled AND d.fcm_token <> ''`,
		routeType, routeKey, stopKey, direction, now)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var reminders []FirebaseArrivalReminder
	for rows.Next() {
		var reminder FirebaseArrivalReminder
		if err := rows.Scan(&reminder.ReminderID, &reminder.InstallID, &reminder.Token, &reminder.RouteType,
			&reminder.RouteKey, &reminder.StopKey, &reminder.Direction, &reminder.LeadMinutes,
			&reminder.FireAt, &reminder.ExpiresAt, &reminder.Status); err != nil {
			return nil, err
		}
		reminders = append(reminders, reminder)
	}
	return reminders, rows.Err()
}

// ClaimArrivalReminder atomically transitions a reminder from pending to sending
// so only one dispatcher sends it. The returned bool is true only when this call
// won the claim (a pending, unexpired row was updated); a concurrent claimer or
// an expired/fired reminder yields false.
func (s *firebaseStore) ClaimArrivalReminder(ctx context.Context, reminderID string, now time.Time) (bool, error) {
	result, err := s.db.Exec(ctx, `
		UPDATE firebase_arrival_reminder SET status = 'sending', updated_at = NOW()
		WHERE reminder_id = $1 AND status = 'pending' AND expires_at > $2`, reminderID, now)
	return result.RowsAffected() == 1, err
}

// ReleaseArrivalReminder returns a claimed reminder from sending back to pending
// so it can be retried after a send failure. The bool is true when a sending row
// was reset.
func (s *firebaseStore) ReleaseArrivalReminder(ctx context.Context, reminderID string) (bool, error) {
	result, err := s.db.Exec(ctx, `
		UPDATE firebase_arrival_reminder SET status = 'pending', updated_at = NOW()
		WHERE reminder_id = $1 AND status = 'sending'`, reminderID)
	return result.RowsAffected() == 1, err
}

// MarkReminderFired finalizes a claimed reminder as fired after a successful
// send. It only transitions rows currently in sending; the bool is true when one
// was updated.
func (s *firebaseStore) MarkReminderFired(ctx context.Context, reminderID string, firedAt time.Time) (bool, error) {
	result, err := s.db.Exec(ctx, `
		UPDATE firebase_arrival_reminder SET status = 'fired', fired_at = $2, updated_at = NOW()
		WHERE reminder_id = $1 AND status = 'sending'`, reminderID, firedAt)
	return result.RowsAffected() == 1, err
}

// DeleteInvalidToken clears a device's FCM token and disables push after FCM
// reports the token as unregistered. The row is kept (token blanked, push off)
// rather than deleted. The bool is true when any device carried that token.
func (s *firebaseStore) DeleteInvalidToken(ctx context.Context, token string) (bool, error) {
	result, err := s.db.Exec(ctx, `
		UPDATE firebase_device SET fcm_token = '', push_enabled = FALSE, updated_at = NOW()
		WHERE fcm_token = $1`, token)
	return result.RowsAffected() > 0, err
}
