package notify

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"time"

	"firebase.google.com/go/v4/messaging"
)

// ArrivalEvent is one live vehicle arrival considered for reminder dispatch.
type ArrivalEvent struct {
	RouteType     string `json:"route_type"`
	RouteKey      string `json:"route_key"`
	StopKey       string `json:"stop_key"`
	Direction     string `json:"direction"`
	ETASeconds    int32  `json:"eta_seconds"`
	ArrivingPlate string `json:"arriving_plate"`
}

type arrivalMatch struct {
	reminder arrivalReminder
	arrival  ArrivalEvent
}

// notificationStorage is the persistence surface the dispatcher depends on,
// implemented by Store and stubbed in tests.
type notificationStorage interface {
	subscribedTokens(context.Context, string, string) ([]deviceToken, error)
	activeRemindersForArrivals(context.Context, []ArrivalEvent, time.Time) ([]arrivalMatch, error)
	dueScheduledReminders(context.Context, time.Time) ([]arrivalReminder, error)
	claim(context.Context, string, time.Time) (bool, error)
	release(context.Context, string) (bool, error)
	fired(context.Context, string, time.Time) (bool, error)
	invalidate(context.Context, string) error
}

// Dispatcher sends route-alert and arrival-reminder pushes. now is a
// clock seam for tests.
type Dispatcher struct {
	store               notificationStorage
	sender              Sender
	now                 func() time.Time
	finalizationTimeout time.Duration
}

// isInvalidFCMToken reports whether an FCM send error means the token is no
// longer registered and should be invalidated. It is a package var so tests can
// substitute the check.
var isInvalidFCMToken = messaging.IsUnregistered

// ArrivalFinalizationTimeout bounds the detached fired/release/invalidate
// window after a send. Exported so the functions package can assert the
// reclaim-safety bound (liveJobTimeout + this < ReminderClaimTimeout) in a
// test.
const ArrivalFinalizationTimeout = 2 * time.Second

