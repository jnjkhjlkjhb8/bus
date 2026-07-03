import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/data/generated/near.pb.dart';
import 'package:wheres_the_car/data/models/near_models.dart';
import 'package:wheres_the_car/data/repositories/near_repository.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_event.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_state.dart';

class NearbyBloc extends Bloc<NearbyEvent, NearbyState> {
  NearbyBloc() : super(const NearbyState()) {
    on<NearbyRequested>(_onRequested);
  }

  Future<void> _onRequested(
    NearbyRequested event,
    Emitter<NearbyState> emit,
  ) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      var lat = event.lat ?? 0;
      var lon = event.lon ?? 0;
      if (event.lat == null || event.lon == null) {
        final pos = await LocationService.instance.currentPosition();
        lat = pos.latitude;
        lon = pos.longitude;
      }
      final resp = await NearRepository.instance
          .nearOnce(lat, lon, event.radius)
          .first;
      final stations = _flatten(resp)
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      emit(
        state.copyWith(stations: stations, loading: false, clearError: true),
      );
    } on Object catch (e) {
      emit(state.copyWith(loading: false, error: AppError.from(e)));
    }
  }

  List<NearStationViewModel> _flatten(resp_near resp) {
    final out = <NearStationViewModel>[];
    for (final group in resp.nearBusStations.values) {
      for (final s in group.nearStations) {
        out.add(_vm(s, NearStationType.bus));
      }
    }
    for (final s in resp.nearMrtStations) {
      out.add(_vm(s, NearStationType.mrt));
    }
    for (final s in resp.nearBikeStations) {
      out.add(_vm(s, NearStationType.bike));
    }
    return out;
  }

  NearStationViewModel _vm(NearStation s, NearStationType type) =>
      NearStationViewModel(
        type: type,
        stationId: s.stationID,
        stationName: s.stationName,
        lat: s.positionLat,
        lon: s.positionLon,
        walkingMinutes: s.walk,
        distanceMeters: s.distance,
      );
}
