import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';

sealed class TraStationEvent extends Equatable {
  const TraStationEvent();
  @override
  List<Object?> get props => [];
}

/// Start (or restart) the live board subscription for [stationId].
final class LoadTraStation extends TraStationEvent {
  const LoadTraStation(this.stationId);
  final String stationId;
  @override
  List<Object?> get props => [stationId];
}

final class TraStationBoardUpdated extends TraStationEvent {
  const TraStationBoardUpdated(this.items);
  final List<TraLiveBoardItem> items;
  @override
  List<Object?> get props => [items];
}

final class TraStationFailed extends TraStationEvent {
  const TraStationFailed(this.error);
  final Object error;
  @override
  List<Object?> get props => [error];
}
