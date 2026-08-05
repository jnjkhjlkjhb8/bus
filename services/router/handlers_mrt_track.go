package main

import (
	"context"
	"time"

	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
)

// This file implements the metro alight-reminder session RPCs on Mrt_Service
// (捷運下車提醒, ADR-0015): CreateTrack binds a carriage to a trip and opens the
// session, WatchTrack streams its evolving state, CancelTrack ends it. The
// functions tracker advances the live position; the router only creates,
// streams, and cancels.

// mrtTrackStore is the reminder-persistence surface the session RPCs need,
// satisfied by *firebaseStore. It is the same firebase_arrival_reminder table
// bus and rail reminders use, reused for metro sessions (route_type='mrt').
type mrtTrackStore interface {
	AuthorizeInstall(context.Context, string, []byte) (bool, error)
	CreateArrivalReminder(context.Context, FirebaseArrivalReminder) error
	CancelArrivalReminder(context.Context, string, string) (bool, error)
}

// mrtTrainInfo is the GetTrainInfo seam used to verify a car binding at session
// creation, satisfied by *shared.TRTCTrainInfoClient and stubbed in tests.
type mrtTrainInfo interface {
	GetTrainInfo(ctx context.Context, carID string) (*shared.TRTCTrainInfo, bool, error)
}

// mrtLeadReminderID names a session's 提前提醒站 row, the sibling of the
// session-ID row that carries the 下車站 event (ADR-0020). Derived rather than
// stored so any caller holding a track ID can reach both rows.
func mrtLeadReminderID(trackID string) string { return trackID + ":lead" }

// mrtTrackSessionTTL keeps a session's reminder row and Redis state alive for a
// generous single ride; the functions tracker ends most sessions well before it.
const mrtTrackSessionTTL = 3 * time.Hour

// mrtTrackEndedStateTTL keeps a cancelled session's final state briefly so a
// connected watcher receives the ending before the key disappears.
const mrtTrackEndedStateTTL = 60 * time.Second

