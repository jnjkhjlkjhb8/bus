import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';

/// Single source for route paths and location construction.
///
/// Call sites build locations through these helpers instead of hand-writing
/// strings, so parameter names and URI encoding cannot drift between the
/// router and its callers. Detail-screen parameters travel in the URL (query
/// or path), which keeps every route cold-deep-linkable and restorable;
/// `state.extra` is only an optional warm-navigation cache.
class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const settings = '/settings';
  static const settingsAppearance = '/settings/appearance';
  static const settingsFareType = '/settings/fare-type';
  static const settingsLanguage = '/settings/language';
  static const search = '/search';
  static const favorites = '/favorites';
  static const busStop = '/bus/stop';
  static const bikeStation = '/bike/station';
  static const rail = '/rail';
  static const metro = '/metro';
  static const go = '/go';
  static const feedback = '/feedback';

  /// The report form, optionally told which screen the rider came from.
  ///
  /// [from] is the concrete location the rider shook on, with the station or
  /// route it was showing: a report that says only which *kind* of screen
  /// misbehaved cannot be acted on. It travels in the URL so the page survives
  /// a cold deep link like every other route here.
  static String feedbackLocation({String? from}) => from == null || from.isEmpty
      ? feedback
      : Uri(path: feedback, queryParameters: {'from': from}).toString();

  /// Route pattern for the bus route detail screen; use [busRoute] to build a
  /// concrete location.
  static const busRoutePattern = '/bus/route/:subRouteUid';

  static String busRoute(String subRouteUid) =>
      '/bus/route/${Uri.encodeComponent(subRouteUid)}';

  /// [lat]/[lon] are an optional first-paint hint: when the caller already
  /// knows where the stop is (search results carry coordinates), the map opens
  /// on it without waiting for the station-group fetch.
  static String busStopLocation({
    required String stopName,
    String? stopId,
    String? city,
    double? lat,
    double? lon,
  }) => Uri(
    path: busStop,
    queryParameters: {
      'name': stopName,
      'id': ?stopId,
      'city': ?city,
      'lat': ?lat?.toString(),
      'lon': ?lon?.toString(),
    },
  ).toString();

  /// [name]/[lat]/[lon] are optional first-paint hints — see
  /// [busStopLocation]. They seed the sheet title and camera target so neither
  /// waits on the static fetch.
  static String bikeStationLocation({
    required String stationUid,
    String? name,
    double? lat,
    double? lon,
  }) => Uri(
    path: bikeStation,
    queryParameters: {
      'uid': stationUid,
      'name': ?name,
      'lat': ?lat?.toString(),
      'lon': ?lon?.toString(),
    },
  ).toString();

  /// The planner opened with its destination already filled in, so a station
  /// detail can hand off to it without the user re-typing where they are
  /// standing. The origin still resolves from GPS as usual.
  static String goToDestination({
    required String name,
    required double lat,
    required double lon,
  }) => Uri(
    path: go,
    queryParameters: {
      'destName': name,
      'destLat': lat.toString(),
      'destLon': lon.toString(),
    },
  ).toString();
}

/// Destination seed for [AppRoutes.go]. Absent or malformed parameters mean
/// the planner opens empty, exactly as it does from the nav bar.
class GoRouteArgs {
  const GoRouteArgs({required this.name, required this.lat, required this.lon});

  final String name;
  final double lat;
  final double lon;

  static GoRouteArgs? from(Map<String, String> query) {
    final name = query['destName'];
    final lat = double.tryParse(query['destLat'] ?? '');
    final lon = double.tryParse(query['destLon'] ?? '');
    if (name == null || name.isEmpty || lat == null || lon == null) return null;
    return GoRouteArgs(name: name, lat: lat, lon: lon);
  }
}

/// Parameters of the `/bus/stop` route, resolved URL-first.
///
/// Query parameters are authoritative so cold deep links and state
/// restoration work without `state.extra`; the legacy extra map is accepted
/// as a fallback cache only.
class BusStopRouteArgs {
  const BusStopRouteArgs({
    required this.stopName,
    this.stopId,
    this.city,
    this.lat,
    this.lon,
  });

  final String stopName;
  final String? stopId;
  final String? city;

  /// Optional first-paint coordinates from the caller; null means the screen
  /// waits for the station-group fetch as before.
  final double? lat;
  final double? lon;

  /// Returns null when neither [query] nor [extra] identify a stop; the
  /// router then renders [RouteErrorScreen] instead of crashing.
  static BusStopRouteArgs? from(Map<String, String> query, Object? extra) {
    final lat = double.tryParse(query['lat'] ?? '');
    final lon = double.tryParse(query['lon'] ?? '');
    final name = query['name'];
    if (name != null && name.isNotEmpty) {
      return BusStopRouteArgs(
        stopName: name,
        stopId: query['id'],
        city: query['city'],
        lat: lat,
        lon: lon,
      );
    }
    if (extra is Map) {
      final cachedName = extra['stopName'];
      final cachedId = extra['stopId'];
      final cachedCity = extra['city'];
      if (cachedName is String && cachedName.isNotEmpty) {
        return BusStopRouteArgs(
          stopName: cachedName,
          stopId: cachedId is String ? cachedId : null,
          city: cachedCity is String ? cachedCity : null,
          lat: lat,
          lon: lon,
        );
      }
    }
    return null;
  }
}

/// Parameters of the `/bike/station` route, resolved URL-first (see
/// [BusStopRouteArgs] for the query-vs-extra policy).
class BikeStationRouteArgs {
  const BikeStationRouteArgs({
    required this.stationUid,
    this.name,
    this.lat,
    this.lon,
  });

  final String stationUid;

  /// Optional first-paint hints from the caller; null means the screen waits
  /// for the static fetch as before.
  final String? name;
  final double? lat;
  final double? lon;

  static BikeStationRouteArgs? from(Map<String, String> query, Object? extra) {
    final name = query['name'];
    final lat = double.tryParse(query['lat'] ?? '');
    final lon = double.tryParse(query['lon'] ?? '');
    final uid = query['uid'];
    if (uid != null && uid.isNotEmpty) {
      return BikeStationRouteArgs(
        stationUid: uid,
        name: name,
        lat: lat,
        lon: lon,
      );
    }
    if (extra is Map) {
      final cached = extra['stationUid'];
      if (cached is String && cached.isNotEmpty) {
        return BikeStationRouteArgs(
          stationUid: cached,
          name: name,
          lat: lat,
          lon: lon,
        );
      }
    }
    return null;
  }
}

/// Typed destination for unmatched locations and malformed route parameters,
/// so a bad deep link degrades to a recoverable page instead of a crash.
class RouteErrorScreen extends StatelessWidget {
  const RouteErrorScreen({required this.uri, super.key});

  /// The location that failed to resolve, shown for diagnosis.
  final Uri uri;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(AppI18n.of(context).routeNotFound),
          const SizedBox(height: 8),
          Text('$uri', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => GoRouter.of(context).go(AppRoutes.home),
            child: Text(AppI18n.of(context).routeGoHome),
          ),
        ],
      ),
    ),
  );
}
