package main

import (
	"context"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/go-redis/redis"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jnjkhjlkjhb8/wheres_the_car/models"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/functions/notify"
	"github.com/jnjkhjlkjhb8/wheres_the_car/services/shared"
	"github.com/robfig/cron/v3"
	"google.golang.org/protobuf/proto"
)

// This file is the metro alight-reminder tracker (捷運下車提醒, ADR-0015): a 15s
// cron that advances each active car-bound session one station hop at a time. It
// is NOT a liveSpec — it never touches TDX. Polling is event-driven: a session
// is only polled once its previous reading's countdown has elapsed, so a ride
// costs about one GetTrainInfo call per station hop rather than one per tick.
// Position, path, and progress live in the session's Redis state (MrtTrackKey);
// the reminders table only enumerates which sessions are active and carries the
// device token for the lead vibration.

// Metro session status values carried in MrtTrackState.status. tracking and
// lead_fired are live; the rest are terminal endings surfaced only on the card.
const (
	mrtStatusTracking  = "tracking"
	mrtStatusLeadFired = "lead_fired"
	mrtStatusArrived   = "arrived"
	mrtStatusLost      = "lost"
	mrtStatusStale     = "stale"
	mrtStatusCancelled = "cancelled"
)

const (
	// mrtTrackActiveTTL keeps a live session's Redis state slightly beyond the
	// reminder's own 3h expiry so a watcher always has state to seed from.
	mrtTrackActiveTTL = 3 * time.Hour
	// mrtTrackEndedTTL keeps a terminal state briefly so connected watchers
	// receive the ending before the key disappears.
	mrtTrackEndedTTL = 60 * time.Second
	// mrtTrackStaleAfter ends a session that has not advanced within this window
	// (a lost binding the position resolver could not classify as off-path, a
	// stalled train, or a persistent feed gap).
	mrtTrackStaleAfter = 10 * time.Minute
	// mrtTrackPollBuffer pads the parsed countdown so the next poll lands just
	// after the train is due at its next station, not before.
	mrtTrackPollBuffer = 10 * time.Second
	// mrtTrackFallbackRetry is the retry delay after an empty/failed GetTrainInfo
	// (including the mrt_live fallback path), where no countdown is available.
	mrtTrackFallbackRetry = 30 * time.Second
	// mrtTrackTickTimeout bounds one whole tracker tick under its 15s cadence.
	mrtTrackTickTimeout = 12 * time.Second
)

// trainInfoClient is the GetTrainInfo seam the tracker depends on, satisfied by
// *shared.TRTCTrainInfoClient and stubbed in tests.
type trainInfoClient interface {
	GetTrainInfo(ctx context.Context, carID string) (*shared.TRTCTrainInfo, bool, error)
}

// mrtTrackStore is the reminder-enumeration seam: which sessions are active and
// how to drop a never-fired one whose Redis state has ended.
type mrtTrackStore interface {
	ActiveMrtTracks(ctx context.Context, now time.Time) ([]notify.MrtTrackReminder, error)
	ExpireMrtTrack(ctx context.Context, id string) error
}

// mrtVibrator fires the lead vibration exactly once, satisfied by
// *notify.Dispatcher (nil-safe when push is disabled).
type mrtVibrator interface {
	FireMrtVibrate(ctx context.Context, event notify.MrtVibrateEvent) (bool, error)
}

// mrtTracker holds the tracker's dependencies for one deployment.
type mrtTracker struct {
	trtc     trainInfoClient
	rc       *redis.Client
	store    mrtTrackStore
	vibrator mrtVibrator
}

// registerMrtTrackCron schedules the 15s tracker. Empty TRTC credentials make
// GetTrainInfo a no-op, and no session can be created without it, so a
// credential-less environment simply has nothing to advance.
func registerMrtTrackCron(r *cron.Cron, rc *redis.Client, db *pgxpool.Pool, dispatcher *notify.Dispatcher) {
	tracker := &mrtTracker{
		trtc:     shared.NewTRTCTrainInfoClient(os.Getenv("TRTC_USERNAME"), os.Getenv("TRTC_PASSWORD")),
		rc:       rc,
		store:    notify.NewStore(db),
		vibrator: dispatcher,
	}
	_, _ = addStaticCron(r, "@every 15s", func() {
		withTimeout(mrtTrackTickTimeout, func(ctx context.Context) {
			tracker.tick(ctx, time.Now().In(taipei))
		})
	})
}