// CreateTrack opens a metro alight-reminder session. It validates that the
// target is strictly ahead on the board→terminal path (BFS over mrt_adjacency,
// same-line edges only — InvalidArgument "這班車不到該站" otherwise) and that the
// carID resolves to a live trip (GetTrainInfo — NotFound "查無此車" on empty),
// persists the session in firebase_arrival_reminder, seeds its Redis state, and
// returns the initial state.
func (s *MrtServer) CreateTrack(ctx context.Context, request *pb.CreateMrtTrackRequest) (*pb.MrtTrackState, error) {
	if !ValidText(request.GetInstallId(), 128) || !ValidText(request.GetCarId(), 32) ||
		!ValidText(request.GetBoardStationId(), 32) || !ValidText(request.GetDestStationId(), 32) ||
		!ValidText(request.GetTargetStationId(), 32) {
		return nil, status.Error(codes.InvalidArgument, "install_id, car_id, and station IDs are required")
	}
	if request.System != "TRTC" {
		return nil, status.Error(codes.FailedPrecondition, "metro alight reminders are supported for TRTC only")
	}
	// lead_stops reuses the reminders lead_minutes column. 0 is the default
	// (no early warning, ADR-0020) and is stored on the alight row as 1 so the
	// column's 1..120 CHECK still holds — the lead row, which is what a lead
	// actually produces, simply is not written at 0.
	if request.LeadStops < 0 || request.LeadStops > 120 {
		return nil, status.Error(codes.InvalidArgument, "lead_stops must be between 0 and 120")
	}
	// Card display strings are stored verbatim and later rendered on a system
	// notification, so they are bounded here rather than trusted. Empty is legal
	// throughout: an app that predates ADR-0018 sends none, which leaves the
	// server unable to push a card — exactly today's behaviour.
	if len(request.VehicleLabel) > 64 || len(request.LineCode) > 8 || !validHexColor(request.LineColorHex) {
		return nil, status.Error(codes.InvalidArgument, "invalid card display fields")
	}
	if err := s.authorizeInstall(ctx, request.InstallId); err != nil {
		return nil, err
	}

	adjacency, err := s.loadMrtAdjacency(ctx, "TRTC")
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to load metro adjacency")
	}
	path, ok := mrtBFSPath(adjacency, request.BoardStationId, request.DestStationId)
	if !ok {
		return nil, status.Error(codes.InvalidArgument, "這班車不到該站")
	}
	targetIndex, ok := mrtTargetIndex(path, request.TargetStationId)
	if !ok {
		return nil, status.Error(codes.InvalidArgument, "這班車不到該站")
	}

	info, found, err := s.trtc.GetTrainInfo(ctx, request.CarId)
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to verify car binding")
	}
	if !found {
		return nil, status.Error(codes.NotFound, "查無此車")
	}

	names, err := s.mrtStationNames(ctx, path)
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to load station names")
	}

	trackID, err := NewUUIDv4()
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to create session ID")
	}
	now := s.clock()
	expiresAt := now.Add(mrtTrackSessionTTL)
	// Reminders-table mapping for a metro session (ADR-0015): plate=carID,
	// route_key=TripId, stop_key=target, direction=terminal, lead_minutes reused
	// as the stops-based lead, fire_at NULL (fired off live position, like bus).
	//
	// Two rows, one per buzz (ADR-0020): the session's own ID carries the
	// 下車站 event, and mrtLeadReminderID(trackID) carries the 提前提醒站 one.
	// They are separate rows because the claim/fired machinery is per-row —
	// one row could only ever deliver one of the two vibrations.
	storedLead := max(request.LeadStops, 1)
	stored := FirebaseArrivalReminder{
		ReminderID: trackID, InstallID: request.InstallId, RouteType: "mrt", RouteKey: info.TripID,
		StopKey: request.TargetStationId, Direction: request.DestStationId, LeadMinutes: storedLead,
		ExpiresAt: expiresAt, Status: ReminderPending, Plate: request.CarId,
		AlightEvent: "alight",
	}
	if err := s.store.CreateArrivalReminder(ctx, stored); err != nil {
		return nil, status.Error(codes.Internal, "failed to save metro session")
	}
	if request.LeadStops > 0 {
		lead := stored
		lead.ReminderID = mrtLeadReminderID(trackID)
		lead.AlightEvent = "lead"
		if err := s.store.CreateArrivalReminder(ctx, lead); err != nil {
			return nil, status.Error(codes.Internal, "failed to save metro session")
		}
	}

	nextStationID, nextStationName := "", ""
	if len(path) > 1 {
		nextStationID = path[1]
		if len(names) > 1 {
			nextStationName = names[1]
		}
	}
	state := &pb.MrtTrackState{
		TrackId: trackID, TripId: info.TripID, CarId: request.CarId,
		PathStationIds: path, PathStationNames: names,
		TargetIndex: targetIndex, CurrentIndex: 0, RemainingStops: targetIndex,
		NextStationId: nextStationID, NextStationName: nextStationName, Progress: 0,
		Status: "tracking", NextPollAtUnix: now.Unix(), LeadStops: request.LeadStops,
		System: "TRTC",
		// Seed the stale clock at creation: a session whose binding never advances
		// at all must still end after the stale window, not poll until expires_at.
		LastProgressAtUnix: now.Unix(),
		// Display invariants the tracker echoes into every pushed card refresh
		// (ADR-0018). Stored, never interpreted: a localized line name and a
		// colour are the app's vocabulary, not the server's.
		VehicleLabel: request.VehicleLabel,
		LineCode:     request.LineCode,
		LineColorHex: request.LineColorHex,
	}
	if err := s.writeTrackState(ctx, state, mrtTrackSessionTTL); err != nil {
		return nil, status.Error(codes.Internal, "failed to seed metro session state")
	}
	zap.S().Infow("log",
		"component", "mrt_track",
		"action", "create",
		"track", trackID,
		"trip", info.TripID,
		"car", request.CarId,
		"target_index", targetIndex,
	)
	return state, nil
}

// WatchTrack streams a session's state: it seeds from the current Redis state key
// then forwards each published update until the client disconnects — the same
// seed-then-subscribe pattern as the metro arrival stream.
func (s *MrtServer) WatchTrack(request *pb.WatchMrtTrackRequest, stream pb.Mrt_Service_WatchTrackServer) error {
	if !ValidText(request.GetTrackId(), 64) {
		return status.Error(codes.InvalidArgument, "track_id is required")
	}
	send := func(data []byte) error {
		state, err := DecodePayload(data, &pb.MrtTrackState{})
		if err != nil {
			return err
		}
		return stream.Send(state)
	}
	return StreamLive(stream.Context(), s.live, LiveStreamSpec{
		channel:  shared.MrtTrackChannel(request.TrackId),
		seedKeys: []string{shared.MrtTrackKey(request.TrackId)},
	}, send)
}

