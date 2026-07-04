import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';

enum RailSystem { tra, thsr }

sealed class RailEvent extends Equatable {
  const RailEvent();
  @override
  List<Object?> get props => [];
}

final class RailSystemChanged extends RailEvent {
  const RailSystemChanged(this.system);
  final RailSystem system;
  @override
  List<Object?> get props => [system];
}

final class RailStationSelected extends RailEvent {
  const RailStationSelected({
    required this.stationId,
    required this.stationName,
  });
  final String stationId;
  final String stationName;
  @override
  List<Object?> get props => [stationId, stationName];
}

final class RailLiveBoardStarted extends RailEvent {
  const RailLiveBoardStarted();
}

final class RailLiveBoardStopped extends RailEvent {
  const RailLiveBoardStopped();
}

final class RailQueryChanged extends RailEvent {
  const RailQueryChanged({
    this.originId,
    this.originName,
    this.destId,
    this.destName,
    this.date,
    this.time,
    this.departureMode,
  });
  final String? originId;
  final String? originName;
  final String? destId;
  final String? destName;
  final DateTime? date;
  final TimeOfDay? time;
  final bool? departureMode;
  @override
  List<Object?> get props => [
    originId,
    originName,
    destId,
    destName,
    date,
    time,
    departureMode,
  ];
}

final class RailQuerySubmitted extends RailEvent {
  const RailQuerySubmitted();
}

final class RailTimetableRequested extends RailEvent {
  const RailTimetableRequested({
    required this.originId,
    required this.destId,
    required this.date,
  });
  final String originId;
  final String destId;
  final String date;
  @override
  List<Object?> get props => [originId, destId, date];
}

final class RailTrainStopsRequested extends RailEvent {
  const RailTrainStopsRequested({required this.trainNo, required this.date});
  final String trainNo;
  final String date;
  @override
  List<Object?> get props => [trainNo, date];
}

final class RailDelaysUpdated extends RailEvent {
  const RailDelaysUpdated(this.delays);
  final Map<String, int> delays;
  @override
  List<Object?> get props => [delays];
}

/// Internal: a fresh live-board snapshot arrived on the resilient stream. The
/// handler reads the current state rather than a captured value.
final class RailLiveBoardItemsUpdated extends RailEvent {
  const RailLiveBoardItemsUpdated(this.items);
  final List<TraLiveBoardItem> items;
  @override
  List<Object?> get props => [items];
}

/// Internal: the live-board stream failed terminally after retries.
final class RailLiveBoardFailed extends RailEvent {
  const RailLiveBoardFailed(this.error);
  final AppError error;
  @override
  List<Object?> get props => [error];
}
