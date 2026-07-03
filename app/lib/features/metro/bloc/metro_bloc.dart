import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/data/models/journey_info.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_event.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_state.dart';

class MetroBloc extends Bloc<MetroEvent, MetroState> {
  MetroBloc() : super(const MetroState()) {
    on<MetroDisplayModeChanged>(_onModeChanged);
    on<MetroStationTapped>(_onStationTapped);
    on<MetroStationDismissed>(_onStationDismissed);
    on<MetroJourneyMatrixLoaded>(_onMatrixLoaded);
  }

  void _onModeChanged(MetroDisplayModeChanged event, Emitter<MetroState> emit) {
    emit(state.copyWith(displayMode: event.mode));
  }

  Future<void> _onStationTapped(
    MetroStationTapped event,
    Emitter<MetroState> emit,
  ) async {
    emit(
      state.copyWith(
        activeStationId: event.stationId,
        clearMatrix: true,
        clearError: true,
      ),
    );
    try {
      final matrix = await _loadJourneyMatrix(event.stationId);
      emit(
        state.copyWith(
          activeStationId: event.stationId,
          journeyMatrix: matrix,
          clearError: true,
        ),
      );
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
      emit(state.copyWith(error: AppError.from(e)));
    }
  }

  void _onStationDismissed(MetroStationDismissed _, Emitter<MetroState> emit) {
    emit(
      state.copyWith(clearStation: true, clearMatrix: true, clearError: true),
    );
  }

  void _onMatrixLoaded(
    MetroJourneyMatrixLoaded event,
    Emitter<MetroState> emit,
  ) {
    emit(state.copyWith(journeyMatrix: event.matrix));
  }

  Future<Map<String, JourneyInfo>> _loadJourneyMatrix(String stationId) async {
    final db = PowerSyncService.instance.db;
    final rows = await db.getAll(
      'SELECT to_station_id, travel_time_min, fare_nt '
      'FROM mrt_journey_matrix WHERE from_station_id = ?',
      [stationId],
    );
    return {
      for (final r in rows)
        r['to_station_id'] as String: JourneyInfo.fromRow(r),
    };
  }
}