// tick advances every due session once. Per-session failures are logged and do
// not abort the others.
func (t *mrtTracker) tick(ctx context.Context, now time.Time) {
	tracks, err := t.store.ActiveMrtTracks(ctx, now)
	if err != nil {
		log.Errorf("[MRT_TRACK] action=tick event=list_error error=%v", err)
		return
	}
	if len(tracks) == 0 {
		return
	}
	log.Infof("[MRT_TRACK] action=tick event=start sessions=%d", len(tracks))
	for _, track := range tracks {
		if ctx.Err() != nil {
			return
		}
		t.advanceSession(ctx, track, now)
	}
}

// advanceSession processes one session: read its Redis state, skip it unless a
// poll is due, acquire a reading, apply the pure advance decision, fire the lead
// vibration once, and persist + publish the new state.
func (t *mrtTracker) advanceSession(ctx context.Context, track notify.MrtTrackReminder, now time.Time) {
	raw, err := t.rc.WithContext(ctx).Get(shared.MrtTrackKey(track.ID)).Bytes()
	if err == redis.Nil {
		// The session's state has ended and its key expired (or was never
		// written). Drop a never-fired row so the active query stops returning it;
		// a fired row ages out on expires_at (its status cannot move — CHECK).
		if expireErr := t.store.ExpireMrtTrack(ctx, track.ID); expireErr != nil {
			log.Warnf("[MRT_TRACK] action=advance event=expire_error track=%s error=%v", track.ID, expireErr)
		}
		return
	}
	if err != nil {
		log.Warnf("[MRT_TRACK] action=advance event=state_read_error track=%s error=%v", track.ID, err)
		return
	}
	var state models.MrtTrackState
	if err := proto.Unmarshal(raw, &state); err != nil {
		log.Warnf("[MRT_TRACK] action=advance event=state_decode_error track=%s error=%v", track.ID, err)
		return
	}
	if mrtIsTerminal(state.Status) {
		return
	}
	if now.Unix() < state.NextPollAtUnix {
		return
	}

	reading := t.readPosition(ctx, &state)
	newState, fire := advanceMrtTrack(&state, reading, now)

	if fire && track.Token != "" {
		fired, fireErr := t.vibrator.FireMrtVibrate(ctx, notify.MrtVibrateEvent{
			ReminderID: track.ID, Token: track.Token, TrackID: track.ID,
		})
		if fireErr != nil {
			log.Warnf("[MRT_TRACK] action=advance event=vibrate_error track=%s error=%v", track.ID, fireErr)
		} else if fired {
			log.Infof("[MRT_TRACK] action=advance event=lead_fired track=%s remaining=%d", track.ID, newState.RemainingStops)
		}
	}

	t.publishState(ctx, newState)
	if mrtIsTerminal(newState.Status) {
		log.Infof("[MRT_TRACK] action=advance event=ended track=%s status=%s", track.ID, newState.Status)
		if expireErr := t.store.ExpireMrtTrack(ctx, track.ID); expireErr != nil {
			log.Warnf("[MRT_TRACK] action=advance event=expire_error track=%s error=%v", track.ID, expireErr)
		}
	}
}

// publishState writes the session state to its Redis key (short TTL once
// terminal so it lingers only long enough for connected watchers) and publishes
// it on the session channel.
func (t *mrtTracker) publishState(ctx context.Context, state *models.MrtTrackState) {
	pb, err := proto.Marshal(state)
	if err != nil {
		log.Warnf("[MRT_TRACK] action=publish event=encode_error track=%s error=%v", state.TrackId, err)
		return
	}
	ttl := mrtTrackActiveTTL
	if mrtIsTerminal(state.Status) {
		ttl = mrtTrackEndedTTL
	}
	rc := t.rc.WithContext(ctx)
	if err := rc.Set(shared.MrtTrackKey(state.TrackId), pb, ttl).Err(); err != nil {
		log.Warnf("[MRT_TRACK] action=publish event=set_error track=%s error=%v", state.TrackId, err)
		return
	}
	if err := rc.Publish(shared.MrtTrackChannel(state.TrackId), pb).Err(); err != nil {
		log.Warnf("[MRT_TRACK] action=publish event=publish_error track=%s error=%v", state.TrackId, err)
	}
}

