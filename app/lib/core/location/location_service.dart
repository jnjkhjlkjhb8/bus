import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
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

  /// Last OS-cached fix, if any — returns instantly, no GPS wait. Null when
  /// the OS has no cached position or permission is missing.
  Future<Position?> lastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } on Object {
      return null;
    }
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
        // 5 m keeps the follow camera moving at walking pace; 25 m delivered a
        // fix only every ~20 s of walking, which read as "not following".
        distanceFilter: 5,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = AndroidSettings(distanceFilter: 5);
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  /// Device compass heading (degrees clockwise from magnetic north), for
  /// rotating the navigation camera as the phone turns. Emits only non-null
  /// headings; on a device with no magnetometer (or the plugin returning no
  /// stream) this is an empty stream and callers keep the GPS-course fallback.
  /// The plugin type stays inside core/ — callers see a plain `Stream<double>`.
  Stream<double> compassStream() {
    final events = FlutterCompass.events;
    if (events == null) return const Stream.empty();
    return events
        .map((event) => event.heading)
        .where((heading) => heading != null)
        .cast<double>();
  }
}
