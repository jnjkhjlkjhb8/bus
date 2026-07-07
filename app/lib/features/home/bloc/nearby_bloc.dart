import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/data/repositories/near_repository.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_event.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_state.dart';

class NearbyBloc extends Bloc<NearbyEvent, NearbyState> {
  NearbyBloc({NearRepository? repository})
    : _repository = repository ?? NearRepository.instance,
      super(const NearbyState()) {
    on<NearbyRequested>(_onRequested);
  }

  final NearRepository _repository;

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
      final stations =
          await _repository.nearOnce(lat, lon, event.radius).first
            ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      emit(
        state.copyWith(stations: stations, loading: false, clearError: true),
      );
    } on Object catch (e) {
      emit(state.copyWith(loading: false, error: AppError.from(e)));
    }
  }
}
