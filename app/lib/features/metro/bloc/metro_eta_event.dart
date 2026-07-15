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

/// Emitted when the arrival feed's underlying ResilientSubscription gives up
/// reconnecting. The bloc keeps showing the last-known [MetroEtaState.arrivals]
/// (the feed never clears them on failure) but surfaces the health so the UI
/// doesn't present silently stale data as current (F28).
final class MetroEtaFailed extends MetroEtaEvent {
  const MetroEtaFailed(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

/// Emitted when the feed recovers after a prior failure notification.
final class MetroEtaRecovered extends MetroEtaEvent {
  const MetroEtaRecovered();
}
