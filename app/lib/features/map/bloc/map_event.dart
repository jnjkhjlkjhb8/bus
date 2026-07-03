import 'package:equatable/equatable.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_car/data/generated/near.pb.dart';

sealed class MapEvent extends Equatable {
  const MapEvent();
  @override
  List<Object?> get props => [];
}

class MapStarted extends MapEvent {
  const MapStarted();
}

class MapLocateRequested extends MapEvent {
  const MapLocateRequested();
}

class MapFilterChanged extends MapEvent {
  const MapFilterChanged(this.filter);
  final MapFilter filter;
  @override
  List<Object?> get props => [filter];
}

class MapNearUpdated extends MapEvent {
  const MapNearUpdated(this.position, this.nearResp);
  final LatLng position;
  final resp_near nearResp;
  @override
  List<Object?> get props => [position, nearResp];
}

class MapLocateFailed extends MapEvent {
  const MapLocateFailed(this.error);
  final String error;
  @override
  List<Object?> get props => [error];
}

enum MapFilter { all, bus, bike, metro, rail }
