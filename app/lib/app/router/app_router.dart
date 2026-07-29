import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:wheres_the_bus/app/router/app_routes.dart';
import 'package:wheres_the_bus/core/firebase/firebase_gate.dart';
import 'package:wheres_the_bus/data/models/fare_type.dart';
import 'package:wheres_the_bus/data/repositories/settings_repository.dart';
import 'package:wheres_the_bus/features/bike/view/bike_station_screen.dart';
import 'package:wheres_the_bus/features/bus/view/bus_route_screen.dart';
import 'package:wheres_the_bus/features/bus/view/bus_stop_screen.dart';
import 'package:wheres_the_bus/features/favorites/view/favorites_screen.dart';
import 'package:wheres_the_bus/features/feedback/view/feedback_screen.dart';
import 'package:wheres_the_bus/features/go/model/planned_place.dart';
import 'package:wheres_the_bus/features/go/view/go_screen.dart';
import 'package:wheres_the_bus/features/home/home_screen.dart';
import 'package:wheres_the_bus/features/metro/view/metro_screen.dart';
import 'package:wheres_the_bus/features/rail/view/rail_screen.dart';
import 'package:wheres_the_bus/features/search/view/search_screen.dart';
import 'package:wheres_the_bus/features/settings/bloc/settings_state.dart';
import 'package:wheres_the_bus/features/settings/settings_option_screen.dart';
import 'package:wheres_the_bus/features/settings/settings_screen.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/widgets/main_scaffold.dart';

Page<T> _page<T>(Widget child) => MaterialPage<T>(child: child);

/// Reads an optional `{options: List<String>, selected: String}` cache from
/// `state.extra`, falling back to [options]/[selected] when absent so the
/// settings option routes survive cold deep links and state restoration.
Page<T> _settingsOptionPage<T>(
  Object? extra, {
  required String title,
  required List<String> options,
  required String selected,
}) {
  var effectiveOptions = options;
  var effectiveSelected = selected;
  if (extra is Map) {
    final cachedOptions = extra['options'];
    final cachedSelected = extra['selected'];
    if (cachedOptions is List) {
      final parsed = cachedOptions.whereType<String>().toList();
      if (parsed.isNotEmpty) effectiveOptions = parsed;
    }
    if (cachedSelected is String) effectiveSelected = cachedSelected;
  }
  return _page(
    SettingsOptionScreen(
      title: title,
      options: effectiveOptions,
      initialSelected: effectiveSelected,
    ),
  );
}

class _DeferredAnalyticsObserver extends NavigatorObserver {
  FirebaseAnalyticsObserver? _delegate;

