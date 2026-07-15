import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  static const settingsLanguage = '/settings/language';
  static const search = '/search';
  static const favorites = '/favorites';
  static const busStop = '/bus/stop';
  static const bikeStation = '/bike/station';
  static const rail = '/rail';
  static const metro = '/metro';
  static const go = '/go';
  static const uiKit = '/ui-kit';

  /// Route pattern for the bus route detail screen; use [busRoute] to build a
  /// concrete location.
  static const busRoutePattern = '/bus/route/:subRouteUid';

  static String busRoute(String subRouteUid) =>
      '/bus/route/${Uri.encodeComponent(subRouteUid)}';

  static String busStopLocation({
    required String stopName,
    String? stopId,
    String? city,
  }) => Uri(
    path: busStop,
    queryParameters: {
      'name': stopName,
      'id': ?stopId,
      'city': ?city,
    },
  ).toString();

  static String bikeStationLocation({required String stationUid}) =>
      Uri(path: bikeStation, queryParameters: {'uid': stationUid}).toString();
}

/// Parameters of the `/bus/stop` route, resolved URL-first.
///
/// Query parameters are authoritative so cold deep links and state
/// restoration work without `state.extra`; the legacy extra map is accepted
/// as a fallback cache only.
class BusStopRouteArgs {
  const BusStopRouteArgs({required this.stopName, this.stopId, this.city});

  final String stopName;
  final String? stopId;
  final String? city;

  /// Returns null when neither [query] nor [extra] identify a stop; the
  /// router then renders [RouteErrorScreen] instead of crashing.
  static BusStopRouteArgs? from(Map<String, String> query, Object? extra) {
    final name = query['name'];
    if (name != null && name.isNotEmpty) {
      return BusStopRouteArgs(
        stopName: name,
        stopId: query['id'],
        city: query['city'],
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
        );
      }
    }
    return null;
  }
}

/// Parameters of the `/bike/station` route, resolved URL-first (see
/// [BusStopRouteArgs] for the query-vs-extra policy).
class BikeStationRouteArgs {
  const BikeStationRouteArgs({required this.stationUid});

  final String stationUid;

  static BikeStationRouteArgs? from(Map<String, String> query, Object? extra) {
    final uid = query['uid'];
    if (uid != null && uid.isNotEmpty) {
      return BikeStationRouteArgs(stationUid: uid);
    }
    if (extra is Map) {
      final cached = extra['stationUid'];
      if (cached is String && cached.isNotEmpty) {
        return BikeStationRouteArgs(stationUid: cached);
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
          const Text('找不到頁面'),
          const SizedBox(height: 8),
          Text('$uri', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => GoRouter.of(context).go(AppRoutes.home),
            child: const Text('回首頁'),
          ),
        ],
      ),
    ),
  );
}
