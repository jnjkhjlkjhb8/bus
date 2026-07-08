import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/data/live/arrival_feed.dart';
import 'package:wheres_the_car/data/models/bike_models.dart';
import 'package:wheres_the_car/data/repositories/bike_repository.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_event.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_state.dart';

class BikeStationBloc extends Bloc<BikeStationEvent, BikeStationState> {
  BikeStationBloc({required this.stationUid, BikeRepository? repository})
    : _repository = repository ?? BikeRepository.instance,
      super(const BikeStationState()) {
    on<BikeStationStarted>(_onStarted);
    on<BikeStationEtaUpdated>(_onEta);
    add(const BikeStationStarted());
  }

  final String stationUid;
  final BikeRepository _repository;

  // Availability is a lone live value, not an arrival list, so it rides the
  // arrival feed's passthrough seam: resilient reconnect/backoff without any
  // merge/decay/sort. It gains no arrival semantics from sharing the seam.
  StreamSubscription<BikeAvailability>? _sub;

  Future<void> _onStarted(
    BikeStationStarted _,
    Emitter<BikeStationState> emit,
  ) async {
    try {
      final info = await _repository.stationStatic(stationUid);
      emit(state.copyWith(
        name: info.name,
        capacity: info.capacity,
        loading: false,
      ));
      _sub = ArrivalFeed.passthrough(
        source: () => _repository.stationEta(stationUid),
      ).listen(
        (a) => add(
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