// CancelTrack ends a caller-owned session: it marks the reminder row cancelled
// (NotFound when no matching pending row exists), publishes a final cancelled
// state, and short-TTLs the state key so watchers see the ending and then the
// key expires.
func (s *MrtServer) CancelTrack(ctx context.Context, request *pb.CancelMrtTrackRequest) (*pb.MrtTrackAck, error) {
	if !ValidText(request.GetInstallId(), 128) || !ValidText(request.GetTrackId(), 64) {
		return nil, status.Error(codes.InvalidArgument, "install_id and track_id are required")
	}
	if err := s.authorizeInstall(ctx, request.InstallId); err != nil {
		return nil, err
	}
	cancelled, err := s.store.CancelArrivalReminder(ctx, request.TrackId, request.InstallId)
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to cancel metro session")
	}
	if !cancelled {
		return nil, status.Error(codes.NotFound, "metro session not found")
	}
	// The lead row only exists above 提前站數 0, and it may already have fired;
	// either way "no pending row" is the normal outcome, not a failure. Only a
	// database error is worth reporting, and not at the cost of a cancel that
	// already succeeded on the row the session is named after.
	if _, leadErr := s.store.CancelArrivalReminder(ctx, mrtLeadReminderID(request.TrackId), request.InstallId); leadErr != nil {
		zap.S().Warnw("lead row error",
			"component", "mrt_track",
			"action", "cancel",
			"event", "lead_row_error",
			"track", request.TrackId,
			"err", leadErr,
		)
	}
	s.publishCancelledState(ctx, request.TrackId)
	return &pb.MrtTrackAck{Ok: true}, nil
}

// SetTrackPushToken stores the ActivityKit push token of the card showing a
// caller-owned session, so the functions tracker can refresh that card while the
// app is suspended (ADR-0018). An empty token clears the key — the app sends
// that when tracking ends, and an absent key simply means "no iOS card to push".
//
// The token lives beside the session state rather than on the device row
// because it is per-activity: it dies with the card, so tying its lifetime to
// the session's TTL leaves nothing to clean up.
func (s *MrtServer) SetTrackPushToken(ctx context.Context, request *pb.SetMrtTrackPushTokenRequest) (*pb.MrtTrackAck, error) {
	if !ValidText(request.GetInstallId(), 128) || !ValidText(request.GetTrackId(), 64) {
		return nil, status.Error(codes.InvalidArgument, "install_id and track_id are required")
	}
	// APNs tokens are lowercase hex; anything else never reaches Apple, so it is
	// rejected at the door rather than stored and retried every station hop.
	if !validPushToken(request.GetPushToken()) {
		return nil, status.Error(codes.InvalidArgument, "push_token must be hex")
	}
	if err := s.authorizeInstall(ctx, request.InstallId); err != nil {
		return nil, err
	}
	key := shared.MrtTrackPushTokenKey(request.TrackId)
	var err error
	if request.PushToken == "" {
		err = s.rc.Del(ctx, key).Err()
	} else {
		err = s.rc.Set(ctx, key, request.PushToken, mrtTrackSessionTTL).Err()
	}
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to store push token")
	}
	return &pb.MrtTrackAck{Ok: true}, nil
}

// validHexColor accepts an empty value or `#RRGGBB`, the form the app's line
// colour table produces.
func validHexColor(value string) bool {
	if value == "" {
		return true
	}
	if len(value) != 7 || value[0] != '#' {
		return false
	}
	for _, r := range value[1:] {
		if !isHexDigit(r) {
			return false
		}
	}
	return true
}

// validPushToken accepts an empty value (the clear) or a bounded hex string.
func validPushToken(value string) bool {
	if len(value) > 256 {
		return false
	}
	for _, r := range value {
		if !isHexDigit(r) {
			return false
		}
	}
	return true
}

func isHexDigit(r rune) bool {
	return (r >= '0' && r <= '9') || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F')
}

// publishCancelledState marks the current session state cancelled (or builds a
// minimal one if the key is already gone) and re-publishes it with a short TTL.
// A Redis failure here is logged, not fatal: the reminder row is already
// cancelled, so the tracker will not advance the session regardless.
func (s *MrtServer) publishCancelledState(ctx context.Context, trackID string) {
	publishCancelledTrackState(ctx, s.rc, trackID)
}

// publishCancelledTrackState is the same ending written by whichever path
// cancelled the session — the gRPC CancelTrack, or the card's own 取消追蹤 over
// HTTP when no engine is alive to make that call (FDPL-65).
func publishCancelledTrackState(ctx context.Context, rc *redis.Client, trackID string) {
	state := &pb.MrtTrackState{TrackId: trackID, System: "TRTC"}
	if raw, err := rc.Get(ctx, shared.MrtTrackKey(trackID)).Bytes(); err == nil {
		if decoded, decodeErr := DecodePayload(raw, &pb.MrtTrackState{}); decodeErr == nil {
			state = decoded
		}
	}
	state.Status = "cancelled"
	state.NextPollAtUnix = 0
	if err := writeTrackState(ctx, rc, state, mrtTrackEndedStateTTL); err != nil {
		zap.S().Warnw("publish error",
			"component", "mrt_track",
			"action", "cancel",
			"event", "publish_error",
			"track", trackID,
			"err", err,
		)
	}
}

