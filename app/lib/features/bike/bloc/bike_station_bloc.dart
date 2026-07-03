import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/data/generated/bike.pb.dart';
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
  StreamSubscription<Resp_Bike_eta>? _sub;

  Future<void> _onStarted(
    BikeStationStarted _,
    Emitter<BikeStationState> emit,
  ) async {
    try {
      final s = await BikeRepository.instance.stationStatic(stationUid);
      emit(state.copyWith(name: s.name, capacity: s.capacity, loading: false));
      _sub = BikeRepository.instance.stationEta(stationUid).listen((resp) {
        final e = Bike_eta.fromBuffer(Uint8List.fromList(resp.data));
        add(
          BikeStationEtaUpdated(
            available: e.generalBikes + e.electricBikes,
            returnDocks: e.availableReturnBikes,
            generalBikes: e.generalBikes,
            electricBikes: e.electricBikes,
          ),
        );
      });
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
