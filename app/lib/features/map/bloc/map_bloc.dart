import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/data/repositories/near_repository.dart';
import 'package:wheres_the_car/features/map/bloc/map_event.dart';
import 'package:wheres_the_car/features/map/bloc/map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  MapBloc({NearRepository? repository})
    : _repository = repository ?? NearRepository.instance,
      super(const MapState()) {
    on<MapStarted>(_onStarted);
    on<MapLocateRequested>(_onLocate);
    on<MapFilterChanged>(_onFilterChanged);
    on<MapNearUpdated>(_onNearUpdated);
    on<MapLocateFailed>(_onFailed);
    add(const MapStarted());
  }

  final NearRepository _repository;

  Future<void> _onStarted(MapStarted _, Emitter<MapState> emit) =>
      _locate(emit);
  Future<void> _onLocate(MapLocateRequested _, Emitter<MapState> emit) =>
      _locate(emit);

  Future<void> _locate(Emitter<MapState> emit) async {
    emit(state.copyWith(locating: true, clearError: true));
    try {
      final pos = await LocationService.instance.currentPosition();
      final latLng = LatLng(pos.latitude, pos.longitude);
      final stations = await _repository
          .nearOnce(pos.latitude, pos.longitude, 800)
          .first;
      emit(
        state.copyWith(position: latLng, stations: stations, locating: false),
      );
    } on Object catch (e) {
      emit(state.copyWith(locating: false, error: _errMsg(e)));
    }
  }

  void _onFilterChanged(MapFilterChanged event, Emitter<MapState> emit) {
    emit(state.copyWith(filter: event.filter));
  }

  void _onNearUpdated(MapNearUpdated event, Emitter<MapState> emit) {
    emit(state.copyWith(position: event.position, stations: event.stations));
  }

  void _onFailed(MapLocateFailed event, Emitter<MapState> emit) {
    emit(state.copyWith(locating: false, error: event.error));
  }

  String _errMsg(Object e) {
    final s = e.toString();
    if (s.contains('denied') || s.contains('permission')) return '請開啟定位權限';
    if (s.contains('disabled') || s.contains('service')) return '請開啟位置服務';
    return '無法取得位置';
  }
}
