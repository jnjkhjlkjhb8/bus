import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wheres_the_bus/app/router/app_routes.dart';
import 'package:wheres_the_bus/core/diagnostics/report_screen.dart';
import 'package:wheres_the_bus/features/feedback/view/shake_report_host.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';

/// Feeds a full out-back-out shake through [samples].
Future<void> _shake(
  WidgetTester tester,
  StreamController<UserAccelerometerEvent> samples,
) async {
  for (final x in [20.0, -20.0, 20.0, -20.0]) {
    samples.add(UserAccelerometerEvent(x, 0, 0, DateTime.now()));
    await tester.pump(const Duration(milliseconds: 80));
  }
  await tester.pumpAndSettle();
}

/// Mounts the host over a two-route router. [openedFrom] collects the `from`
/// parameter every time the report route is built, which is the contract the
/// gesture has to keep: the report must name the screen the rider shook on,
/// not the form itself.
Future<void> _pump(
  WidgetTester tester,
  StreamController<UserAccelerometerEvent> samples, {
  required List<String?> openedFrom,
  String initialLocation = AppRoutes.busStop,
}) async {
  Widget host(Widget child) =>
      ShakeReportHost(samples: samples.stream, child: child);
  await tester.pumpWidget(
    MaterialApp.router(
      locale: const Locale('zh'),
      localizationsDelegates: AppI18n.localizationsDelegates,
      supportedLocales: AppI18n.supportedLocales,
      routerConfig: GoRouter(
        initialLocation: initialLocation,
        routes: [
          GoRoute(
            path: AppRoutes.busStop,
            builder: (_, _) => host(const Scaffold(body: Text('stop'))),
          ),
          GoRoute(
            path: AppRoutes.feedback,
            builder: (_, state) {
              openedFrom.add(state.uri.queryParameters['from']);
              return host(const Scaffold(body: Text('form')));
            },
          ),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late StreamController<UserAccelerometerEvent> samples;
  late List<String?> openedFrom;

  setUp(() {
    samples = StreamController<UserAccelerometerEvent>.broadcast();
    openedFrom = [];
  });
  tearDown(() => samples.close());

  testWidgets('a shake asks before it navigates', (tester) async {
    await _pump(tester, samples, openedFrom: openedFrom);

    await _shake(tester, samples);

    expect(find.text('有什麼要告訴開發者的？'), findsOneWidget);
    // Asking is not going: nothing has been opened yet.
    expect(openedFrom, isEmpty);
  });

  testWidgets('confirming opens the form and names the screen behind it', (
    tester,
  ) async {
    await _pump(tester, samples, openedFrom: openedFrom);
    await _shake(tester, samples);

    await tester.tap(find.text('回報問題'));
    await tester.pumpAndSettle();

    expect(find.text('form'), findsOneWidget);
    expect(openedFrom, [AppRoutes.busStop]);
  });

  testWidgets('declining leaves the rider where they were', (tester) async {
    await _pump(tester, samples, openedFrom: openedFrom);
    await _shake(tester, samples);

    await tester.tap(find.text('不用了'));
    await tester.pumpAndSettle();

    expect(find.text('有什麼要告訴開發者的？'), findsNothing);
    expect(find.text('stop'), findsOneWidget);
    expect(openedFrom, isEmpty);
  });

  // A station opened inside the home sheet is not a route, so without the held
  // detail every report from one would name `/bus/stop` and no station.
  testWidgets('a held detail names the station the route cannot', (
    tester,
  ) async {
    ReportScreen.hold(route: AppRoutes.busStop, detail: 'bus:1234 台北車站');
    addTearDown(ReportScreen.release);
    await _pump(tester, samples, openedFrom: openedFrom);
    await _shake(tester, samples);

    await tester.tap(find.text('回報問題'));
    await tester.pumpAndSettle();

    expect(openedFrom, ['${AppRoutes.busStop} · bus:1234 台北車站']);
  });

  testWidgets('a detail held for another screen is left behind', (
    tester,
  ) async {
    ReportScreen.hold(route: AppRoutes.home, detail: 'bus:1234 台北車站');
    addTearDown(ReportScreen.release);
    await _pump(tester, samples, openedFrom: openedFrom);
    await _shake(tester, samples);

    await tester.tap(find.text('回報問題'));
    await tester.pumpAndSettle();

    expect(openedFrom, [AppRoutes.busStop]);
  });

  // Answering "report a problem" with the form the rider is already looking at
  // is an interface that isn't listening.
  testWidgets('shaking on the form itself does nothing', (tester) async {
    await _pump(
      tester,
      samples,
      openedFrom: openedFrom,
      initialLocation: AppRoutes.feedback,
    );

    await _shake(tester, samples);

    expect(find.text('有什麼要告訴開發者的？'), findsNothing);
    expect(find.text('form'), findsOneWidget);
  });
}
