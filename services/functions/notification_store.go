package main

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// notificationDB is the minimal pgx surface notificationStore needs, so it can
// be backed by a pool or a test double.
type notificationDB interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	Query(context.Context, string, ...any) (pgx.Rows, error)
}

// notificationStore reads push subscriptions and arrival reminders and mutates
// reminder state (claim/fire/release, token invalidation) in PostgreSQL.
type notificationStore struct{ db notificationDB }

// deviceToken is a single device's FCM token.
type deviceToken struct{ token string }

// arrivalReminder is a pending arrival reminder joined to its device token.
// leadMinutes is how far ahead of arrival the user asked to be notified.
type arrivalReminder struct {
	id, token, routeType, routeKey, stopKey, direction string
	leadMinutes                                        int
}

// subscribedTokens returns the push-enabled device tokens subscribed to a
// route's alerts, skipping devices with push disabled or an empty token.
func (s notificationStore) subscribedTokens(ctx context.Context, routeType, routeKey string) ([]deviceToken, error) {
	rows, err := s.db.Query(ctx, `SELECT d.fcm_token FROM firebase_route_subscription s JOIN firebase_device d ON d.install_id=s.install_id WHERE s.route_type=$1 AND s.route_key=$2 AND d.push_enabled AND d.fcm_token<>''`, routeType, routeKey)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []deviceToken
	for rows.Next() {
		var v deviceToken
		if err := rows.Scan(&v.token); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

// activeReminders returns pending, unexpired arrival reminders for a specific
// route/stop/direction, joined to a push-enabled device token. now filters out
// reminders whose expires_at has passed.
func (s notificationStore) activeReminders(ctx context.Context, routeType, routeKey, stopKey, direction string, now time.Time) ([]arrivalReminder, error) {
	rows, err := s.db.Query(ctx, `SELECT r.reminder_id,d.fcm_token,r.route_type,r.route_key,r.stop_key,r.direction,r.lead_minutes FROM firebase_arrival_reminder r JOIN firebase_device d ON d.install_id=r.install_id WHERE r.route_type=$1 AND r.route_key=$2 AND r.stop_key=$3 AND r.direction=$4 AND r.status='pending' AND r.expires_at>$5 AND d.push_enabled AND d.fcm_token<>''`, routeType, routeKey, stopKey, direction, now)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []arrivalReminder
	for rows.Next() {
		var v arrivalReminder
		if err := rows.Scan(&v.id, &v.token, &v.routeType, &v.routeKey, &v.stopKey, &v.direction, &v.leadMinutes); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

// dueScheduledReminders returns pending reminders whose scheduled fire_at has
// arrived (rail: fire_at = arrival − lead), joined to a push-enabled device
// token. Bus reminders leave fire_at NULL and are excluded — they fire off the
// live ETA via activeReminders instead. expires_at>now drops trains that have
// already arrived so a late tick doesn't send a stale "arriving" push.
func (s notificationStore) dueScheduledReminders(ctx context.Context, now time.Time) ([]arrivalReminder, error) {
	rows, err := s.db.Query(ctx, `SELECT r.reminder_id,d.fcm_token,r.route_type,r.route_key,r.stop_key,r.direction,r.lead_minutes FROM firebase_arrival_reminder r JOIN firebase_device d ON d.install_id=r.install_id WHERE r.status='pending' AND r.fire_at IS NOT NULL AND r.fire_at<=$1 AND r.expires_at>$1 AND d.push_enabled AND d.fcm_token<>''`, now)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []arrivalReminder
	for rows.Next() {
		var v arrivalReminder
		if err := rows.Scan(&v.id, &v.token, &v.routeType, &v.routeKey, &v.stopKey, &v.direction, &v.leadMinutes); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

// rowsChanged reports whether a conditional UPDATE affected exactly its one
// target row, which is how the claim/fire/release state transitions detect
// whether they actually won the race. The input error is passed through.
func rowsChanged(tag pgconn.CommandTag, err error) (bool, error) { return tag.RowsAffected() == 1, err }

// claim atomically moves a pending, unexpired reminder to 'sending', returning
// true only if this caller won it. This is the guard against two ETA runs pushing
// the same reminder concurrently.
func (s notificationStore) claim(ctx context.Context, id string, now time.Time) (bool, error) {
	tag, err := s.db.Exec(ctx, `UPDATE firebase_arrival_reminder SET status='sending',updated_at=NOW() WHERE reminder_id=$1 AND status='pending' AND expires_at>$2`, id, now)
	return rowsChanged(tag, err)
}

// release returns a claimed ('sending') reminder to 'pending' so it can be
// retried, used when a send fails after the claim was taken.
func (s notificationStore) release(ctx context.Context, id string) (bool, error) {
	tag, err := s.db.Exec(ctx, `UPDATE firebase_arrival_reminder SET status='pending',updated_at=NOW() WHERE reminder_id=$1 AND status='sending'`, id)
	return rowsChanged(tag, err)
}

// fired marks a claimed reminder 'fired' after a successful send, stamping
// fired_at, so it is not sent again.
func (s notificationStore) fired(ctx context.Context, id string, now time.Time) (bool, error) {
	tag, err := s.db.Exec(ctx, `UPDATE firebase_arrival_reminder SET status='fired',fired_at=$2,updated_at=NOW() WHERE reminder_id=$1 AND status='sending'`, id, now)
	return rowsChanged(tag, err)
}

// invalidate clears a device's FCM token and disables push for it, called when
// FCM reports the token is unregistered so dead tokens stop being targeted.
func (s notificationStore) invalidate(ctx context.Context, token string) error {
	_, err := s.db.Exec(ctx, `UPDATE firebase_device SET fcm_token='',push_enabled=FALSE,updated_at=NOW() WHERE fcm_token=$1`, token)
	return err
}