// readPosition acquires one position reading for a due session: GetTrainInfo
// first (one call per hop), falling back to the already-ingested mrt_live stream
// by TripId when GetTrainInfo is empty. It is the impure counterpart of
// advanceMrtTrack.
func (t *mrtTracker) readPosition(ctx context.Context, state *models.MrtTrackState) mrtReading {
	info, ok, err := t.trtc.GetTrainInfo(ctx, state.CarId)
	if err != nil {
		log.Warnf("[MRT_TRACK] action=read event=traininfo_error track=%s error=%v", state.TrackId, err)
		return mrtReading{}
	}
	if ok {
		if info.TripID != state.TripId {
			// The carID now reports a different trip — the train re-tripped or
			// turned around, so the binding no longer follows this rider's ride.
			return mrtReading{lost: true}
		}
		idx := mrtResolvePathIndex(state.PathStationNames, info.StnName)
		countdown, hasCountdown := parseTrtcTrainCountdown(info.CountdownTime)
		if idx < 0 {
			// An empty StnName is a transient mid-run gap (retry); a non-empty name
			// that is not on the stored path means the train left the path.
			if strings.TrimSpace(strings.TrimSuffix(info.StnName, "站")) == "" {
				return mrtReading{gotInfo: true}
			}
			return mrtReading{lost: true}
		}
		return mrtReading{nextIndex: idx, countdown: countdown, hasCountdown: hasCountdown, gotInfo: true, resolved: true}
	}
	// GetTrainInfo empty: advance from mrt_live by TripId until it recovers.
	if idx, found := t.fallbackFromLive(ctx, state); found {
		return mrtReading{nextIndex: idx, resolved: true}
	}
	return mrtReading{}
}

// fallbackFromLive scans the ingested TRTC mrt_live keys for path stations ahead
// of the current position and returns the earliest one whose live arrival row
// carries this session's TripId — the train is just before that station. The
// terminal is the session's direction field; each path station's line comes from
// its ID prefix.
func (t *mrtTracker) fallbackFromLive(ctx context.Context, state *models.MrtTrackState) (int, bool) {
	if len(state.PathStationIds) == 0 {
		return 0, false
	}
	rc := t.rc.WithContext(ctx)
	// The terminal is the last station on the board→terminal path; it is part of
	// the mrt_live key identity (a station has simultaneous arrivals per direction).
	terminal := state.PathStationIds[len(state.PathStationIds)-1]
	start := int(state.CurrentIndex) + 1
	for idx := start; idx < len(state.PathStationIds); idx++ {
		station := state.PathStationIds[idx]
		line := trtcLinePrefix(station)
		raw, err := rc.Get(shared.MrtLiveKey("TRTC", station, line, terminal)).Bytes()
		if err != nil {
			continue
		}
		var live models.MrtLive
		if err := proto.Unmarshal(raw, &live); err != nil {
			continue
		}
		if live.TrainNumber == state.TripId {
			return idx, true
		}
	}
	return 0, false
}

// mrtReading is one resolved position observation, the pure input to
// advanceMrtTrack. nextIndex is the path index of the train's next station.
// resolved distinguishes "the train is at nextIndex" from "no position this
// tick". gotInfo means GetTrainInfo answered (so its countdown schedules the
// next poll); a fallback or empty reading retries on the short interval. lost
// means the reading places the train off the ride.
type mrtReading struct {
	nextIndex    int
	countdown    time.Duration
	hasCountdown bool
	gotInfo      bool
	resolved     bool
	lost         bool
}

