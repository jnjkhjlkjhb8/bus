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
    on<BusStopFailed>(_onFailed);
    add(const BusStopStarted());
  }

  final String stopId;
  final String? city;
  final BusStopEtaRepository _repository;
  ResilientSubscription<List<BusStopArrival>>? _sub;

  Future<void> _onStarted(BusStopEvent _, Emitter<BusStopState> emit) async {
    emit(state.copyWith(status: BusStopStatus.loading, clearError: true));
    await _sub?.cancel();
    try {
      final members = await _repository.members(stopId);
      if (members.isNotEmpty) {
        emit(state.copyWith(status: BusStopStatus.loaded, members: members));
      }
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
    }
    _sub = ResilientSubscription<List<BusStopArrival>>(
      source: () => _repository.watchStop(stopId, city: city),
      onData: (arrivals) => add(BusStopArrivalsUpdated(arrivals)),
      onFailure: (e) => add(BusStopFailed(e)),
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

  void _onFailed(BusStopFailed event, Emitter<BusStopState> emit) {
    emit(state.copyWith(status: BusStopStatus.error, error: event.error));
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
