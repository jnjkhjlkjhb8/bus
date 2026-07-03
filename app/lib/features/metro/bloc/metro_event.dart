import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/data/models/journey_info.dart';

sealed class MetroEvent extends Equatable {
  const MetroEvent();
  @override
  List<Object?> get props => [];
}

class MetroDisplayModeChanged extends MetroEvent {
  const MetroDisplayModeChanged(this.mode);
  final MetroDisplayMode mode;
  @override
  List<Object?> get props => [mode];
}

class MetroStationTapped extends MetroEvent {
  const MetroStationTapped({required this.stationId});
  final String stationId;
  @override
  List<Object?> get props => [stationId];
}

class MetroStationDismissed extends MetroEvent {
  const MetroStationDismissed();
}

class MetroJourneyMatrixLoaded extends MetroEvent {
  const MetroJourneyMatrixLoaded({required this.matrix});
  final Map<String, JourneyInfo> matrix;
  @override
  List<Object?> get props => [matrix];
}

enum MetroDisplayMode { travelTime, fare }
