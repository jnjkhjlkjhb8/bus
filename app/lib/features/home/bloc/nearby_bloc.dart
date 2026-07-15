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
    on<NearbyRetried>(_onRetried);
  }

  final NearRepository _repository;

  // Event handlers run concurrently (no transformer), so an older query can
  // resolve after a newer one; only the current generation is allowed to emit.
  var _generation = 0;

  /// The most recently issued query, kept even on failure so [NearbyRetried]
  /// replays the same dragged viewport instead of falling back to GPS.
  NearbyRequested? _lastAttempted;

  Future<void> _onRetried(
    NearbyRetried event,
    Emitter<NearbyState> emit,
  ) async {
    final last = _lastAttempted;
    if (last == null) return;
    await _run(last, emit);
  }

  Future<void> _onRequested(
    NearbyRequested event,
    Emitter<NearbyState> emit,
  ) async {
    _lastAttempted = event;
    await _run(event, emit);
  }

  Future<void> _run(NearbyRequested event, Emitter<NearbyState> emit) async {
    final gen = ++_generation;
    emit(state.copyWith(loading: true, clearError: true));
    try {
      var lat = event.lat ?? 0;
      var lon = event.lon ?? 0;
      if (event.lat == null || event.lon == null) {
        final pos = await LocationService.instance.currentPosition();
        lat = pos.latitude;
        lon = pos.longitude;
      }
      final stations = await _repository.nearOnce(lat, lon, event.radius).first
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      if (gen != _generation) return;
      emit(
        state.copyWith(stations: stations, loading: false, clearError: true),
      );
    } on Object catch (e) {
      if (gen != _generation) return;
      emit(state.copyWith(loading: false, error: AppError.from(e)));
    }
  }
}
