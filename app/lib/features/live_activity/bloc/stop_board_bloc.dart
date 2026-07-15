import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/live_activity/live_activity_channel.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/repositories/bus_repository.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/stop_board_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/stop_board_state.dart';

/// Routes shown on the stop-board Live Activity, ranked soonest-first.
const _maxBoardRows = 4;

/// Drives the stop-board Live Activity (every route serving one stop, ranked
/// by soonest ETA) from [BusRepository.stationEta].
///
/// Shares the single [LiveActivityChannel] with [JourneySessionBloc]'s
/// journey/track card — only one Live Activity can exist at a time, so
/// [StopBoardStarted] cancels any live journey session first (mutual
/// exclusion). Each owner holds its own lease on the channel (see
/// [LiveActivityChannel] class doc), so a delayed command from whichever
/// side lost the race is a no-op rather than clobbering the winner.
class StopBoardBloc extends Bloc<StopBoardEvent, StopBoardState> {
  StopBoardBloc({
    required LiveActivityChannel channel,
    required JourneySessionBloc session,
    Stream<List<BusStopArrival>> Function(String city, String stopKey)?
    etaSource,
  }) : _channel = channel,
       _session = session,
       _etaSource = etaSource ?? BusRepository.instance.stationEta,
       super(const StopBoardState()) {
    on<StopBoardStarted>(_onStarted);
    on<StopBoardStopped>(_onStopped);
    on<BoardArrivalsReceived>(_onArrivals);
  }

  final LiveActivityChannel _channel;
  final JourneySessionBloc _session;
  final Stream<List<BusStopArrival>> Function(String city, String stopKey)
  _etaSource;

  StreamSubscription<List<BusStopArrival>>? _sub;
  int? _lease;

  /// Set synchronously before the first startBoard's await. Bloc's default
  /// event transformer runs handlers concurrently, so a second arrivals
  /// frame can enter [_onArrivals] while the first frame's startBoard
  /// round-trip is still in flight — [_lease] alone (assigned only after
  /// the await) can't distinguish "not started" from "start in flight",
  /// and both frames would mint a lease, orphaning the first.
  bool _boardStarted = false;

  /// Bumped on every [StopBoardStarted]/[StopBoardStopped] so a startBoard
  /// round-trip that resolves after the board was stopped or retargeted can
  /// tell its lease belongs to a dead board (see [_onArrivals]).
  int _boardEpoch = 0;

  void _onStarted(StopBoardStarted event, Emitter<StopBoardState> emit) {
    // Only one Live Activity can exist; a board supersedes any in-flight
    // journey/track card the same way starting a new journey would.
    _session.add(const JourneyCancelled());
    unawaited(_sub?.cancel());
    _lease = null;
    _boardStarted = false;
    _boardEpoch++;
    emit(StopBoardState(active: true, stopName: event.stopName));
    _sub = _etaSource(
      event.city,
      event.stopKey,
    ).listen((arrivals) => add(BoardArrivalsReceived(arrivals)));
  }

  Future<void> _onArrivals(
    BoardArrivalsReceived event,
    Emitter<StopBoardState> emit,
  ) async {
    final rows = _rows(event.arrivals);
    final stopName = state.stopName ?? '';
    if (!_boardStarted) {
      _boardStarted = true;
      final epoch = _boardEpoch;
      final lease = await _channel.startBoard(stopName, rows);
      if (epoch == _boardEpoch) {
        _lease = lease;
      } else {
        // Stopped or retargeted while the start round-trip was in flight:
        // this lease will never be stopped by _onStopped, so release it
        // here instead of leaving the activity orphaned.
        unawaited(_channel.stop(lease));
      }
      return;
    }
    // A frame arriving while the start round-trip is still in flight
    // (_lease not yet assigned) is skipped; the next frame updates.
    final lease = _lease;
    if (lease != null) {
      unawaited(_channel.updateBoard(lease, stopName, rows));
    }
  }

  List<StopBoardRow> _rows(List<BusStopArrival> arrivals) {
    final sorted = [...arrivals]
      ..sort((a, b) => a.estimateSeconds.compareTo(b.estimateSeconds));
    return [
      for (final a in sorted.take(_maxBoardRows))
        StopBoardRow(
          routeNumber: a.routeName,
          destination: '往${a.destination}',
          etaLabel: a.displayLabel ?? '—',
        ),
    ];
  }

  void _onStopped(StopBoardStopped _, Emitter<StopBoardState> emit) {
    unawaited(_sub?.cancel());
    _sub = null;
    _boardStarted = false;
    _boardEpoch++;
    final lease = _lease;
    _lease = null;
    if (lease != null) unawaited(_channel.stop(lease));
    emit(const StopBoardState());
  }

  @override
  Future<void> close() {
    unawaited(_sub?.cancel());
    return super.close();
  }
}
