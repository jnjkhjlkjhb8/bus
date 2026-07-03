import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/journey_info.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_event.dart';

class MetroState extends Equatable {
  const MetroState({
    this.displayMode = MetroDisplayMode.travelTime,
    this.activeStationId,
    this.journeyMatrix,
    this.error,
  });

  final MetroDisplayMode displayMode;
  final String? activeStationId;
  final Map<String, JourneyInfo>? journeyMatrix;
  final AppError? error;

  MetroState copyWith({
    MetroDisplayMode? displayMode,
    String? activeStationId,
    bool clearStation = false,
    Map<String, JourneyInfo>? journeyMatrix,
    bool clearMatrix = false,
    AppError? error,
    bool clearError = false,
  }) => MetroState(
    displayMode: displayMode ?? this.displayMode,
    activeStationId: clearStation
        ? null
        : activeStationId ?? this.activeStationId,
    journeyMatrix: clearMatrix ? null : journeyMatrix ?? this.journeyMatrix,
    error: clearError ? null : error ?? this.error,
  );

  @override
  List<Object?> get props => [
    displayMode,
    activeStationId,
    journeyMatrix,
    error,
  ];
}
