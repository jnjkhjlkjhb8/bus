import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Compass bearing from [a] to [b] in degrees, or null when the two points sit
/// closer than [minMeters] apart.
///
/// The fallback for a vehicle whose reported azimuth is unusable: TDX sends 0
/// both for "heading due north" and for "no heading at all". Below [minMeters]
/// the bearing between two fixes is GPS noise rather than a direction of
/// travel, so it is refused instead of pointing the vehicle somewhere
/// arbitrary.
///
/// Equirectangular rather than great-circle: over the metres-to-hundreds-of-
/// metres a live frame moves, the two agree far inside the precision a marker
/// rotation can show.
double? bearingIfMoved(LatLng a, LatLng b, {double minMeters = 5}) {
  const metresPerDegree = 111320.0;
  final north = (b.latitude - a.latitude) * metresPerDegree;
  final east =
      (b.longitude - a.longitude) *
      metresPerDegree *
      math.cos(a.latitude * math.pi / 180);
  if (north * north + east * east < minMeters * minMeters) return null;
  return (math.atan2(east, north) * 180 / math.pi + 360) % 360;
}

/// Interpolates [a] → [b] the short way round the compass, so a bus crossing
/// north glides 350° → 10° through zero instead of unwinding backwards through
/// 180°.
///
/// The result is deliberately not normalised to 0–360: `Marker.rotation` takes
/// any degree value, and clamping mid-glide would reintroduce the jump.
double lerpHeading(double a, double b, double t) =>
    a + (((b - a + 540) % 360) - 180) * t;
