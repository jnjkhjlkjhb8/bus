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
