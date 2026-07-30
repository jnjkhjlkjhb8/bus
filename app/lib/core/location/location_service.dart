import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

/// Why the app currently has no fix. Published by [LocationService.denial] so
/// the resident notice rail can say so without every screen re-deriving it
/// from a caught exception.
enum LocationDenial { permission, serviceDisabled }

/// Wrapper around geolocator — handles permission and fallback.
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  /// Current reason location is unavailable, or null once a fix succeeds.
  /// Written by [currentPosition] on every attempt, so it always reflects the
  /// last real answer from the OS rather than a stale first-launch guess.
  static final denial = ValueNotifier<LocationDenial?>(null);

  /// Returns current position, requesting permission if needed.
  /// Throws [LocationServiceDisabledException] or [PermissionDeniedException]
  /// if unavailable — callers fall back to manual station selection, and
  /// [denial] carries the reason for the notice rail.
  Future<Position> currentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      denial.value = LocationDenial.serviceDisabled;
      throw const LocationServiceDisabledException();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        denial.value = LocationDenial.permission;
        throw const PermissionDeniedException('Location permission denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      denial.value = LocationDenial.permission;
      throw const PermissionDeniedException(
        'Location permission permanently denied',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 10),
      ),
    );
    denial.value = null;
    return position;
  }

  Future<Position?>? _prefetchedLastKnown;

  /// Starts the cached-fix lookup early — call from `main()`.
  ///
  /// Despite the name, `getLastKnownPosition` is not free: on Android the first
  /// call costs ~370 ms of plugin/platform setup. Home needs that fix straight
  /// after the bootstrap splash, where it is the only thing between the map and
  /// the first nearby query, so it runs during the splash instead.
  void prefetchLastKnown() {
    _prefetchedLastKnown ??= _readLastKnown();
  }

  /// Last OS-cached fix, if any — no GPS wait. Null when the OS has no cached
  /// position or permission is missing.
  ///
  /// Consumes a [prefetchLastKnown] result once, then goes back to reading the
  /// OS directly, so a later caller never gets a stale startup value.
  Future<Position?> lastKnownPosition() {
    final prefetched = _prefetchedLastKnown;
    _prefetchedLastKnown = null;
    return prefetched ?? _readLastKnown();
  }

  Future<Position?> _readLastKnown() async {
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

  /// Higher-accuracy stream for active navigation; stops when the subscription
  /// is cancelled at journey end.
  ///
  /// Foreground only, on both platforms. The app ships neither the iOS
  /// `location` background mode nor Android's ACCESS_BACKGROUND_LOCATION, so
  /// the OS stops delivering fixes once the app leaves the screen and the
  /// journey card resumes from the next fix after the app comes back.
  Stream<Position> navigationStream() {
    late final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // AppleSettings.accuracy defaults to best; omitted here to satisfy the
      // analyzer while keeping full-accuracy foreground tracking.
      settings = AppleSettings(
        activityType: ActivityType.otherNavigation,
        // 5 m keeps the follow camera moving at walking pace; 25 m delivered a
        // fix only every ~20 s of walking, which read as "not following".
        distanceFilter: 5,
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
