import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/grpc/live_data.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';
import 'package:wheres_the_car/data/repositories/tra_repository.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_event.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_state.dart';

String _formatDate(DateTime now) {
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '${now.year}-$m-$d';
}

/// Drives a single TRA station's live departure board for the home
/// second-layer sheet. Isolated from the bigger RailBloc state machine:
/// this only ever watches one station's live board stream.
class TraStationBloc extends Bloc<TraStationEvent, TraStationState> {
  TraStationBloc({String Function() today = _defaultToday})
    : _today = today,
      super(const TraStationState()) {
    on<LoadTraStation>(_onLoad);
    on<TraStationBoardUpdated>(_onBoardUpdated);
    on<TraStationFailed>(_onFailed);
  }

  final String Function() _today;
  LiveData<List<TraLiveBoardItem>>? _sub;

  static String _defaultToday() => _formatDate(DateTime.now());

  Future<void> _onLoad(
    LoadTraStation e,
    Emitter<TraStationState> emit,
  ) async {
    await _sub?.cancel();
    emit(const TraStationState(loading: true));
    _sub = LiveData<List<TraLiveBoardItem>>.watch(
      source: () => TraRepository.instance.liveBoard(e.stationId, _today()),
      onData: (items) => add(TraStationBoardUpdated(items)),
      onFailure: (error) => add(TraStationFailed(error)),
    );
  }

  void _onBoardUpdated(
    TraStationBoardUpdated e,
    Emitter<TraStationState> emit,
  ) {
    final sorted = [...e.items]
      ..sort((a, b) => a.departureTime.compareTo(b.departureTime));
    emit(state.copyWith(items: sorted, loading: false));
  }

  void _onFailed(TraStationFailed e, Emitter<TraStationState> emit) {
    emit(state.copyWith(loading: false, error: AppError.from(e.error)));
  }

  @override
  Future<void> close() {
    unawaited(_sub?.cancel());
    return super.close();
  }
}
