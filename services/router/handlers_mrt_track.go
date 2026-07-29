package main

import (
	"context"
	"time"

	pb "github.com/jnjkhjlkjhb8/wheres_the_bus/models"
	"github.com/jnjkhjlkjhb8/wheres_the_bus/services/shared"
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
	CreateArrivalReminder(context.Context, firebaseArrivalReminder) error
	CancelArrivalReminder(context.Context, string, string) (bool, error)
}

// mrtTrainInfo is the GetTrainInfo seam used to verify a car binding at session
// creation, satisfied by *shared.TRTCTrainInfoClient and stubbed in tests.
type mrtTrainInfo interface {
	GetTrainInfo(ctx context.Context, carID string) (*shared.TRTCTrainInfo, bool, error)
}

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
	if !validText(request.GetInstallId(), 128) || !validText(request.GetCarId(), 32) ||
		!validText(request.GetBoardStationId(), 32) || !validText(request.GetDestStationId(), 32) ||
		!validText(request.GetTargetStationId(), 32) {
		return nil, status.Error(codes.InvalidArgument, "install_id, car_id, and station IDs are required")
	}
	if request.System != "TRTC" {
		return nil, status.Error(codes.FailedPrecondition, "metro alight reminders are supported for TRTC only")
	}
	// lead_stops reuses the reminders lead_minutes column, whose CHECK bounds it
	// to 1..120; a stops-based lead is small but must satisfy that constraint.
	if request.LeadStops < 1 || request.LeadStops > 120 {
		return nil, status.Error(codes.InvalidArgument, "lead_stops must be between 1 and 120")
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

	trackID, err := newUUIDv4()
	if err != nil {
		return nil, status.Error(codes.Internal, "failed to create session ID")
	}
	now := s.clock()
	expiresAt := now.Add(mrtTrackSessionTTL)
	// Reminders-table mapping for a metro session (ADR-0015): plate=carID,
	// route_key=TripId, stop_key=target, direction=terminal, lead_minutes reused
	// as the stops-based lead, fire_at NULL (fired off live position, like bus).
	stored := firebaseArrivalReminder{
		ReminderID: trackID, InstallID: request.InstallId, RouteType: "mrt", RouteKey: info.TripID,
		StopKey: request.TargetStationId, Direction: request.DestStationId, LeadMinutes: request.LeadStops,
		ExpiresAt: expiresAt, Status: reminderPending, Plate: request.CarId,
	}
	if err := s.store.CreateArrivalReminder(ctx, stored); err != nil {
		return nil, status.Error(codes.Internal, "failed to save metro session")
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
	}
	if err := s.writeTrackState(ctx, state, mrtTrackSessionTTL); err != nil {
		return nil, status.Error(codes.Internal, "failed to seed metro session state")
	}
	log.Infof("[MRT_TRACK] action=create track=%s trip=%s car=%s target_index=%d", trackID, info.TripID, request.CarId, targetIndex)
	return state, nil
}

// WatchTrack streams a session's state: it seeds from the current Redis state key
// then forwards each published update until the client disconnects — the same
// seed-then-subscribe pattern as the metro arrival stream.
func (s *MrtServer) WatchTrack(request *pb.WatchMrtTrackRequest, stream pb.Mrt_Service_WatchTrackServer) error {
	if !validText(request.GetTrackId(), 64) {
		return status.Error(codes.InvalidArgument, "track_id is required")
	}
	send := func(data []byte) error {
		state, err := decodePayload(data, &pb.MrtTrackState{})
		if err != nil {
			return err
		}
		return stream.Send(state)
	}
	return streamLive(stream.Context(), s.live, liveStreamSpec{
		channel:  shared.MrtTrackChannel(request.TrackId),
		seedKeys: []string{shared.MrtTrackKey(request.TrackId)},
	}, send)
}

// CancelTrack ends a caller-owned session: it marks the reminder row cancelled
// (NotFound when no matching pending row exists), publishes a final cancelled
// state, and short-TTLs the state key so watchers see the ending and then the
// key expires.
func (s *MrtServer) CancelTrack(ctx context.Context, request *pb.CancelMrtTrackRequest) (*pb.MrtTrackAck, error) {
	if !validText(request.GetInstallId(), 128) || !validText(request.GetTrackId(), 64) {
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
	s.publishCancelledState(ctx, request.TrackId)
	return &pb.MrtTrackAck{Ok: true}, nil
}

// publishCancelledState marks the current session state cancelled (or builds a
// minimal one if the key is already gone) and re-publishes it with a short TTL.
// A Redis failure here is logged, not fatal: the reminder row is already
// cancelled, so the tracker will not advance the session regardless.
func (s *MrtServer) publishCancelledState(ctx context.Context, trackID string) {
	state := &pb.MrtTrackState{TrackId: trackID, System: "TRTC"}
	if raw, err := s.rc.WithContext(ctx).Get(shared.MrtTrackKey(trackID)).Bytes(); err == nil {
		if decoded, decodeErr := decodePayload(raw, &pb.MrtTrackState{}); decodeErr == nil {
			state = decoded
		}
	}
	state.Status = "cancelled"
	state.NextPollAtUnix = 0
	if err := s.writeTrackState(ctx, state, mrtTrackEndedStateTTL); err != nil {
		log.Warnf("[MRT_TRACK] action=cancel event=publish_error track=%s error=%v", trackID, err)
	}
}

// writeTrackState marshals a state, stores it under MrtTrackKey with ttl, and
// publishes it on MrtTrackChannel so any established watcher receives it.
func (s *MrtServer) writeTrackState(ctx context.Context, state *pb.MrtTrackState, ttl time.Duration) error {
	payload, err := proto.Marshal(state)
	if err != nil {
		return err
	}
	rc := s.rc.WithContext(ctx)
	if err := rc.Set(shared.MrtTrackKey(state.TrackId), payload, ttl).Err(); err != nil {
		return err
	}
	return rc.Publish(shared.MrtTrackChannel(state.TrackId), payload).Err()
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
