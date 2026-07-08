import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wheres_the_car/core/live_activity/live_activity_channel.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_car/features/live_activity/data/leg_eta_source.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

class JourneySessionBloc
    extends Bloc<JourneySessionEvent, JourneySessionState> {
  JourneySessionBloc({
    LegEtaStream etaStream = defaultLegEtaStream,
    LiveActivityChannel? channel,
    Stream<Position> Function()? positions,
    this.sessionTimeout = const Duration(hours: 8),
  }) : _etaStream = etaStream,
       _channel = channel,
       _positions = positions,
       super(const JourneySessionState()) {
    on<JourneyStarted>(_onStarted);
    on<BoardConfirmed>(_onBoarded);
    on<AlightConfirmed>(_onAlighted);
    on<JourneyCancelled>(_onCancelled);
    on<EtaTicked>(_onEta);
    on<ProgressTicked>(_onProgress);
  }

  final LegEtaStream _etaStream;
  final LiveActivityChannel? _channel;
  final Stream<Position> Function()? _positions;

  /// ActivityKit hard-caps activities at 8h; the session ends itself first.
  final Duration sessionTimeout;

  StreamSubscription<Duration?>? _etaSub;
  StreamSubscription<Position>? _posSub;
  Timer? _timeout;

  Future<void> _onStarted(
    JourneyStarted event,
    Emitter<JourneySessionState> emit,
  ) async {
    if (event.legs.isEmpty) return;
    _timeout?.cancel();
    _timeout = Timer(sessionTimeout, () => add(const JourneyCancelled()));
    emit(
      JourneySessionState(phase: JourneyPhase.waiting, legs: event.legs),
    );
    _subscribeEta(event.legs.first);
    await _channel?.start(_content(state));
  }

  void _onBoarded(BoardConfirmed _, Emitter<JourneySessionState> emit) {
    if (state.phase != JourneyPhase.waiting) return;
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
    unawaited(_channel?.update(_content(state)));
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
    _subscribeEta(state.legs[next]);
    unawaited(_channel?.update(_content(state)));
  }

  void _onCancelled(JourneyCancelled _, Emitter<JourneySessionState> emit) {
    if (state.phase == JourneyPhase.idle) return;
    _end(emit);
  }

  void _onEta(EtaTicked event, Emitter<JourneySessionState> emit) {
    if (state.phase != JourneyPhase.waiting) return;
    final suggest = event.eta != null && event.eta! <= Duration.zero;
    emit(state.copyWith(eta: event.eta, suggestBoarding: suggest));
    unawaited(_channel?.update(_content(state)));
  }

  void _onProgress(ProgressTicked event, Emitter<JourneySessionState> emit) {
    if (state.phase != JourneyPhase.riding) return;
    if (event.nextStopIndex <= state.nextStopIndex) return;
    emit(state.copyWith(nextStopIndex: event.nextStopIndex));
    unawaited(_channel?.update(_content(state)));
  }

  void _end(Emitter<JourneySessionState> emit) {
    unawaited(_etaSub?.cancel());
    unawaited(_posSub?.cancel());
    _timeout?.cancel();
    emit(state.copyWith(phase: JourneyPhase.done, suggestBoarding: false));
    unawaited(_channel?.stop());
  }

  void _subscribeEta(JourneyLeg leg) {
    unawaited(_etaSub?.cancel());
    // Stream error (gRPC drop) → fall back to the scheduled countdown, per
    // spec: never blank the card mid-journey.
    _etaSub = _etaStream(leg).listen(
      (eta) => add(EtaTicked(eta)),
      onError: (Object _) {
        unawaited(_etaSub?.cancel());
        _etaSub = scheduledCountdown(leg.scheduledDeparture)
            .listen((eta) => add(EtaTicked(eta)));
      },
    );
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
        pos.latitude, pos.longitude, p.lat, p.lng,
      );
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    if (best != state.nextStopIndex) add(ProgressTicked(best));
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
      remainingStops:
          s.phase == JourneyPhase.riding ? total - s.nextStopIndex : null,
      progressPercent:
          s.phase == JourneyPhase.riding && total > 0
              ? s.nextStopIndex / total
              : 0.0,
      etaMs: s.eta == null
          ? null
          : DateTime.now().add(s.eta!).millisecondsSinceEpoch,
      walkMinutes: s.phase == JourneyPhase.waiting
          ? leg.leadingWalkMinutes
          : 0,
    );
  }

  @override
  Future<void> close() {
    unawaited(_etaSub?.cancel());
    unawaited(_posSub?.cancel());
    _timeout?.cancel();
    return super.close();
  }
}
