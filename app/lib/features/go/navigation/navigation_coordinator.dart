import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:wheres_the_bus/data/models/plan_models.dart';
import 'package:wheres_the_bus/data/tracking/journey_models.dart';
import 'package:wheres_the_bus/data/tracking/journey_session_bloc.dart';
import 'package:wheres_the_bus/data/tracking/journey_session_event.dart';
import 'package:wheres_the_bus/data/tracking/journey_session_state.dart';
import 'package:wheres_the_bus/features/go/bloc/plan_bloc.dart';
import 'package:wheres_the_bus/features/go/bloc/plan_event.dart';
import 'package:wheres_the_bus/features/go/widgets/transit_visuals.dart'
    show isWalk;

// GPS-noise tunables for decideNavAction. Bump these if real-world
// testing shows false triggers; the ceiling is "wide enough to fire near a
// stop, narrow enough not to fire from the next block over".
const _kWalkArrivalRadiusMeters = 40.0;
const _kBoardDepartRadiusMeters = 80.0;
const _kAlightArrivalRadiusMeters = 60.0;

// display-only radius for advancing the current turn-by-turn walk
// step to the next maneuver. Deliberately tighter than the leg-arrival radius:
// tuning it only changes which instruction line shows, never leg progress.
const _kWalkStepAdvanceRadiusMeters = 20.0;

/// What the autopilot decided to do with one GPS fix.
enum NavAction { none, board, alight, advance }

/// Pure: (active PlanBloc section, autopilot's own boarded flag, position) ->
/// action. Keyed off the coordinator's own `_lastAutoBoardedLeg` rather than
/// `JourneySession.phase` so the autopilot advances transit legs on GPS alone
/// even when Live Activity is off (JourneySession never leaves `idle` then).
/// No side effects; unit-tested exhaustively in isolation from the blocs.
NavAction decideNavAction({
  required PlanSection section,
  required bool boarded,
  required double lat,
  required double lon,
}) {
  if (isWalk(section)) {
    final arrival = section.arrival.location;
    final distance = Geolocator.distanceBetween(
      lat,
      lon,
      arrival.lat,
      arrival.lng,
    );
    return distance <= _kWalkArrivalRadiusMeters
        ? NavAction.advance
        : NavAction.none;
  }
  if (!boarded) {
    final departure = section.departure.location;
    final distance = Geolocator.distanceBetween(
      lat,
      lon,
      departure.lat,
      departure.lng,
    );
    return distance > _kBoardDepartRadiusMeters
        ? NavAction.board
        : NavAction.none;
  }
  final arrival = section.arrival.location;
  final distance = Geolocator.distanceBetween(
    lat,
    lon,
    arrival.lat,
    arrival.lng,
  );
  return distance <= _kAlightArrivalRadiusMeters
      ? NavAction.alight
      : NavAction.none;
}

/// Pure: advance the current walk-step index when the GPS fix reaches the next
/// maneuver point. Display-only — it never advances the leg. The index only
/// increases, so GPS jitter can never rewind the shown instruction.
int advanceWalkStep({
  required List<PlanWalkStep> steps,
  required int current,
  required double lat,
  required double lon,
}) {
  if (current >= steps.length - 1) return current;
  final next = steps[current + 1].location;
  final distance = Geolocator.distanceBetween(lat, lon, next.lat, next.lng);
  return distance <= _kWalkStepAdvanceRadiusMeters ? current + 1 : current;
}

// compass-throttle tunables for shouldApplyHeading. A heading only reaches
// the camera when it turns the map by more than _kHeadingMinDeltaDeg AND
// at least _kHeadingMinInterval has elapsed since the last applied one —
// enough to read as continuous rotation without flooding moveCamera (~5/sec
// ceiling). Widen the delta if the map jitters while the phone sits still;
// shorten the interval if in-place rotation feels laggy.
const _kHeadingMinDeltaDeg = 3.0;
const _kHeadingMinInterval = Duration(milliseconds: 200);

/// Pure: whether a fresh compass [next] heading should be pushed to the camera,
/// given the [last] applied bearing (null if none yet) and [sinceLast] elapsed
/// since the last applied heading. The first heading always applies; after
/// that it must clear both the rate limit and the angular threshold. The delta
/// is measured on the circle, so 359°→1° is 2° (below threshold), not 358°.
bool shouldApplyHeading({
  required double? last,
  required double next,
  required Duration sinceLast,
}) {
  if (last == null) return true;
  if (sinceLast < _kHeadingMinInterval) return false;
  final raw = (next - last).abs() % 360;
  final delta = raw > 180 ? 360 - raw : raw;
  return delta > _kHeadingMinDeltaDeg;
}

class NavigationAdvanceResult {
  const NavigationAdvanceResult({
    required this.arrived,
    this.nextCameraPoint,
  });

  final bool arrived;
  final PlanPoint? nextCameraPoint;
}

