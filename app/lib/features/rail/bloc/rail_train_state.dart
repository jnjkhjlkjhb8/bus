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
    this.reminders = const {},
  });

  final RailTrainStatus status;
  final List<RailTrainStop> stops;

  /// Adult (全票) fare in NT$, or null when the fare query has no data.
  final int? fullFare;
  final AppError? error;

  /// Active arrival reminders, keyed by stop name → reminder id. A value of
  /// `'pending'` marks an in-flight create/cancel so the bell can show progress.
  final Map<String, String> reminders;

  RailTrainState copyWith({
    RailTrainStatus? status,
    List<RailTrainStop>? stops,
    int? fullFare,
    AppError? error,
    Map<String, String>? reminders,
  }) => RailTrainState(
    status: status ?? this.status,
    stops: stops ?? this.stops,
    fullFare: fullFare ?? this.fullFare,
    error: error ?? this.error,
    reminders: reminders ?? this.reminders,
  );

  @override
  List<Object?> get props => [status, stops, fullFare, error, reminders];
}