// advanceMrtTrack is the pure session-advance decision: given the prior state, a
// position reading, and the clock, it returns the next state and whether the
// lead vibration should fire this tick. Position never moves backward. It sets
// the ending status (arrived / lost / stale) or the live status
// (tracking / lead_fired) and schedules the next poll. Firing is decided here
// but performed by the caller (which owns the once-only claim machinery).
func advanceMrtTrack(state *models.MrtTrackState, reading mrtReading, now time.Time) (*models.MrtTrackState, bool) {
	next := proto.Clone(state).(*models.MrtTrackState)
	target := next.TargetIndex

	// Within one stop of the alight station, a lost binding IS the arrival: at
	// the end of a run the carID re-trips (new TripId) or reports off-path, and
	// terminal alight stations are common — ending such a ride as "lost" would
	// misreport a completed ride. Reclassify by advancing past the target.
	finishing := state.CurrentIndex >= target-1
	if reading.lost {
		if !finishing {
			next.Status = mrtStatusLost
			next.NextPollAtUnix = 0
			return next, false
		}
		reading = mrtReading{nextIndex: int(target) + 1, resolved: true}
	}

	advanced := false
	if reading.resolved {
		// The reading is the train's next station; the last passed station is one
		// before it. Guard against any backward movement.
		candidate := int32(reading.nextIndex - 1)
		if candidate > next.CurrentIndex {
			next.CurrentIndex = candidate
			next.LastProgressAtUnix = now.Unix()
			advanced = true
		}
	}

	if next.CurrentIndex >= target {
		next.CurrentIndex = target
	}
	next.RemainingStops = target - next.CurrentIndex
	if next.RemainingStops < 0 {
		next.RemainingStops = 0
	}
	next.NextStationId, next.NextStationName = mrtNextStation(next)
	if target > 0 {
		next.Progress = float64(next.CurrentIndex) / float64(target)
	} else {
		next.Progress = 1
	}

	// fire is requested on every tick inside the lead zone, not just the first:
	// the claim/fired machinery makes delivery once-only, and re-requesting lets
	// a transiently failed (released) send retry on a later tick.
	fire := next.RemainingStops <= next.LeadStops

	switch {
	case next.CurrentIndex >= target:
		next.Status = mrtStatusArrived
		next.NextPollAtUnix = 0
		return next, fire
	case !advanced && mrtStale(state.LastProgressAtUnix, now):
		if finishing {
			// Stalled within one stop of the target (typically a persistently empty
			// GetTrainInfo at the end of a run): report the ride completed.
			next.CurrentIndex = target
			next.RemainingStops = 0
			next.Progress = 1
			next.NextStationId, next.NextStationName = mrtNextStation(next)
			next.Status = mrtStatusArrived
			next.NextPollAtUnix = 0
			return next, fire
		}
		next.Status = mrtStatusStale
		next.NextPollAtUnix = 0
		return next, false
	case next.RemainingStops <= next.LeadStops:
		next.Status = mrtStatusLeadFired
	default:
		next.Status = mrtStatusTracking
	}

	if reading.gotInfo && reading.hasCountdown && reading.countdown > 0 {
		next.NextPollAtUnix = now.Add(reading.countdown + mrtTrackPollBuffer).Unix()
	} else {
		next.NextPollAtUnix = now.Add(mrtTrackFallbackRetry).Unix()
	}
	return next, fire
}

// mrtNextStation returns the station the train is heading toward: the one after
// the last passed. Past the terminal it is empty.
func mrtNextStation(state *models.MrtTrackState) (string, string) {
	nextIdx := int(state.CurrentIndex) + 1
	if nextIdx < 0 || nextIdx >= len(state.PathStationIds) {
		return "", ""
	}
	name := ""
	if nextIdx < len(state.PathStationNames) {
		name = state.PathStationNames[nextIdx]
	}
	return state.PathStationIds[nextIdx], name
}

// mrtStale reports whether the position has not advanced within the stale
// window. A zero lastProgress (never advanced since creation) is measured from
// now on the first tick, so a session only goes stale after a real gap.
func mrtStale(lastProgressUnix int64, now time.Time) bool {
	if lastProgressUnix <= 0 {
		return false
	}
	return now.Sub(time.Unix(lastProgressUnix, 0)) > mrtTrackStaleAfter
}

// mrtIsTerminal reports whether a status is an ending (no further advancement).
func mrtIsTerminal(status string) bool {
	switch status {
	case mrtStatusArrived, mrtStatusLost, mrtStatusStale, mrtStatusCancelled:
		return true
	}
	return false
}

// mrtResolvePathIndex resolves a GetTrainInfo StnName to a path index, matching
// against the stored path names only. It strips the 「站」suffix and absorbs the
// same feed misspellings the live job aliases; an empty or off-path name is -1.
func mrtResolvePathIndex(names []string, stnName string) int {
	trimmed := strings.TrimSuffix(stnName, "站")
	if aliased, ok := trtcAliases[trimmed]; ok {
		trimmed = aliased
	}
	if strings.TrimSpace(trimmed) == "" {
		return -1
	}
	for i, name := range names {
		if name == trimmed || name == stnName {
			return i
		}
	}
	return -1
}

// parseTrtcTrainCountdown parses GetTrainInfo's "mm:ss" CountdownTime to the next
// station. Anything else carries no schedule, so the next poll uses the short
// fallback interval instead.
func parseTrtcTrainCountdown(s string) (time.Duration, bool) {
	minutes, seconds, found := strings.Cut(s, ":")
	if !found {
		return 0, false
	}
	mi, err1 := strconv.Atoi(minutes)
	si, err2 := strconv.Atoi(seconds)
	if err1 != nil || err2 != nil || mi < 0 || si < 0 || si > 59 {
		return 0, false
	}
	return time.Duration(mi*60+si) * time.Second, true
}
