import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlannedPlace {
  const PlannedPlace({
    required this.name,
    required this.latLng,
    this.isCurrentLocation = false,
  });

  final String name;
  final LatLng latLng;
  final bool isCurrentLocation;

  PlannedPlace copyWith({
    String? name,
    LatLng? latLng,
    bool? isCurrentLocation,
  }) {
    return PlannedPlace(
      name: name ?? this.name,
      latLng: latLng ?? this.latLng,
      isCurrentLocation: isCurrentLocation ?? this.isCurrentLocation,
    );
  }
}
