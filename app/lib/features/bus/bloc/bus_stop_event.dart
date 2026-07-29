import 'package:equatable/equatable.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/data/live/arrival_feed.dart';
import 'package:wheres_the_bus/data/models/bus_models.dart';

sealed class BusStopEvent extends Equatable {
  const BusStopEvent();
  @override
  List<Object?> get props => [];
}

class BusStopStarted extends BusStopEvent {
  const BusStopStarted();
}

class BusStopRetryRequested extends BusStopEvent {
  const BusStopRetryRequested();
}

class BusStopArrivalsUpdated extends BusStopEvent {
  const BusStopArrivalsUpdated(
    this.arrivals, {
    this.kind = ArrivalFeedEmissionKind.source,
  });
  final List<BusStopArrival> arrivals;

  /// Which kind of feed emission produced this list — `source` for a fresh
  /// network frame, `decay` for a local countdown re-emission between frames.
  /// Only `source` frames may refresh network-freshness timestamps or clear
  /// an offline error (F29, F30).
  final ArrivalFeedEmissionKind kind;
  @override
  List<Object?> get props => [arrivals, kind];
}

/// Selects a member stop to filter the arrivals list and centre the map on it;
/// a null [stationUid] clears the filter back to 全部.
class BusStopStationSelected extends BusStopEvent {
  const BusStopStationSelected(this.stationUid);
  final String? stationUid;
  @override
  List<Object?> get props => [stationUid];
}

class BusStopFailed extends BusStopEvent {
  const BusStopFailed(this.error);

  final AppError error;

  @override
  List<Object?> get props => [error];
}
