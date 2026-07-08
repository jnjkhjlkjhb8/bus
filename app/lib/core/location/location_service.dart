import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Wrapper around geolocator — handles permission and fallback.
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  /// Returns current position, requesting permission if needed.
  /// Throws [LocationServiceDisabledException] or [PermissionDeniedException]
  /// if unavailable — callers fall back to manual station selection.
  Future<Position> currentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const PermissionDeniedException('Location permission denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const PermissionDeniedException(
        'Location permission permanently denied',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }

  /// Continuous position stream (low power).
  Stream<Position> positionStream() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 50,
    ),
  );

  /// Higher-accuracy stream for active navigation. iOS continues in the
  /// background (UIBackgroundModes location) with the system indicator shown;
  /// stops when the subscription is cancelled at journey end.
  Stream<Position> navigationStream() {
    late final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // AppleSettings.accuracy defaults to best and allowBackgroundLocation
      // updates default to true; both are omitted here to satisfy the analyzer
      // while keeping full-accuracy background tracking.
      settings = AppleSettings(
        activityType: ActivityType.otherNavigation,
        distanceFilter: 25,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = AndroidSettings(distanceFilter: 25);
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