  FirebaseAnalyticsObserver? get _observer {
    if (Firebase.apps.isEmpty) return null;
    return _delegate ??= FirebaseAnalyticsObserver(
      analytics: FirebaseAnalytics.instance,
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _observer?.didPush(route, previousRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _observer?.didPop(route, previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _observer?.didReplace(newRoute: newRoute, oldRoute: oldRoute);
}

/// Builds the app's route graph: one [StatefulShellRoute] branch whose shell
/// is [MainScaffold] (banners + floating NavMiniBar over the content).
List<RouteBase> buildAppRoutes({
  bool firebaseEnabled = FirebaseGate.enabled,
}) => [
  StatefulShellRoute.indexedStack(
    builder: (context, state, navigationShell) =>
        MainScaffold(shell: navigationShell),
    branches: [
      StatefulShellBranch(
        observers: firebaseEnabled ? [_DeferredAnalyticsObserver()] : const [],
        routes: [
          GoRoute(
            path: AppRoutes.home,
            pageBuilder: (_, _) => const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (_, _) => _page(const SettingsScreen()),
            routes: [
              // Each picker resolves its own labels rather than relying on the
              // ones the settings screen passed through `extra`, so a cold
              // deep link into the route lands on a fully labelled screen.
              GoRoute(
                path: 'appearance',
                pageBuilder: (context, state) {
                  final i18n = AppI18n.of(context);
                  return _settingsOptionPage<String>(
                    state.extra,
                    title: i18n.settingsAppearance,
                    options: [
                      for (final e in Appearance.values) e.labelOf(i18n),
                    ],
                    selected: Appearance.fromKey(
                      SettingsRepository.instance.appearanceMode,
                    ).labelOf(i18n),
                  );
                },
              ),
              GoRoute(
                path: 'fare-type',
                pageBuilder: (context, state) {
                  final i18n = AppI18n.of(context);
                  return _settingsOptionPage<String>(
                    state.extra,
                    title: i18n.settingsFareType,
                    options: [for (final e in FareType.values) e.labelOf(i18n)],
                    selected: SettingsRepository.instance.fareType.labelOf(
                      i18n,
                    ),
                  );
                },
              ),
              GoRoute(
                path: 'language',
                pageBuilder: (context, state) {
                  final i18n = AppI18n.of(context);
                  return _settingsOptionPage<String>(
                    state.extra,
                    title: i18n.settingsLanguage,
                    options: [for (final e in Language.values) e.labelOf(i18n)],
                    selected: Language.fromKey(
                      SettingsRepository.instance.languageCode,
                    ).labelOf(i18n),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.search,
            pageBuilder: (_, _) => _page(const SearchScreen()),
          ),
          GoRoute(
            path: AppRoutes.favorites,
            pageBuilder: (_, _) => _page(const FavoritesScreen()),
          ),
          GoRoute(
            path: AppRoutes.busStop,
            pageBuilder: (_, state) {
              final args = BusStopRouteArgs.from(
                state.uri.queryParameters,
                state.extra,
              );
              if (args == null) return _page(RouteErrorScreen(uri: state.uri));
              return _page(
                BusStopScreen(
                  stopName: args.stopName,
                  stopId: args.stopId,
                  city: args.city,
                  lat: args.lat,
                  lon: args.lon,
                ),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.bikeStation,
            pageBuilder: (_, state) {
              final args = BikeStationRouteArgs.from(
                state.uri.queryParameters,
                state.extra,
              );
              if (args == null) return _page(RouteErrorScreen(uri: state.uri));
              return _page(
                BikeStationScreen(
                  stationUid: args.stationUid,
                  name: args.name,
                  lat: args.lat,
                  lon: args.lon,
                ),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.busRoutePattern,
            pageBuilder: (_, state) {
              final uid = state.pathParameters['subRouteUid'] ?? '';
              if (uid.isEmpty) return _page(RouteErrorScreen(uri: state.uri));
              return _page(BusRouteScreen(subRouteUid: uid));
            },
          ),
          GoRoute(
            path: AppRoutes.rail,
            pageBuilder: (_, _) => _page(const RailScreen()),
          ),
          GoRoute(
            path: AppRoutes.metro,
            pageBuilder: (_, state) =>
                _page(MetroScreen(initialStation: state.extra as String?)),
          ),
          GoRoute(
            path: AppRoutes.feedback,
            pageBuilder: (_, state) => _page(
              FeedbackScreen(fromScreen: state.uri.queryParameters['from']),
            ),
          ),
          GoRoute(
            path: AppRoutes.go,
            pageBuilder: (_, state) {
              final args = GoRouteArgs.from(state.uri.queryParameters);
              return _page(
                GoScreen(
                  initialDestination: args == null
                      ? null
                      : PlannedPlace(
                          name: args.name,
                          latLng: LatLng(args.lat, args.lon),
                        ),
                ),
              );
            },
          ),
        ],
      ),
    ],
  ),
];

class AppRouter {
  AppRouter._();

  static final rootNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = createRouter(navigatorKey: rootNavigatorKey);

  /// Production configuration behind an injectable entry point: tests create
  /// throwaway routers pinned to a deep-link [initialLocation].
  static GoRouter createRouter({
    GlobalKey<NavigatorState>? navigatorKey,
    String initialLocation = AppRoutes.home,
  }) => GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: initialLocation,
    errorPageBuilder: (_, state) => _page(RouteErrorScreen(uri: state.uri)),
    routes: buildAppRoutes(),
  );
}
