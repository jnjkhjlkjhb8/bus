import 'package:equatable/equatable.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_car/data/models/near_models.dart';
import 'package:wheres_the_car/features/map/bloc/map_event.dart';

class MapState extends Equatable {
  const MapState({
    this.position,
    this.stations = const [],
    this.filter = MapFilter.all,
    this.locating = false,
    this.error,
  });

  final LatLng? position;
  final List<NearStationViewModel> stations;
  final MapFilter filter;
  final bool locating;
  final String? error;

  MapState copyWith({
    LatLng? position,
    List<NearStationViewModel>? stations,
    MapFilter? filter,
    bool? locating,
    String? error,
    bool clearError = false,
  }) => MapState(
    position: position ?? this.position,
    stations: stations ?? this.stations,
    filter: filter ?? this.filter,
    locating: locating ?? this.locating,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [position, stations, filter, locating, error];
}
