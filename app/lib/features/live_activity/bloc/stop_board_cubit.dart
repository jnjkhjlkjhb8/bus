import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/live_activity/live_activity_channel.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/repositories/bus_repository.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';

/// Routes shown on the stop-board Live Activity, ranked soonest-first.
const _maxBoardRows = 4;

class StopBoardState extends Equatable {
  const StopBoardState({this.active = false, this.stopName});

  final bool active;
  final String? stopName;

  @override
  List<Object?> get props => [active, stopName];
}

/// Drives the stop-board Live Activity (every route serving one stop, ranked
/// by soonest ETA) from [BusRepository.stationEta].
///
/// Shares the single [LiveActivityChannel] with [JourneySessionBloc]'s
/// journey/track card — only one Live Activity can exist at a time, so
/// [start] cancels any live journey session first (mutual exclusion).
class StopBoardCubit extends Cubit<StopBoardState> {
  StopBoardCubit({
    required LiveActivityChannel channel,
    required JourneySessionBloc session,
    Stream<List<BusStopArrival>> Function(String city, String stopKey)?
    etaSource,
  }) : _channel = channel,
       _session = session,
       _etaSource = etaSource ?? BusRepository.instance.stationEta,
       super(const StopBoardState());

  final LiveActivityChannel _channel;
  final JourneySessionBloc _session;
  final Stream<List<BusStopArrival>> Function(String city, String stopKey)
  _etaSource;

  StreamSubscription<List<BusStopArrival>>? _sub;
  bool _boardStarted = false;

  void start(String city, String stopKey, String stopName) {
    // Only one Live Activity can exist; a board supersedes any in-flight
    // journey/track card the same way starting a new journey would.
    _session.add(const JourneyCancelled());
    unawaited(_sub?.cancel());
    _boardStarted = false;
    emit(StopBoardState(active: true, stopName: stopName));
    _sub = _etaSource(city, stopKey).listen((arrivals) {
      final rows = _rows(arrivals);
      if (!_boardStarted) {
        _boardStarted = true;
        unawaited(_channel.startBoard(stopName, rows));
      } else {
        unawaited(_channel.updateBoard(stopName, rows));
      }
    });
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

  void stop() {
    unawaited(_sub?.cancel());
    _sub = null;
    _boardStarted = false;
    unawaited(_channel.stop());
    emit(const StopBoardState());
  }

  @override
  Future<void> close() {
    unawaited(_sub?.cancel());
    return super.close();
  }
}
