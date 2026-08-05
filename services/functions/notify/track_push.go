package notify

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"time"

	"firebase.google.com/go/v4/messaging"
)

// This file builds and delivers one alight-tracking card refresh (ADR-0018).
//
// The card itself is unchanged: both native surfaces already render the field
// set Dart's `AlightTrackContent.toArgs()` defines, and a pushed refresh carries
// exactly those fields. What differs is the transport, and with it the shape:
//
//   - Android takes an FCM data message. Its receiver rebuilds the notification
//     through the same builder the MethodChannel path uses, so values arrive as
//     strings and are parsed there.
//   - iOS takes an APNs Live Activity push, whose `content-state` ActivityKit
//     decodes straight into the widget's `ContentState` with no app code in the
//     loop. That is why the two Date fields on the Swift side are unix integers:
//     a JSONDecoder left at its defaults reads a bare number as seconds since
//     2001, and nothing would have caught the 31-year skew at runtime.
//
// Only a session whose data actually moved is pushed — never a timer — which is
// what keeps volume inside APNs' Live Activity budget: about one push per
// station hop.

// AlightCard is one reading of the tracking card, in the vocabulary both native
// builders already speak.
type AlightCard struct {
	// TrackID travels to Android only, where the card's 取消追蹤 needs it to end
	// the session without an app process (FDPL-65). iOS has no equivalent: its
	// cancel button runs an App Intent inside the app.
	TrackID        string
	Mode           string
	Phase          string
	VehicleLabel   string
	VehicleID      string
	BoardStation   string
	TargetStation  string
	NextStation    string
	HopCount       int32
	CurrentIndex   int32
	RemainingStops int32
	LeadStops      int32
	LineCode       string
	LineColorHex   string
	// AsOf stamps the reading, for the iOS card's own staleness display and for
	// the APNs timestamp that orders two pushes. Android does not carry it: two
	// machines' clocks cannot order a push against a local update, so that side
	// arbitrates on stops remaining, which only ever moves one way.
	AsOf time.Time
	// StaleAfter is how long this reading stays true without another. It becomes
	// the Live Activity's stale-date, which is how the platform says "this is
	// old" when nothing can say it for us.
	StaleAfter time.Duration
}

// CardTarget is where one card lives: a device (Android's notification) and/or
// one ActivityKit activity (iOS's Live Activity). Either may be empty.
type CardTarget struct {
	FCMToken      string
	ActivityToken string
}

// CardAlert is the 下車提醒 crossing, as the iOS card can express it. ADR-0020
// asks for a vibration with nothing entering the notification centre; on iOS an
// alerting Live Activity update is the closest primitive, and it is the only one
// that reaches a suspended app. Android keeps its silent data-message buzz.
type CardAlert struct {
	Title string
	Body  string
}

// LeadAlert and AlightAlert are the two crossings, worded as the local iOS path
// words them so a pushed card and a foreground card never say different things.
func LeadAlert(remaining int32, target string) CardAlert {
	return CardAlert{Title: "Ready", Body: fmt.Sprintf("再過 %d 站到 %s", remaining, target)}
}

func AlightAlert(target string) CardAlert {
	return CardAlert{Title: "Get Set", Body: "下一站 " + target}
}

// TrackPusher delivers card refreshes over whichever transports are configured.
// A nil pusher, or a nil leg within it, is a no-op: push is additive to the
// foreground MethodChannel path, and a deployment without credentials keeps
// exactly today's behaviour.
type TrackPusher struct {
	fcm  Sender
	apns APNSSender
}

// NewTrackPusher returns nil when neither transport is available, so callers can
// hold a nil pusher and stop worrying about it.
func NewTrackPusher(fcm Sender, apns APNSSender) *TrackPusher {
	if fcm == nil && apns == nil {
		return nil
	}
	return &TrackPusher{fcm: fcm, apns: apns}
}

