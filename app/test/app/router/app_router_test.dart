import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:wheres_the_car/app/router/app_router.dart';
import 'package:wheres_the_car/app/router/app_routes.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/go/bloc/plan_bloc.dart';
import 'package:wheres_the_car/features/settings/settings_option_screen.dart';
import 'package:wheres_the_car/shared/widgets/main_scaffold.dart';

/// Flattens the route tree into the full set of route path patterns.
List<String> collectPaths(List<RouteBase> routes) {
  final paths = <String>[];
  void visit(RouteBase route) {
    if (route is GoRoute) paths.add(route.path);
    route.routes.forEach(visit);
  }

  routes.forEach(visit);
  return paths;
}

void main() {
  setUpAll(() async {
    // SettingsScreen (the /settings shell parent of the option routes) reads
    // the settings box on bloc construction, so back the repository with a
    // real on-disk box the same way other Hive-touching tests do.
    Hive.init('./.dart_tool/hive_test_app_router');
    await Hive.openBox<dynamic>('settings');
  });

  Future<void> pumpAt(WidgetTester tester, String location) async {
    final router = AppRouter.createRouter(initialLocation: location);
    final alertBloc = AlertBloc();
    final planBloc = PlanBloc();
    addTearDown(router.dispose);
    addTearDown(alertBloc.close);
    addTearDown(planBloc.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AlertBloc>.value(value: alertBloc),
          BlocProvider<PlanBloc>.value(value: planBloc),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
  }

  group('route graph', () {
    test('release graph excludes every UI Kit route', () {
      final paths = collectPaths(buildAppRoutes(includeDebugRoutes: false));
      expect(paths.where((p) => p.contains('ui-kit')), isEmpty);
    });

    test('debug graph includes the UI Kit gallery', () {
      final paths = collectPaths(buildAppRoutes(includeDebugRoutes: true));
      expect(paths, contains(AppRoutes.uiKit));
    });

    test('main routes match the documented architecture', () {
      final paths = collectPaths(buildAppRoutes(includeDebugRoutes: false));
      const expected = [
        '/',
        '/search',
        '/favorites',
        '/bus/stop',
        '/bus/route/:subRouteUid',
        '/bike/station',
        '/rail',
        '/metro',
        '/go',
        '/settings',
      ];
      for (final path in expected) {
        expect(paths, contains(path));
      }
    });
  });

  group('cold deep links (no state.extra)', () {
    testWidgets('settings appearance renders the option screen', (
      tester,
    ) async {
      await pumpAt(tester, AppRoutes.settingsAppearance);
      expect(find.byType(SettingsOptionScreen), findsOneWidget);
      expect(find.byType(RouteErrorScreen), findsNothing);
    });

    testWidgets('settings language renders the option screen', (tester) async {
      await pumpAt(tester, AppRoutes.settingsLanguage);
      expect(find.byType(SettingsOptionScreen), findsOneWidget);
      expect(find.byType(RouteErrorScreen), findsNothing);
    });

    testWidgets('shell wraps routed content in MainScaffold', (tester) async {
      await pumpAt(tester, AppRoutes.settings);
      expect(find.byType(MainScaffold), findsOneWidget);
    });
  });

  group('malformed parameters', () {
    testWidgets('bus stop without a name shows the typed error page', (
      tester,
    ) async {
      await pumpAt(tester, AppRoutes.busStop);
      expect(find.byType(RouteErrorScreen), findsOneWidget);
    });

    testWidgets('bike station without a uid shows the typed error page', (
      tester,
    ) async {
      await pumpAt(tester, AppRoutes.bikeStation);
      expect(find.byType(RouteErrorScreen), findsOneWidget);
    });

    testWidgets('an unknown location shows the typed error page', (
      tester,
    ) async {
      await pumpAt(tester, '/no-such-route');
      expect(find.byType(RouteErrorScreen), findsOneWidget);
    });
  });
}
