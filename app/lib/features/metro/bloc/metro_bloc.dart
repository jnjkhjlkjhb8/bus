import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/data/repositories/mrt_repository.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_event.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_state.dart';

class MetroBloc extends Bloc<MetroEvent, MetroState> {
  MetroBloc({MrtRepository? repository})
    : _repository = repository ?? MrtRepository.instance,
      super(const MetroState()) {
    on<MetroStationTapped>(_onStationTapped);
    on<MetroStationDismissed>(_onStationDismissed);
    on<MetroJourneyMatrixLoaded>(_onMatrixLoaded);
  }

  final MrtRepository _repository;

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
      final matrix = await _repository.journeyMatrix(event.stationId);
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
}
