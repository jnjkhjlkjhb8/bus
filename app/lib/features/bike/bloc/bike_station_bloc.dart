import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/grpc/live_data.dart';
import 'package:wheres_the_car/data/models/bike_models.dart';
import 'package:wheres_the_car/data/repositories/bike_repository.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_event.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_state.dart';

class BikeStationBloc extends Bloc<BikeStationEvent, BikeStationState> {
  BikeStationBloc({required this.stationUid})
    : super(const BikeStationState()) {
    on<BikeStationStarted>(_onStarted);
    on<BikeStationEtaUpdated>(_onEta);
    add(const BikeStationStarted());
  }

  final String stationUid;

  // Migrated from a bare StreamSubscription to LiveData in the Track-C
  // refactor: the availability stream now retries with backoff instead of
  // dying silently on a dropped connection. This is a deliberate behavior
  // improvement over the previous unresilient subscription.
  LiveData<BikeAvailability>? _sub;

  Future<void> _onStarted(
    BikeStationStarted _,
    Emitter<BikeStationState> emit,
  ) async {
    try {
      final info = await BikeRepository.instance.stationStatic(stationUid);
      emit(state.copyWith(
        name: info.name,
        capacity: info.capacity,
        loading: false,
      ));
      _sub = LiveData<BikeAvailability>.watch(
        source: () => BikeRepository.instance.stationEta(stationUid),
        onData: (a) => add(
          BikeStationEtaUpdated(
            available: a.available,
            returnDocks: a.returnDocks,
            generalBikes: a.generalBikes,
            electricBikes: a.electricBikes,
          ),
        ),
      );
    } on Object catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  void _onEta(BikeStationEtaUpdated e, Emitter<BikeStationState> emit) {
    emit(
      state.copyWith(
        available: e.available,
        returnDocks: e.returnDocks,
        generalBikes: e.generalBikes,
        electricBikes: e.electricBikes,
      ),
    );
  }

  @override
  Future<void> close() {
    unawaited(_sub?.cancel());
    return super.close();
  }
}
