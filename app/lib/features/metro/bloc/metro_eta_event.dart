import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_state.dart';

sealed class MetroEtaEvent extends Equatable {
  const MetroEtaEvent();
  @override
  List<Object?> get props => [];
}

final class LoadMetroEta extends MetroEtaEvent {
  const LoadMetroEta(this.system, this.stationId);
  final String system;
  final String stationId;
  @override
  List<Object?> get props => [system, stationId];
}

final class MetroEtaArrived extends MetroEtaEvent {
  const MetroEtaArrived(this.arrivals);

  /// The merged, sorted arrival list emitted by the arrival feed (dedup by
  /// line+destination and sort by estimate now live in the feed).
  final List<MetroArrival> arrivals;
  @override
  List<Object?> get props => [arrivals];
}

/// Emitted when the live seed grace period elapses without a first arrival, so
/// the skeleton resolves to an empty state instead of waiting forever on a
/// push that never comes (no incoming trains, or an env without a feed).
final class MetroEtaSettled extends MetroEtaEvent {
  const MetroEtaSettled();
}
