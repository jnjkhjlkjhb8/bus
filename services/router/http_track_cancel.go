package main

import (
	"context"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

// TrackCancelPath ends an alight-tracking session from the card itself, for the
// one caller that cannot use the gRPC CancelTrack: the Android broadcast
// receiver behind 取消追蹤 (FDPL-65).
//
// That receiver runs with no Flutter engine, so it has neither the install id
// (a Hive box) nor the install secret (EncryptedSharedPreferences) the gRPC call
// authenticates with, and no gRPC stack to make the call on. Since a pushed card
// refresh can now put a card in front of a rider whose app process is gone
// (ADR-0018), that button had become reachable in a state where it could only
// hide the card and leave the session — and its remaining 下車提醒 buzzes —
// running.
//
// **The track id is the credential.** It is a server-minted UUIDv4 that only
// ever travels to the device that owns the session, so holding one is proof of
// having been shown that card. The endpoint therefore takes nothing else: no
// install id to spoof, and no way to enumerate. What it grants is exactly one
// irreversible-but-minor act — ending your own reminder — and it answers the
// same way whether or not the session existed, so it cannot be used to probe.
const TrackCancelPath = "/api/track/cancel"

// httpTrackCancelRateLimit bounds the endpoint. One press ends one ride, so a
// device has no honest reason to call this more than a handful of times an hour;
// the limit is set for a retry loop, not for traffic.
const httpTrackCancelRateLimit = 20

type trackCancelRequest struct {
	TrackID string `json:"track_id"`
}

// trackCancelStore is the cancel surface, satisfied by *firebaseStore.
type trackCancelStore interface {
	CancelArrivalReminderByID(ctx context.Context, reminderID string) (bool, error)
}

// HandleTrackCancel cancels a session's two reminder rows (the 下車站 row named
// after the session and its 提前提醒站 sibling) and publishes a terminal state so
// a watching app sees the ending.
//
// It always answers 204 for a well-formed id. Reporting whether the row existed
// would turn an unguessable identifier into an oracle, and the caller cannot act
// on the difference anyway: the card is already gone from its screen.
func HandleTrackCancel(store trackCancelStore, rc *redis.Client) gin.HandlerFunc {
	return func(c *gin.Context) {
		var request trackCancelRequest
		if err := c.ShouldBindJSON(&request); err != nil || !validUUIDv4(request.TrackID) {
			c.Status(http.StatusBadRequest)
			return
		}
		ctx := c.Request.Context()
		cancelled := false
		for _, id := range []string{request.TrackID, mrtLeadReminderID(request.TrackID)} {
			done, err := store.CancelArrivalReminderByID(ctx, id)
			if err != nil {
				zap.S().Warnw("cancel error",
					"component", "mrt_track",
					"action", "http_cancel",
					"event", "cancel_error",
					"track", request.TrackID,
					"err", err,
				)
				c.Status(http.StatusInternalServerError)
				return
			}
			cancelled = cancelled || done
		}
		if cancelled {
			publishCancelledTrackState(ctx, rc, request.TrackID)
			zap.S().Infow("cancelled",
				"component", "mrt_track",
				"action", "http_cancel",
				"event", "cancelled",
				"track", request.TrackID,
			)
		}
		c.Status(http.StatusNoContent)
	}
}

// validUUIDv4 accepts exactly the shape NewUUIDv4 produces. Anything else is
// rejected before it reaches the database: this endpoint's whole security
// argument is that its input is unguessable, and a lookup by arbitrary string
// would not be.
func validUUIDv4(value string) bool {
	if len(value) != 36 {
		return false
	}
	for index, r := range value {
		switch index {
		case 8, 13, 18, 23:
			if r != '-' {
				return false
			}
		case 14:
			if r != '4' {
				return false
			}
		default:
			if !isHexDigit(r) {
				return false
			}
		}
	}
	return true
}

// trackCancelStoreFor adapts the pool the HTTP router is built with. Kept here
// rather than threading a store through httpServerConfig: this is the only HTTP
// route that writes, and one constructor is cheaper than a new config field.
func trackCancelStoreFor(db *pgxpool.Pool) trackCancelStore {
	return NewFirebaseStore(db)
}