// PushCard refreshes one card on every transport its target names. Errors are
// joined rather than short-circuited: an iOS token that has gone must not stop
// the Android half of the same session from updating.
//
// A CardAlert is honoured on iOS only. On Android the crossing already rides its
// own silent data message (ADR-0020), and a second, alerting notification would
// put in the notification centre exactly what that ADR keeps out of it.
func (p *TrackPusher) PushCard(ctx context.Context, card AlightCard, target CardTarget, alert *CardAlert) error {
	if p == nil {
		return nil
	}
	var errs []error
	if p.fcm != nil && target.FCMToken != "" {
		if err := p.fcm.Send(ctx, cardMessage(target.FCMToken, card)); err != nil {
			errs = append(errs, fmt.Errorf("fcm: %w", err))
		}
	}
	if p.apns != nil && target.ActivityToken != "" {
		payload, err := liveActivityPayload(card, alert)
		if err != nil {
			errs = append(errs, fmt.Errorf("apns payload: %w", err))
		} else if err := p.apns.SendLiveActivity(ctx, target.ActivityToken, payload); err != nil {
			errs = append(errs, fmt.Errorf("apns: %w", err))
		}
	}
	return errors.Join(errs...)
}

// cardMessage is the Android leg: a data-only, high-priority message carrying
// the card's fields. No notification payload — the receiver builds the card
// itself, and a notification here would post a second, plain one beside it.
// Priority high or Doze holds it until the rider has already missed the stop.
func cardMessage(token string, card AlightCard) *messaging.Message {
	data := map[string]string{
		"type": trackPushType,
		// Rides on the card so its 取消追蹤 can end this session even from a
		// process with no Dart alive (FDPL-65) — which is exactly the state a
		// pushed card can be read in.
		"trackId":        card.TrackID,
		"mode":           card.Mode,
		"phase":          card.Phase,
		"vehicleLabel":   card.VehicleLabel,
		"vehicleId":      card.VehicleID,
		"boardStation":   card.BoardStation,
		"targetStation":  card.TargetStation,
		"nextStation":    card.NextStation,
		"hopCount":       strconv.Itoa(int(card.HopCount)),
		"currentIndex":   strconv.Itoa(int(card.CurrentIndex)),
		"remainingStops": strconv.Itoa(int(card.RemainingStops)),
		"leadStops":      strconv.Itoa(int(card.LeadStops)),
		"lineCode":       card.LineCode,
		"lineColorHex":   card.LineColorHex,
	}
	return &messaging.Message{
		Token:   token,
		Data:    data,
		Android: &messaging.AndroidConfig{Priority: "high"},
	}
}

// trackPushType is the discriminator the Android receiver filters on. It sits
// beside the existing "alight_vibrate" type on the same FCM path.
const trackPushType = "alight_track"

// cardDismissalLinger keeps a terminal card on screen before the system takes it
// away, matching the linger the local iOS path ends with: an ending has to be
// seen.
const cardDismissalLinger = 8 * time.Second

// liveActivityPayload is the iOS leg. `content-state` mirrors the widget's
// ContentState field for field; `timestamp` is how APNs discards a push that
// arrives after a newer one; `stale-date` is the reading's own expiry.
//
// A terminal phase ends the activity instead of updating it, with a dismissal
// date rather than an immediate removal.
func liveActivityPayload(card AlightCard, alert *CardAlert) ([]byte, error) {
	state := map[string]any{
		"phase":          card.Phase,
		"vehicleLabel":   card.VehicleLabel,
		"nextStation":    card.NextStation,
		"hopCount":       card.HopCount,
		"currentIndex":   card.CurrentIndex,
		"remainingStops": card.RemainingStops,
		"leadStops":      card.LeadStops,
		"walkMinutes":    0,
		"asOfUnix":       card.AsOf.Unix(),
	}
	if card.VehicleID != "" {
		state["vehicleId"] = card.VehicleID
	}
	if card.LineCode != "" {
		state["lineCode"] = card.LineCode
	}
	if card.LineColorHex != "" {
		state["lineColorHex"] = card.LineColorHex
	}

	aps := map[string]any{
		"timestamp":     card.AsOf.Unix(),
		"event":         "update",
		"content-state": state,
	}
	if cardPhaseIsLive(card.Phase) {
		aps["stale-date"] = card.AsOf.Add(card.StaleAfter).Unix()
	} else {
		aps["event"] = "end"
		aps["dismissal-date"] = card.AsOf.Add(cardDismissalLinger).Unix()
	}
	if alert != nil {
		aps["alert"] = map[string]any{"title": alert.Title, "body": alert.Body}
	}
	return json.Marshal(map[string]any{"aps": aps})
}

// cardPhaseIsLive mirrors the widget's own Phase.isLive: waiting, riding and
// approaching still have a ride to describe; arrived and lost are endings.
func cardPhaseIsLive(phase string) bool {
	switch phase {
	case "waiting", "riding", "approaching":
		return true
	}
	return false
}
