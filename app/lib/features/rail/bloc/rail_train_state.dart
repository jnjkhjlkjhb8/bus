import 'package:equatable/equatable.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/data/models/rail_fare_quote.dart';

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
    this.userFare,
    this.error,
    this.liveDelayMinutes,
  });

  final RailTrainStatus status;
  final List<RailTrainStop> stops;

  /// Adult (全票) fare in NT$ for the train's own full run (its first stop to
  /// its last), or null when the fare query has no data.
  final RailFareQuote? fullFare;

  /// Adult (全票) fare in NT$ for the segment the caller actually searched
  /// (`RailTrainBloc.userOrigin`/`userDest`), or null when no such segment was
  /// given, or its fare query had no data. This is the number an O/D result
  /// list already quoted the user, so the screen must lead with this one, not
  /// [fullFare] — quoting the full-run fare instead used to show a different
  /// price than the list for what read as the same trip.
  final RailFareQuote? userFare;
  final AppError? error;

  /// Live TRA 誤點 minutes for this train, or null before the first delay
  /// frame lands (THSR stays null — no delay feed). The screen falls back to
  /// the snapshot it navigated in with while this is null.
  final int? liveDelayMinutes;

  RailTrainState copyWith({
    RailTrainStatus? status,
    List<RailTrainStop>? stops,
    RailFareQuote? fullFare,
    RailFareQuote? userFare,
    AppError? error,
    int? liveDelayMinutes,
  }) => RailTrainState(
    status: status ?? this.status,
    stops: stops ?? this.stops,
    fullFare: fullFare ?? this.fullFare,
    userFare: userFare ?? this.userFare,
    error: error ?? this.error,
    liveDelayMinutes: liveDelayMinutes ?? this.liveDelayMinutes,
  );

  @override
  List<Object?> get props => [
    status,
    stops,
    fullFare,
    userFare,
    error,
    liveDelayMinutes,
  ];
}
