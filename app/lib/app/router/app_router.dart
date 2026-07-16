import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wheres_the_car/app/router/app_routes.dart';
import 'package:wheres_the_car/app/router/debug_ui_kit_routes.dart';
import 'package:wheres_the_car/core/firebase/firebase_gate.dart';
import 'package:wheres_the_car/data/repositories/settings_repository.dart';
import 'package:wheres_the_car/features/bike/view/bike_station_screen.dart';
import 'package:wheres_the_car/features/bus/view/bus_route_screen.dart';
import 'package:wheres_the_car/features/bus/view/bus_stop_screen.dart';
import 'package:wheres_the_car/features/favorites/view/favorites_screen.dart';
import 'package:wheres_the_car/features/go/view/go_screen.dart';
import 'package:wheres_the_car/features/home/home_screen.dart';
import 'package:wheres_the_car/features/metro/view/metro_screen.dart';
import 'package:wheres_the_car/features/rail/view/rail_screen.dart';
import 'package:wheres_the_car/features/search/view/search_screen.dart';
import 'package:wheres_the_car/features/settings/bloc/settings_state.dart';
import 'package:wheres_the_car/features/settings/settings_option_screen.dart';
import 'package:wheres_the_car/features/settings/settings_screen.dart';
import 'package:wheres_the_car/shared/widgets/main_scaffold.dart';

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
/// is [MainScaffold] (banners + floating NavMiniBar over the content), plus
/// the debug-only UI Kit gallery when [includeDebugRoutes] is set.
List<RouteBase> buildAppRoutes({
  required bool includeDebugRoutes,
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
              GoRoute(
                path: 'appearance',
                pageBuilder: (_, state) => _settingsOptionPage<String>(
                  state.extra,
                  title: '外觀',
                  options: [for (final e in Appearance.values) e.label],
                  selected: Appearance.fromKey(
                    SettingsRepository.instance.appearanceMode,
                  ).label,
                ),
              ),
              GoRoute(
                path: 'language',
                pageBuilder: (_, state) => _settingsOptionPage<String>(
                  state.extra,
                  title: '語言',
                  options: [for (final e in Language.values) e.label],
                  // Language is UI-only state (not persisted), so a cold link
                  // starts from the default.
                  selected: Language.system.label,
                ),
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
              return _page(BikeStationScreen(stationUid: args.stationUid));
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
            pageBuilder: (_, _) => _page(const MetroScreen()),
          ),
          GoRoute(
            path: AppRoutes.go,
            pageBuilder: (_, _) => _page(const GoScreen()),
          ),
        ],
      ),
    ],
  ),
  ...debugUiKitRoutes(enabled: includeDebugRoutes),
];

class AppRouter {
  AppRouter._();

  static final rootNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = createRouter(navigatorKey: rootNavigatorKey);

  /// Production configuration behind an injectable entry point: tests create
  /// throwaway routers pinned to a deep-link [initialLocation] or with
  /// release-graph semantics ([includeDebugRoutes] false).
  static GoRouter createRouter({
    GlobalKey<NavigatorState>? navigatorKey,
    bool includeDebugRoutes = kDebugMode,
    String initialLocation = AppRoutes.home,
  }) => GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: initialLocation,
    errorPageBuilder: (_, state) => _page(RouteErrorScreen(uri: state.uri)),
    routes: buildAppRoutes(includeDebugRoutes: includeDebugRoutes),
  );
}
