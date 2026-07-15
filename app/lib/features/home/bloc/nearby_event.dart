import 'package:equatable/equatable.dart';

sealed class NearbyEvent extends Equatable {
  const NearbyEvent();

  @override
  List<Object?> get props => [];
}

final class NearbyRequested extends NearbyEvent {
  const NearbyRequested({required this.radius, this.lat, this.lon});

  final int radius;
  final double? lat;
  final double? lon;

  @override
  List<Object?> get props => [radius, lat, lon];
}

/// Re-sends the most recent [NearbyRequested] query verbatim — including a
/// failed dragged-viewport query — rather than falling back to device GPS.
final class NearbyRetried extends NearbyEvent {
  const NearbyRetried();
}