func (s *MrtServer) writeTrackState(ctx context.Context, state *pb.MrtTrackState, ttl time.Duration) error {
	return writeTrackState(ctx, s.rc, state, ttl)
}

// writeTrackState marshals a state, stores it under MrtTrackKey with ttl, and
// publishes it on MrtTrackChannel so any established watcher receives it.
func writeTrackState(ctx context.Context, rc *redis.Client, state *pb.MrtTrackState, ttl time.Duration) error {
	payload, err := proto.Marshal(state)
	if err != nil {
		return err
	}
	if err := rc.Set(ctx, shared.MrtTrackKey(state.TrackId), payload, ttl).Err(); err != nil {
		return err
	}
	return rc.Publish(ctx, shared.MrtTrackChannel(state.TrackId), payload).Err()
}

// clock returns the server's now function, defaulting to time.Now when unset so
// tests can pin the session clock.
func (s *MrtServer) clock() time.Time {
	if s.now != nil {
		return s.now()
	}
	return time.Now()
}

// authorizeInstall verifies the caller owns the installation, reusing the
// install-secret machinery the Firebase reminder RPCs use.
func (s *MrtServer) authorizeInstall(ctx context.Context, installID string) error {
	secretHash, err := InstallationSecretHash(ctx, installID)
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

// loadMrtAdjacency reads a system's same-line adjacency edges into a directed
// map. The table already stores both directions of every segment, so BFS over
// this map is an undirected walk within a line (ADR-0015).
func (s *MrtServer) loadMrtAdjacency(ctx context.Context, system string) (map[string][]string, error) {
	rows, err := s.db.Query(ctx, `SELECT from_station_id, to_station_id FROM mrt_adjacency WHERE system = $1`, system)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	adjacency := map[string][]string{}
	for rows.Next() {
		var from, to string
		if err := rows.Scan(&from, &to); err != nil {
			return nil, err
		}
		adjacency[from] = append(adjacency[from], to)
	}
	return adjacency, rows.Err()
}

// mrtStationNames returns the display names for the path stations in path order,
// leaving an unmatched station's name empty rather than failing the session.
func (s *MrtServer) mrtStationNames(ctx context.Context, path []string) ([]string, error) {
	rows, err := s.db.Query(ctx, `SELECT station_id, name FROM mrt_station WHERE system = 'TRTC' AND station_id = ANY($1)`, path)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	byID := map[string]string{}
	for rows.Next() {
		var id, name string
		if err := rows.Scan(&id, &name); err != nil {
			return nil, err
		}
		byID[id] = name
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	names := make([]string, len(path))
	for i, id := range path {
		names[i] = byID[id]
	}
	return names, nil
}

// mrtBFSPath returns the shortest board→terminal station sequence over the
// same-line adjacency graph, inclusive of both endpoints. Because the graph's
// only inter-line links are shared station IDs — and TRTC transfer stations
// carry a distinct ID per line — a component never spans two lines, so a
// terminal on another line is simply unreachable. ok is false when no path
// exists.
func mrtBFSPath(adjacency map[string][]string, board, terminal string) ([]string, bool) {
	if board == terminal {
		return nil, false
	}
	prev := map[string]string{board: ""}
	queue := []string{board}
	for len(queue) > 0 {
		node := queue[0]
		queue = queue[1:]
		if node == terminal {
			return mrtReconstruct(prev, terminal), true
		}
		for _, next := range adjacency[node] {
			if _, seen := prev[next]; seen {
				continue
			}
			prev[next] = node
			queue = append(queue, next)
		}
	}
	return nil, false
}

// mrtReconstruct walks the BFS predecessor map from terminal back to the root and
// returns the path in board→terminal order.
func mrtReconstruct(prev map[string]string, terminal string) []string {
	var reversed []string
	for node := terminal; node != ""; node = prev[node] {
		reversed = append(reversed, node)
	}
	path := make([]string, len(reversed))
	for i, node := range reversed {
		path[len(reversed)-1-i] = node
	}
	return path
}

// mrtTargetIndex returns the target station's position on the path. ok is false
// when the target is not strictly ahead of the board (index 0) — i.e. absent
// from the path or the board itself — which is the "這班車不到該站" rejection.
func mrtTargetIndex(path []string, target string) (int32, bool) {
	for i, station := range path {
		if station == target {
			if i == 0 {
				return 0, false
			}
			return int32(i), true
		}
	}
	return 0, false
}
