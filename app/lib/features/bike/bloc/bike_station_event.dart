import 'package:equatable/equatable.dart';

sealed class BikeStationEvent extends Equatable {
  const BikeStationEvent();
  @override
  List<Object?> get props => [];
}

final class BikeStationStarted extends BikeStationEvent {
  const BikeStationStarted();
}

final class BikeStationEtaUpdated extends BikeStationEvent {
  const BikeStationEtaUpdated({
    required this.available,
    required this.returnDocks,
    required this.generalBikes,
    required this.electricBikes,
  });
  final int available;
  final int returnDocks;
  final int generalBikes;
  final int electricBikes;
  @override
  List<Object?> get props => [
    available,
    returnDocks,
    generalBikes,
    electricBikes,
  ];
}

/// Emitted when the live availability stream's ResilientSubscription gives up
/// reconnecting. The last-known counts stay in state (the passthrough never
/// clears them), so this is what lets the UI tell a confirmed zero from a
/// silently stale one (F27).
final class BikeStationEtaFailed extends BikeStationEvent {
  const BikeStationEtaFailed(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

/// Emitted when the live availability stream recovers after a prior failure.
final class BikeStationEtaRecovered extends BikeStationEvent {
  const BikeStationEtaRecovered();
}
