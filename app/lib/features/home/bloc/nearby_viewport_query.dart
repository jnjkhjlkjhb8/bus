import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Backend hard cap on the nearby-station search radius — must track
/// `maxNearbyRadius` in services/router/nearby.go. A query beyond this is
/// rejected outright, so the client clamps before ever sending it.
const kNearbyMaxRadiusMeters = 5000;

/// Floor so a fully collapsed/zero-size viewport still asks for a sensible
/// area rather than a near-zero radius.
const kNearbyMinRadiusMeters = 100;

const _earthRadiusMeters = 6371000.0;

/// Great-circle distance between [a] and [b], in metres.
double haversineMeters(LatLng a, LatLng b) {
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLon = (b.longitude - a.longitude) * math.pi / 180;
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return _earthRadiusMeters * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

/// Search radius, in whole metres, spanning [center] to the farthest corner
/// of [bounds] — so a query covers everything currently on screen — clamped
/// to the backend's accepted range.
int nearbyRadiusForViewport({
  required LatLng center,
  required LatLngBounds bounds,
}) {
  final corners = [
    bounds.northeast,
    bounds.southwest,
    LatLng(bounds.northeast.latitude, bounds.southwest.longitude),
    LatLng(bounds.southwest.latitude, bounds.northeast.longitude),
  ];
  final farthest = corners
      .map((corner) => haversineMeters(center, corner))
      .reduce(math.max);
  return farthest.round().clamp(
    kNearbyMinRadiusMeters,
    kNearbyMaxRadiusMeters,
  );
}

/// Viewport-query bookkeeping for the home map: [lastAttempted] tracks every
/// center a query was actually sent for (success or failure), while
/// [lastSuccessful] only advances on a successful response. Deduping future
/// idle-triggered queries against [lastSuccessful] — not [lastAttempted] —
/// means a failed request never suppresses a retry at the same spot.
class NearbyViewportQuery {
  const NearbyViewportQuery({this.lastAttempted, this.lastSuccessful});

  final LatLng? lastAttempted;
  final LatLng? lastSuccessful;

  /// Whether [center] is far enough from the last *successful* query to be
  /// worth re-fetching.
  bool shouldQuery(LatLng center, {double thresholdMeters = 200}) {
    final last = lastSuccessful;
    if (last == null) return true;
    return haversineMeters(center, last) >= thresholdMeters;
  }

  NearbyViewportQuery withAttempted(LatLng center) => NearbyViewportQuery(
    lastAttempted: center,
    lastSuccessful: lastSuccessful,
  );

  NearbyViewportQuery withSuccess(LatLng center) => NearbyViewportQuery(
    lastAttempted: lastAttempted,
    lastSuccessful: center,
  );
}