class NavigationCoordinator {
  NavigationCoordinator({
    required PlanBloc planBloc,
    required JourneySessionBloc journeySessionBloc,
    required bool Function() liveActivityEnabled,
    Stream<Position> Function()? positions,
    // `arrived` mirrors advance()'s NavigationAdvanceResult.arrived; keeping
    // the callback shape a plain positional trio matches the other two args.
    // ignore: avoid_positional_boolean_parameters
    void Function(NavAction action, PlanPoint? cameraTarget, bool arrived)?
    onAutoAction,
    // A lone status flag reads fine positionally; matches onAutoAction's shape.
    // ignore: avoid_positional_boolean_parameters
    void Function(bool driving)? onAutopilotStatus,
    void Function(Position fix)? onFollowUpdate,
  }) : _planBloc = planBloc,
       _journeySessionBloc = journeySessionBloc,
       _liveActivityEnabled = liveActivityEnabled,
       _positions = positions,
       _onAutoAction = onAutoAction,
       _onAutopilotStatus = onAutopilotStatus,
       _onFollowUpdate = onFollowUpdate;

  final PlanBloc _planBloc;
  final JourneySessionBloc _journeySessionBloc;
  final bool Function() _liveActivityEnabled;
  final Stream<Position> Function()? _positions;
  // Mirrors the constructor parameter's positional trio; see its comment.
  // ignore: avoid_positional_boolean_parameters
  final void Function(NavAction action, PlanPoint? cameraTarget, bool arrived)?
  _onAutoAction;
  // Mirrors the constructor parameter's positional flag; see its comment.
  // ignore: avoid_positional_boolean_parameters
  final void Function(bool driving)? _onAutopilotStatus;
  // Raw fix passed to the UI on every tick so the camera can follow the user;
  // the UI owns the camera (MaaS navigation definition), the coordinator only
  // forwards the position it already subscribes to (no second GPS stream).
  final void Function(Position fix)? _onFollowUpdate;

  StreamSubscription<Position>? _posSub;

  /// Dedupe guard for [_onAutopilotStatus]: null until the first emission
  /// after `start()`, so the optimistic `true` fired there always emits even
  /// if a prior navigation last emitted `true` too.
  bool? _driving;

  /// Guards advance/alight against re-firing while a GPS fix lingers inside
  /// the trigger radius.
  int? _lastAutoAdvancedLeg;

  /// The autopilot's own record of which leg it has boarded — one of two
  /// sources `decideNavAction` reads (as `boarded`, alongside the live
  /// `JourneySession.phase`) to flip a transit leg from board-eligible to
  /// alight-eligible. Primary rather than sole source of truth: with Live
  /// Activity off, `JourneySession.phase` never leaves `idle`, so this flag
  /// is what keeps auto board/alight working at all. `BoardConfirmed` is
  /// still dispatched to keep the Live Activity in sync when it's on; it
  /// safely no-ops otherwise.
  int? _lastAutoBoardedLeg;

  Future<PlanPoint?> start({
    required PlanRoute route,
    required int routeIndex,
  }) async {
    _planBloc
      ..add(RouteSelected(index: routeIndex))
      ..add(const NavigationStarted());
    final legs = JourneyLeg.legsFromRoute(route);
    if (legs.isNotEmpty && _liveActivityEnabled()) {
      _journeySessionBloc.add(JourneyStarted(legs: legs));
    }
    _lastAutoAdvancedLeg = null;
    _lastAutoBoardedLeg = null;
    // Location is forced, so optimistically assume the autopilot is driving
    // as navigation starts — this keeps the manual buttons hidden from frame
    // one instead of flashing on before the first GPS fix arrives. Reset the
    // dedupe field first so this always re-emits, even if a prior navigation
    // last emitted `true` too.
    _driving = null;
    _setDriving(true);
    _subscribePositions();
    return route.firstPoint();
  }

  void _subscribePositions() {
    final positions = _positions;
    if (positions == null) return;
    unawaited(_posSub?.cancel());
    _posSub = positions().listen(
      (position) {
        _setDriving(true);
        _onFollowUpdate?.call(position);
        _onPosition(position);
      },
      onError: (Object _) => _setDriving(false),
      onDone: () => _setDriving(false),
    );
  }

  /// Emits [_onAutopilotStatus] only on an actual change, so the nav sheet
  /// doesn't rebuild on every GPS fix once the manual controls are already
  /// hidden.
  void _setDriving(bool v) {
    if (_driving == v) return;
    _driving = v;
    _onAutopilotStatus?.call(v);
  }

