package main

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"firebase.google.com/go/v4/messaging"
)

// notificationStorage is the persistence surface the dispatcher depends on,
// implemented by notificationStore and stubbed in tests.
type notificationStorage interface {
	subscribedTokens(context.Context, string, string) ([]deviceToken, error)
	activeReminders(context.Context, string, string, string, string, time.Time) ([]arrivalReminder, error)
	claim(context.Context, string, time.Time) (bool, error)
	release(context.Context, string) (bool, error)
	fired(context.Context, string, time.Time) (bool, error)
	invalidate(context.Context, string) error
}

// notificationDispatcher sends route-alert and arrival-reminder pushes. now is a
// clock seam for tests.
type notificationDispatcher struct {
	store  notificationStorage
	sender fcmSender
	now    func() time.Time
}

// isInvalidFCMToken reports whether an FCM send error means the token is no
// longer registered and should be invalidated. It is a package var so tests can
// substitute the check.
var isInvalidFCMToken = messaging.IsUnregistered

// newNotificationDispatcher builds a dispatcher, or returns nil when sender is
// nil (push disabled). Callers must treat a nil dispatcher as "notifications off"
// — every dispatcher method is nil-safe and returns early.
func newNotificationDispatcher(store notificationStorage, sender fcmSender) *notificationDispatcher {
	if sender == nil {
		return nil
	}
	return &notificationDispatcher{store: store, sender: sender, now: time.Now}
}

// notificationMessage builds an FCM message with both a notification and a data
// payload (title/body are copied into data too), configured for high-priority
// delivery with default sound on Android and APNs. It mutates and reuses the
// passed data map.
func notificationMessage(token, title, body string, data map[string]string) *messaging.Message {
	data["title"] = title
	data["body"] = body
	return &messaging.Message{Token: token, Data: data, Notification: &messaging.Notification{Title: title, Body: body}, Android: &messaging.AndroidConfig{Priority: "high", Notification: &messaging.AndroidNotification{Sound: "default"}}, APNS: &messaging.APNSConfig{Payload: &messaging.APNSPayload{Aps: &messaging.Aps{Sound: "default"}}}}
}

// routeAlert pushes a service-alert notification to every device subscribed to a
// route. It is a no-op for a nil dispatcher, non-bus types, or an empty routeKey.
// Tokens are deduped, and a send that reports an unregistered token invalidates
// that token instead of retrying.
func (d *notificationDispatcher) routeAlert(ctx context.Context, routeType, routeKey, body string) {
	if d == nil || routeType != "bus" || routeKey == "" {
		return
	}
	tokens, err := d.store.subscribedTokens(ctx, routeType, routeKey)
	if err != nil {
		log.Infof("[FCM] route subscriptions: %v", err)
		return
	}
	seen := map[string]struct{}{}
	for _, v := range tokens {
		if _, ok := seen[v.token]; ok {
			continue
		}
		seen[v.token] = struct{}{}
		err = d.sender.Send(ctx, notificationMessage(v.token, "路線異常", body, map[string]string{"kind": "route_alert", "route_type": routeType, "route_key": routeKey}))
		if isInvalidFCMToken(err) {
			_ = d.store.invalidate(ctx, v.token)
		} else if err != nil {
			log.Infof("[FCM] route alert send: %v", err)
		}
	}
}

// arrival fires arrival reminders for a stop when the live ETA falls within a
// reminder's lead time. It is transport-agnostic: bus arrivals come from the
// live TDX ETA (busEta), metro from the Redis metro ETA cache, and TRA/THSR from
// timetable data (see arrival_sources.go); each source computes etaSeconds and
// calls this method the same way. No-op for a nil dispatcher or a negative ETA.
// Each reminder is claimed before sending to avoid duplicate pushes across
// concurrent ETA runs; on success it is marked fired, and an unregistered-token
// send invalidates the token. etaSeconds is rounded up to whole minutes in the
// message body.
func (d *notificationDispatcher) arrival(ctx context.Context, routeType, routeKey, stopKey, direction string, etaSeconds int32) {
	if d == nil || etaSeconds < 0 {
		return
	}
	now := d.now()
	reminders, err := d.store.activeReminders(ctx, routeType, routeKey, stopKey, direction, now)
	if err != nil {
		log.Infof("[FCM] arrival reminders: %v", err)
		return
	}
	for _, r := range reminders {
		if etaSeconds > int32(r.leadMinutes*60) {
			continue
		}
		claimed, err := d.store.claim(ctx, r.id, now)
		if err != nil || !claimed {
			continue
		}
		msg := notificationMessage(r.token, "即將到站", fmt.Sprintf("預計 %d 分鐘後到站", (etaSeconds+59)/60), map[string]string{"kind": "arrival_reminder", "route_type": r.routeType, "route_key": r.routeKey, "stop_key": r.stopKey, "direction": r.direction, "lead_minutes": strconv.Itoa(r.leadMinutes)})
		err = d.sender.Send(ctx, msg)
		if err != nil {
			if isInvalidFCMToken(err) {
				_ = d.store.invalidate(ctx, r.token)
			}
			continue
		}
		if _, err = d.store.fired(ctx, r.id, now); err != nil {
			log.Infof("[FCM] mark reminder fired: %v", err)
		}
	}
}
