import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wheres_the_car/core/live_activity/live_activity_channel.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_car/features/live_activity/data/leg_eta_source.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

/// Drives a journey/track Live Activity through [JourneySessionState].
///
/// Every [JourneyStarted] bumps [_generation]. The internal tick events
/// ([EtaTicked], [ProgressTicked], [PinnedStopsUpdated]) carry the
/// generation their source subscription was created under; handlers drop
/// anything that doesn't match the current generation. This matters because
/// cancelling a stream subscription is asynchronous — an event already
/// in flight from journey A's subscription can still land after journey B
/// has started, and without the generation check it would silently mix
/// into B's state (both journeys' waiting phase looks identical).
class JourneySessionBloc
    extends Bloc<JourneySessionEvent, JourneySessionState> {
  JourneySessionBloc({
    LegEtaStream etaStream = defaultLegEtaStream,
    RouteEtaStream routeEtaStream = defaultRouteEtaStream,
    LiveActivityChannel? channel,
    Stream<Position> Function()? positions,
    this.sessionTimeout = const Duration(hours: 8),
    this.trackOnlyLinger = const Duration(minutes: 2),
  }) : _etaStream = etaStream,
       _routeEtaStream = routeEtaStream,
       _channel = channel,
       _positions = positions,
       super(const JourneySessionState()) {
    on<JourneyStarted>(_onStarted);
    on<BoardConfirmed>(_onBoarded);
    on<AlightConfirmed>(_onAlighted);
    on<JourneyCancelled>(_onCancelled);
    on<EtaTicked>(_onEta);
    on<ProgressTicked>(_onProgress);
    on<PinnedStopsUpdated>(_onPinnedStopsUpdated);
  }

  final LegEtaStream _etaStream;
  final RouteEtaStream _routeEtaStream;
  final LiveActivityChannel? _channel;
  final Stream<Position> Function()? _positions;

  /// ActivityKit hard-caps activities at 8h; the session ends itself first.
  final Duration sessionTimeout;

  /// How long a trackOnly session keeps showing 進站中 after arrival before
  /// ending itself, when no follow-up ETA frame reveals the bus has left.
  final Duration trackOnlyLinger;

  StreamSubscription<Duration?>? _etaSub;
  StreamSubscription<List<BusStopEtaViewModel>>? _routeEtaSub;
  StreamSubscription<Position>? _posSub;
  Timer? _timeout;
  Timer? _linger;
  bool _trackedArrived = false;

  /// Bumped on every [JourneyStarted]; see class doc.
  int _generation = 0;

  /// Lease on the shared [LiveActivityChannel]'s current activity, handed
  /// back by `start`/`startBoard`. Null until this journey has one.
  int? _lease;

  Future<void> _onStarted(
    JourneyStarted event,
    Emitter<JourneySessionState> emit,
  ) async {
    if (event.legs.isEmpty) return;
    _timeout?.cancel();
    _timeout = Timer(sessionTimeout, () => add(const JourneyCancelled()));
    _linger?.cancel();
    _trackedArrived = false;
    final generation = ++_generation;
    emit(
      JourneySessionState(
        phase: JourneyPhase.waiting,
        legs: event.legs,
        trackOnly: event.trackOnly,
        plate: event.plate,
      ),
    );
    _subscribeEta(event.legs.first, generation);
    _subscribeRouteEta(
      event.legs.first,
      event.trackOnly,
      event.plate,
      generation,
    );
    _lease = await _channel?.start(_content(state));
  }

  void _onBoarded(BoardConfirmed _, Emitter<JourneySessionState> emit) {
    if (state.phase != JourneyPhase.waiting || state.trackOnly) return;
    unawaited(_etaSub?.cancel());
    emit(
      state.copyWith(
        phase: JourneyPhase.riding,
        clearEta: true,
        nextStopIndex: 0,
        suggestBoarding: false,
      ),
    );
    _subscribePositions();
    _pushUpdate();
  }

  void _onAlighted(AlightConfirmed _, Emitter<JourneySessionState> emit) {
    if (state.phase != JourneyPhase.riding) return;
    unawaited(_posSub?.cancel());
    if (state.isLastLeg) {
      _end(emit);
      return;
    }
    final next = state.legIndex + 1;
    emit(
      state.copyWith(
        phase: JourneyPhase.waiting,
        legIndex: next,
        clearEta: true,
        nextStopIndex: 0,
        suggestBoarding: false,
      ),
    );
    _subscribeEta(state.legs[next], _generation);
    _pushUpdate();
  }

  void _onCancelled(JourneyCancelled _, Emitter<JourneySessionState> emit) {
    if (state.phase == JourneyPhase.idle) return;
    _end(emit);
  }

  void _onEta(EtaTicked event, Emitter<JourneySessionState> emit) {
    if (event.generation != _generation) return; // stale journey
    if (state.phase != JourneyPhase.waiting) return;
    final arrived = event.eta != null && event.eta! <= Duration.zero;
    // trackOnly never rides, so 進站中 is the terminal display, not a
    // boarding prompt.
    emit(
      state.copyWith(
        eta: event.eta,
        suggestBoarding: arrived && !state.trackOnly,
      ),
    );
    _pushUpdate();
    if (!state.trackOnly) return;
    if (arrived && !_trackedArrived) {
      _trackedArrived = true;
      _linger = Timer(trackOnlyLinger, () => add(const JourneyCancelled()));
    } else if (_trackedArrived &&
        event.eta != null &&
        event.eta! > const Duration(minutes: 1)) {
      // The ETA jumped back up after arrival: the tracked bus has left and
      // the stream now counts down the following one — end the session.
      add(const JourneyCancelled());
    }
  }

  void _onProgress(ProgressTicked event, Emitter<JourneySessionState> emit) {
    if (event.generation != _generation) return; // stale journey
    if (state.phase != JourneyPhase.riding) return;
    if (event.nextStopIndex <= state.nextStopIndex) return;
    emit(state.copyWith(nextStopIndex: event.nextStopIndex));
    _pushUpdate();
  }

  void _onPinnedStopsUpdated(
    PinnedStopsUpdated event,
    Emitter<JourneySessionState> emit,
  ) {
    if (event.generation != _generation) return; // stale journey
    if (state.phase != JourneyPhase.waiting) return;
    // A frame that can't resolve the target stop or the pinned plate (bus
    // momentarily between stops) leaves the prior stops-remaining in place
    // rather than blanking the Live Activity's 還剩 N 站 back to null.
    if (event.stopsRemaining == null) return;
    emit(state.copyWith(pinnedStopsRemaining: event.stopsRemaining));
    _pushUpdate();
  }

  void _end(Emitter<JourneySessionState> emit) {
    unawaited(_etaSub?.cancel());
    unawaited(_routeEtaSub?.cancel());
    unawaited(_posSub?.cancel());
    _timeout?.cancel();
    _linger?.cancel();
    emit(state.copyWith(phase: JourneyPhase.done, suggestBoarding: false));
    final lease = _lease;
    _lease = null;
    if (lease != null) unawaited(_channel?.stop(lease));
  }

  /// Pushes [_content] through the shared channel under this journey's
  /// current lease; a no-op once another owner has superseded it.
  void _pushUpdate() {
    final lease = _lease;
    if (lease != null) unawaited(_channel?.update(lease, _content(state)));
  }

  void _subscribeEta(JourneyLeg leg, int generation) {
    unawaited(_etaSub?.cancel());
    // Stream error (gRPC drop) → fall back to the scheduled countdown, per
    // spec: never blank the card mid-journey.
    _etaSub = _etaStream(leg).listen(
      (eta) => add(EtaTicked(eta, generation: generation)),
      onError: (Object _) {
        unawaited(_etaSub?.cancel());
        _etaSub = scheduledCountdown(leg.scheduledDeparture).listen(
          (eta) => add(EtaTicked(eta, generation: generation)),
        );
      },
    );
  }

  /// A pinned (plate-tracked) trackOnly session additionally tracks the
  /// pinned vehicle's live stop-distance from the alight stop. Unpinned and
  /// MaaS (non-trackOnly) sessions never subscribe here.
  void _subscribeRouteEta(
    JourneyLeg leg,
    bool trackOnly,
    String? plate,
    int generation,
  ) {
    unawaited(_routeEtaSub?.cancel());
    _routeEtaSub = null;
    if (!trackOnly || plate == null) return;
    final routeKey = leg.identity.routeKey;
    if (routeKey.isEmpty) return;
    // Stream error (gRPC drop) → stopsRemaining simply stops updating; the
    // card keeps its last-known value rather than going blank.
    _routeEtaSub = _routeEtaStream(routeKey).listen(
      (etas) => add(
        PinnedStopsUpdated(
          _pinnedStopsRemaining(etas, leg, plate),
          generation: generation,
        ),
      ),
      onError: (Object _) {},
    );
  }

  /// Stops between the pinned vehicle's current position and the leg's
  /// alight stop, both located in [etas] by stop uid / vehicle plate. Null
  /// when either side hasn't resolved yet (target stop or the plate itself
  /// missing from the current frame).
  int? _pinnedStopsRemaining(
    List<BusStopEtaViewModel> etas,
    JourneyLeg leg,
    String plate,
  ) {
    final direction = leg.identity.direction;
    final inDirection = direction.isEmpty
        ? etas
        : etas.where((e) => '${e.direction}' == direction);

    BusStopEtaViewModel? target;
    BusStopEtaViewModel? plateStop;
    for (final e in inDirection) {
      if (e.stopUid == leg.identity.departureStopKey) target = e;
      if (e.vehicles.any((v) => v.plate == plate)) {
        if (plateStop == null || e.sequence < plateStop.sequence) {
          plateStop = e;
        }
      }
    }
    if (target == null || plateStop == null) return null;
    final diff = target.sequence - plateStop.sequence;
    return diff < 0 ? 0 : diff;
  }

  void _subscribePositions() {
    final positions = _positions;
    if (positions == null) return;
    unawaited(_posSub?.cancel());
    // Stream error (permission revoked mid-ride) → riding continues on manual
    // stop control; position-based progress simply stops updating.
    _posSub = positions().listen(_onPosition, onError: (Object _) {});
  }

  void _onPosition(Position pos) {
    final leg = state.currentLeg;
    if (leg == null || state.phase != JourneyPhase.riding) return;
    // Nearest upcoming stop wins; never move backwards (index is monotonic).
    var best = state.nextStopIndex;
    var bestDist = double.infinity;
    for (var i = state.nextStopIndex; i < leg.stopLocations.length; i++) {
      final p = leg.stopLocations[i];
      final d = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        p.lat,
        p.lng,
      );
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    if (best != state.nextStopIndex) {
      add(ProgressTicked(best, generation: _generation));
    }
  }

  LiveActivityContent _content(JourneySessionState s) {
    final leg = s.currentLeg!;
    final total = leg.stopLocations.length;
    final names = [...leg.stopNames, leg.alightStop];
    final nextName =
        s.phase == JourneyPhase.riding && s.nextStopIndex < names.length
        ? names[s.nextStopIndex]
        : leg.boardStop;
    return LiveActivityContent(
      mode: s.phase == JourneyPhase.riding ? 'riding' : 'waiting',
      type: leg.kind.name == 'metro' ? 'mrt' : leg.kind.name,
      routeOrTrain: leg.routeLabel,
      fromStation: leg.boardStop,
      nextStation: nextName,
      alightStation: leg.alightStop,
      remainingStops: s.plate != null
          ? s.pinnedStopsRemaining
          : (s.phase == JourneyPhase.riding ? total - s.nextStopIndex : null),
      progressPercent: s.phase == JourneyPhase.riding && total > 0
          ? s.nextStopIndex / total
          : 0.0,
      etaMs: s.eta == null
          ? null
          : DateTime.now().add(s.eta!).millisecondsSinceEpoch,
      walkMinutes: s.phase == JourneyPhase.waiting ? leg.leadingWalkMinutes : 0,
      plate: s.plate,
      routeNumber: leg.routeLabel.split(' 往').first.trim(),
    );
  }

  @override
  Future<void> close() {
    unawaited(_etaSub?.cancel());
    unawaited(_routeEtaSub?.cancel());
    unawaited(_posSub?.cancel());
    _timeout?.cancel();
    _linger?.cancel();
    return super.close();
  }
}
