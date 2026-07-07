import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';

enum RailTrainStatus { loading, loaded, empty, error }

/// One stop on a train's timetable, normalized across TRA/THSR.
class RailTrainStop extends Equatable {
  const RailTrainStop({
    required this.name,
    required this.arrive,
    required this.depart,
  });

  final String name;
  final String arrive;
  final String depart;

  @override
  List<Object?> get props => [name, arrive, depart];
}

class RailTrainState extends Equatable {
  const RailTrainState({
    this.status = RailTrainStatus.loading,
    this.stops = const [],
    this.fullFare,
    this.error,
  });

  final RailTrainStatus status;
  final List<RailTrainStop> stops;

  /// Adult (全票) fare in NT$, or null when the fare query has no data.
  final int? fullFare;
  final AppError? error;

  @override
  List<Object?> get props => [status, stops, fullFare, error];
}
