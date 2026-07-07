import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/grpc/resilient_stream.dart';
import 'package:wheres_the_car/data/repositories/bus_stop_eta_repository.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_event.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_state.dart';

class BusStopBloc extends Bloc<BusStopEvent, BusStopState> {
  BusStopBloc({
    required this.stopId,
    this.city,
    BusStopEtaRepository? repository,
  }) : _repository = repository ?? BusStopEtaRepository.instance,
       super(const BusStopState()) {
    on<BusStopStarted>(_onStarted);
    on<BusStopRetryRequested>(_onStarted);
    on<BusStopArrivalsUpdated>(_onUpdated);
    on<BusStopDecayTicked>(_onDecayTicked);
    on<BusStopStationSelected>(_onStationSelected);
    on<BusStopFailed>(_onFailed);
    add(const BusStopStarted());
    _decayTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => add(const BusStopDecayTicked()),
    );
  }

  final String? stopId;
  final String? city;
  final BusStopEtaRepository _repository;
  ResilientSubscription<List<BusStopArrival>>? _sub;
  Timer? _decayTimer;

  Future<void> _onStarted(BusStopEvent _, Emitter<BusStopState> emit) async {
    final id = stopId ?? '';
    if (id.isEmpty) {
      emit(state.copyWith(status: BusStopStatus.empty, clearError: true));
      return;
    }
    emit(state.copyWith(status: BusStopStatus.loading, clearError: true));
    await _sub?.cancel();
    try {
      final members = await _repository.members(id);
      if (members.isNotEmpty) {
        emit(state.copyWith(status: BusStopStatus.loaded, members: members));
      }
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
    }
    _sub = ResilientSubscription<List<BusStopArrival>>(
      source: () => _repository.watchStop(id, city: city),
      onData: (arrivals) => add(BusStopArrivalsUpdated(arrivals)),
      onFailure: (e) => add(BusStopFailed(e)),
    );
  }

  void _onStationSelected(
    BusStopStationSelected event,
    Emitter<BusStopState> emit,
  ) {
    emit(
      event.stationUid == null
          ? state.copyWith(clearSelection: true)
          : state.copyWith(selectedStationUid: event.stationUid),
    );
  }

  void _onUpdated(BusStopArrivalsUpdated event, Emitter<BusStopState> emit) {
    if (event.arrivals.isEmpty && state.arrivals.isNotEmpty) return;
    emit(
      state.copyWith(
        status: event.arrivals.isEmpty && state.members.isEmpty
            ? BusStopStatus.empty
            : BusStopStatus.loaded,
        arrivals: event.arrivals,
        updatedAt: DateTime.now(),
        clearError: true,
      ),
    );
  }

  void _onDecayTicked(BusStopDecayTicked _, Emitter<BusStopState> emit) {
    if (state.arrivals.isEmpty) return;
    final now = DateTime.now();
    emit(
      state.copyWith(
        arrivals: [for (final a in state.arrivals) a.decayed(now)],
      ),
    );
  }

  void _onFailed(BusStopFailed event, Emitter<BusStopState> emit) {
    emit(state.copyWith(status: BusStopStatus.error, error: event.error));
  }

  @override
  Future<void> close() async {
    _decayTimer?.cancel();
    await _sub?.cancel();
    return super.close();
  }
}