// NewDispatcher builds a dispatcher, or returns nil when sender is
// nil (push disabled). Callers must treat a nil dispatcher as "notifications off"
// — every dispatcher method is nil-safe and returns early.
func NewDispatcher(store notificationStorage, sender Sender) *Dispatcher {
	if sender == nil {
		return nil
	}
	return &Dispatcher{store: store, sender: sender, now: time.Now, finalizationTimeout: ArrivalFinalizationTimeout}
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

// MrtVibrateEvent is one metro alight-reminder session reaching its lead: the
// reminder/track ID to fire once and the device token to reach. TrackID is
// echoed to the client so it can match the vibration to the session on screen.
type MrtVibrateEvent struct {
	ReminderID string
	Token      string
	TrackID    string
}

// vibrateMessage builds the alight-reminder push: a DATA-only, high-priority FCM
// message with NO notification payload, so nothing enters the notification
// center — the Android client wakes and vibrates (ADR-0015). iOS transport
// (ActivityKit alerting) is out of scope for this phase; this message carries no
// APNs config, so an iOS token receives a silent data message the client may
// ignore until that seam is built.
func vibrateMessage(token, trackID string) *messaging.Message {
	return &messaging.Message{
		Token:   token,
		Data:    map[string]string{"type": "mrt_vibrate", "track_id": trackID},
		Android: &messaging.AndroidConfig{Priority: "high"},
	}
}

// FireMrtVibrate delivers the alight vibration exactly once, reusing the
// reminder claim/fire machinery: claim moves the row pending→sending (losing the
// race or an already-fired row yields false with no send), the data message is
// sent, and fired finalizes it. A failed send releases the claim for a later
// tick and invalidates an unregistered token. No-op — (false, nil) — for a nil
// dispatcher or an empty token (push off / unknown device), so the tracker still
// advances the card without vibrating.
func (d *Dispatcher) FireMrtVibrate(ctx context.Context, event MrtVibrateEvent) (bool, error) {
	if d == nil || event.Token == "" {
		return false, nil
	}
	now := d.now()
	claimed, err := d.store.claim(ctx, event.ReminderID, now)
	if err != nil {
		return false, fmt.Errorf("claim mrt track %s: %w", event.ReminderID, err)
	}
	if !claimed {
		return false, nil
	}
	sendErr := d.sender.Send(ctx, vibrateMessage(event.Token, event.TrackID))
	finalizationCtx, cancelFinalization := context.WithTimeout(context.WithoutCancel(ctx), d.finalizationTimeout)
	defer cancelFinalization()
	if sendErr != nil {
		if isInvalidFCMToken(sendErr) {
			if invalidateErr := d.store.invalidate(finalizationCtx, event.Token); invalidateErr != nil {
				return false, errors.Join(fmt.Errorf("send mrt vibrate %s: %w", event.ReminderID, sendErr), invalidateErr)
			}
		}
		if _, releaseErr := d.store.release(finalizationCtx, event.ReminderID); releaseErr != nil {
			return false, errors.Join(fmt.Errorf("send mrt vibrate %s: %w", event.ReminderID, sendErr), releaseErr)
		}
		return false, fmt.Errorf("send mrt vibrate %s: %w", event.ReminderID, sendErr)
	}
	fired, err := d.store.fired(finalizationCtx, event.ReminderID, now)
	if err != nil {
		return false, fmt.Errorf("mark mrt track %s fired: %w", event.ReminderID, err)
	}
	return fired, nil
}

// routeAlert pushes a service-disruption notification to every device
// subscribed to a route. An empty routeKey is a line-wide disruption and
// reaches every subscriber of that transit type. It is a no-op for a nil
// dispatcher or an unknown transit type. Tokens are deduped, and a send that
// reports an unregistered token invalidates that token instead of retrying.
func (d *Dispatcher) routeAlert(ctx context.Context, routeType, routeKey, body string) {
	if d == nil || !isAlertRouteType(routeType) {
		return
	}
	tokens, err := d.store.subscribedTokens(ctx, routeType, routeKey)
	if err != nil {
		log.Errorf("[FCM] action=route_alert event=subscriptions_query_failed route_type=%s route_key=%s error=%v", routeType, routeKey, err)
		return
	}
	seen := map[string]struct{}{}
	for _, v := range tokens {
		if _, ok := seen[v.token]; ok {
			continue
		}
		seen[v.token] = struct{}{}
		err = d.sender.Send(ctx, notificationMessage(v.token, alertTitle(routeKey), body, map[string]string{"kind": "route_alert", "route_type": routeType, "route_key": routeKey}))
		if isInvalidFCMToken(err) {
			_ = d.store.invalidate(ctx, v.token)
		} else if err != nil {
			log.Warnf("[FCM] action=route_alert event=send_failed route_type=%s route_key=%s error=%v", routeType, routeKey, err)
		}
	}
}

// isAlertRouteType reports whether a transit type can carry disruption alerts.
// It mirrors the route_type CHECK constraint on firebase_route_subscription.
func isAlertRouteType(routeType string) bool {
	switch routeType {
	case "bus", "mrt", "tra", "thsr":
		return true
	}
	return false
}

// alertTitle labels a disruption by how wide it is: a keyed alert names one
// route, an unkeyed one is line-wide.
func alertTitle(routeKey string) string {
	if routeKey == "" {
		return "營運通阻"
	}
	return "路線異常"
}

// arrivalReminderBody renders the live-ETA reminder text. Zero minutes means
// the vehicle is entering the stop now (the MQTT near-stop trigger), where
// 「預計 0 分鐘後到站」would read as broken copy.
func arrivalReminderBody(minutes int32) string {
	if minutes <= 0 {
		return "即將進站"
	}
	return fmt.Sprintf("預計 %d 分鐘後到站", minutes)
}

func sameArrivalIdentity(left, right ArrivalEvent) bool {
	return left.RouteType == right.RouteType && left.RouteKey == right.RouteKey &&
		left.StopKey == right.StopKey && left.Direction == right.Direction
}

// Arrivals dispatches one collection of live arrival observations with one
// reminder lookup. Claim, send, and final state errors are joined so no failed
// transition is hidden from the cron runner.
func (d *Dispatcher) Arrivals(ctx context.Context, events []ArrivalEvent) error {
	if d == nil || len(events) == 0 {
		return nil
	}
	eligible := make([]ArrivalEvent, 0, len(events))
	for _, event := range events {
		if event.ETASeconds >= 0 {
			eligible = append(eligible, event)
		}
	}
	if len(eligible) == 0 {
		return nil
	}
	now := d.now()
	matches, err := d.store.activeRemindersForArrivals(ctx, eligible, now)
	if err != nil {
		return fmt.Errorf("load arrival reminders: %w", err)
	}
	var dispatchErr error
	for _, match := range matches {
		if ctxErr := ctx.Err(); ctxErr != nil {
			dispatchErr = errors.Join(dispatchErr, ctxErr)
			break
		}
		r, event := match.reminder, match.arrival
		if !sameArrivalIdentity(event, ArrivalEvent{
			RouteType: r.routeType, RouteKey: r.routeKey, StopKey: r.stopKey, Direction: r.direction,
		}) || event.ETASeconds < 0 || event.ETASeconds > int32(r.leadMinutes*60) ||
			(r.plate != "" && r.plate != event.ArrivingPlate) {
			continue
		}
		claimed, claimErr := d.store.claim(ctx, r.id, now)
		if claimErr != nil {
			dispatchErr = errors.Join(dispatchErr, fmt.Errorf("claim arrival reminder %s: %w", r.id, claimErr))
			continue
		}
		if !claimed {
			continue
		}
		msg := notificationMessage(r.token, "即將到站", arrivalReminderBody((event.ETASeconds+59)/60), map[string]string{"kind": "arrival_reminder", "route_type": r.routeType, "route_key": r.routeKey, "stop_key": r.stopKey, "direction": r.direction, "lead_minutes": strconv.Itoa(r.leadMinutes)})
		sendErr := d.sender.Send(ctx, msg)
		finalizationCtx, cancelFinalization := context.WithTimeout(context.WithoutCancel(ctx), d.finalizationTimeout)
		if sendErr != nil {
			if isInvalidFCMToken(sendErr) {
				if invalidateErr := d.store.invalidate(finalizationCtx, r.token); invalidateErr != nil {
					dispatchErr = errors.Join(dispatchErr, fmt.Errorf("invalidate arrival reminder token: %w", invalidateErr))
				}
			}
			released, releaseErr := d.store.release(finalizationCtx, r.id)
			if releaseErr != nil {
				dispatchErr = errors.Join(dispatchErr, fmt.Errorf("release arrival reminder %s: %w", r.id, releaseErr))
			} else if !released {
				dispatchErr = errors.Join(dispatchErr, fmt.Errorf("release arrival reminder %s changed no rows", r.id))
			}
			dispatchErr = errors.Join(dispatchErr, fmt.Errorf("send arrival reminder %s: %w", r.id, sendErr))
			cancelFinalization()
			if ctxErr := ctx.Err(); ctxErr != nil {
				dispatchErr = errors.Join(dispatchErr, ctxErr)
				break
			}
			continue
		}
		fired, firedErr := d.store.fired(finalizationCtx, r.id, now)
		cancelFinalization()
		if firedErr != nil {
			dispatchErr = errors.Join(dispatchErr, fmt.Errorf("mark arrival reminder %s fired: %w", r.id, firedErr))
		} else if !fired {
			dispatchErr = errors.Join(dispatchErr, fmt.Errorf("mark arrival reminder %s fired changed no rows", r.id))
		}
		if ctxErr := ctx.Err(); ctxErr != nil {
			dispatchErr = errors.Join(dispatchErr, ctxErr)
			break
		}
	}
	return dispatchErr
}

// FireScheduled sends arrival reminders whose scheduled fire time has arrived —
// the rail path, where the arrival time is known so fire_at was set at creation
// (arrival − lead) rather than derived from a live ETA. It claims each reminder
// before sending to avoid duplicate pushes across ticks, marks it fired on
// success, releases it to retry on a transient failure, and invalidates the
// token when FCM reports it unregistered. No-op for a nil dispatcher. Mirrors
// the Arrivals contract: claim, send, and final-state errors are joined so no
// failed transition — including a release failure that would otherwise strand
// a reminder in 'sending' forever — is hidden from the cron runner.
func (d *Dispatcher) FireScheduled(ctx context.Context) error {
	if d == nil {
		return nil
	}
	now := d.now()
	reminders, err := d.store.dueScheduledReminders(ctx, now)
	if err != nil {
		return fmt.Errorf("load scheduled reminders: %w", err)
	}
	var dispatchErr error
	for _, r := range reminders {
		if ctxErr := ctx.Err(); ctxErr != nil {
			dispatchErr = errors.Join(dispatchErr, ctxErr)
			break
		}
		claimed, claimErr := d.store.claim(ctx, r.id, now)
		if claimErr != nil {
			dispatchErr = errors.Join(dispatchErr, fmt.Errorf("claim scheduled reminder %s: %w", r.id, claimErr))
			continue
		}
		if !claimed {
			continue
		}
		msg := notificationMessage(r.token, "即將到站", fmt.Sprintf("預計 %d 分鐘後到站", r.leadMinutes), map[string]string{"kind": "arrival_reminder", "route_type": r.routeType, "route_key": r.routeKey, "stop_key": r.stopKey, "direction": r.direction, "lead_minutes": strconv.Itoa(r.leadMinutes)})
		sendErr := d.sender.Send(ctx, msg)
		finalizationCtx, cancelFinalization := context.WithTimeout(context.WithoutCancel(ctx), d.finalizationTimeout)
		if sendErr != nil {
			if isInvalidFCMToken(sendErr) {
				if invalidateErr := d.store.invalidate(finalizationCtx, r.token); invalidateErr != nil {
					dispatchErr = errors.Join(dispatchErr, fmt.Errorf("invalidate scheduled reminder token: %w", invalidateErr))
				}
			}
			released, releaseErr := d.store.release(finalizationCtx, r.id)
			if releaseErr != nil {
				dispatchErr = errors.Join(dispatchErr, fmt.Errorf("release scheduled reminder %s: %w", r.id, releaseErr))
			} else if !released {
				dispatchErr = errors.Join(dispatchErr, fmt.Errorf("release scheduled reminder %s changed no rows", r.id))
			}
			dispatchErr = errors.Join(dispatchErr, fmt.Errorf("send scheduled reminder %s: %w", r.id, sendErr))
			cancelFinalization()
			if ctxErr := ctx.Err(); ctxErr != nil {
				dispatchErr = errors.Join(dispatchErr, ctxErr)
				break
			}
			continue
		}
		fired, firedErr := d.store.fired(finalizationCtx, r.id, now)
		cancelFinalization()
		if firedErr != nil {
			dispatchErr = errors.Join(dispatchErr, fmt.Errorf("mark scheduled reminder %s fired: %w", r.id, firedErr))
		} else if !fired {
			dispatchErr = errors.Join(dispatchErr, fmt.Errorf("mark scheduled reminder %s fired changed no rows", r.id))
		}
		if ctxErr := ctx.Err(); ctxErr != nil {
			dispatchErr = errors.Join(dispatchErr, ctxErr)
			break
		}
	}
	return dispatchErr
}