  void _onPosition(Position position) {
    final activeLeg = _planBloc.state.activeLegIndex;
    if (activeLeg == null) return;
    final route = _currentRoute();
    if (route == null) return;
    if (activeLeg >= route.sections.length) return;
    final section = route.sections[activeLeg];
    // Display-only: advance the turn-by-turn walk step. Never touches leg
    // advancement, which decideNavAction below still owns exclusively.
    if (isWalk(section) && section.walkSteps.isNotEmpty) {
      final current = _planBloc.state.activeWalkStepIndex;
      final next = advanceWalkStep(
        steps: section.walkSteps,
        current: current,
        lat: position.latitude,
        lon: position.longitude,
      );
      if (next != current) {
        _planBloc.add(WalkStepAdvanced(index: next));
      }
    }
    // A manual 我上車了 tap dispatches BoardConfirmed straight to
    // JourneySessionBloc, bypassing this coordinator, so `_lastAutoBoardedLeg`
    // alone would stay stale until the next auto-board. Honoring the live
    // phase too reflects a manual board immediately and avoids re-entering
    // the `board` branch (and its haptic) once already riding.
    final boarded =
        _lastAutoBoardedLeg == activeLeg ||
        _journeySessionBloc.state.phase == JourneyPhase.riding;
    final action = decideNavAction(
      section: section,
      boarded: boarded,
      lat: position.latitude,
      lon: position.longitude,
    );
    switch (action) {
      case NavAction.none:
        return;
      case NavAction.board:
        if (boarded) return;
        _lastAutoBoardedLeg = activeLeg;
        _journeySessionBloc.add(const BoardConfirmed());
        _onAutoAction?.call(NavAction.board, null, false);
      case NavAction.alight:
        if (_lastAutoAdvancedLeg == activeLeg) return;
        _lastAutoAdvancedLeg = activeLeg;
        _journeySessionBloc.add(const AlightConfirmed());
        unawaited(_autoAdvance(route, activeLeg, NavAction.alight));
      case NavAction.advance:
        if (_lastAutoAdvancedLeg == activeLeg) return;
        _lastAutoAdvancedLeg = activeLeg;
        unawaited(_autoAdvance(route, activeLeg, NavAction.advance));
    }
  }

  Future<void> _autoAdvance(
    PlanRoute route,
    int activeLeg,
    NavAction action,
  ) async {
    final result = await advance(route: route, activeLeg: activeLeg);
    _onAutoAction?.call(action, result.nextCameraPoint, result.arrived);
  }

  Future<NavigationAdvanceResult> advance({
    required PlanRoute route,
    required int activeLeg,
  }) async {
    if (activeLeg >= route.sections.length - 1) {
      await end();
      return const NavigationAdvanceResult(arrived: true);
    }
    final nextLeg = activeLeg + 1;
    _planBloc.add(StopArrived(legIndex: nextLeg, stopIndex: 0));
    return NavigationAdvanceResult(
      arrived: false,
      nextCameraPoint: route.firstPoint(leg: nextLeg),
    );
  }

  Future<void> end() async {
    unawaited(_posSub?.cancel());
    _planBloc.add(const NavigationEnded());
    _journeySessionBloc.add(const JourneyCancelled());
  }

  /// Called when JourneySession reaches `done` on its own (last transit leg
  /// alighted, or the ActivityKit cap). Route structure — not the live active
  /// index — decides whether that also ends the whole navigation: a trailing
  /// walk section after the last transit leg must keep running so the
  /// autopilot (or the manual button) can finish it.
  Future<bool> reconcileJourneyDone() async {
    final activeLeg = _planBloc.state.activeLegIndex;
    if (activeLeg == null) {
      unawaited(_posSub?.cancel());
      return false;
    }
    final route = _currentRoute();
    if (route != null && _hasTrailingWalk(route)) {
      // Last transit leg done but a final walk remains: keep navigating so
      // the walk finishes (autopilot on arrival, or the 完成此段 button). Do
      // NOT end, do NOT reset the camera, and KEEP the position subscription
      // alive.
      return false;
    }
    unawaited(_posSub?.cancel());
    _planBloc.add(const NavigationEnded());
    return true;
  }

  /// Resolves the route backing the current navigation, mirroring the lookup
  /// `_onPosition` performs against `PlanBloc`'s `selectedRouteIndex`/`result`.
  PlanRoute? _currentRoute() {
    final routeIndex = _planBloc.state.selectedRouteIndex;
    final routes = _planBloc.state.result?.routes;
    if (routeIndex == null || routes == null || routeIndex >= routes.length) {
      return null;
    }
    return routes[routeIndex];
  }

  /// True iff a walk section follows the route's last transit section, i.e.
  /// alighting the final transit leg does not yet mean the journey is over.
  bool _hasTrailingWalk(PlanRoute route) {
    final lastTransit = route.sections.lastIndexWhere((s) => !isWalk(s));
    return lastTransit != -1 && lastTransit < route.sections.length - 1;
  }

  /// Releases the GPS subscription without touching app-scoped blocs. Call
  /// this from the owning widget's `dispose()` so a screen torn down without
  /// going through `end()`/`reconcileJourneyDone()` (e.g. a route
  /// replacement that isn't a back-pop) doesn't keep polling GPS or
  /// dispatching autopilot transitions into blocs that outlive the screen.
  void dispose() {
    unawaited(_posSub?.cancel());
  }
}
