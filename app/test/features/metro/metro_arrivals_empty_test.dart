import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_state.dart';
import 'package:wheres_the_car/features/metro/view/metro_station_detail_view.dart';

void main() {
  const schedule = [
    MetroSchedule(destination: '南港展覽館', firstTime: '06:02', lastTime: '00:37'),
    MetroSchedule(destination: '動物園', firstTime: '06:00', lastTime: '00:40'),
  ];

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    ),
  );

  group('metroServiceStatus', () {
    test('midday counts as running', () {
      final s = metroServiceStatus(schedule, DateTime(2026, 7, 12, 12));
      expect(s.state, MetroServiceState.running);
    });

    test('after the last past-midnight train counts as ended', () {
      // 00:50 is after every 00:3x/00:40 last train.
      final s = metroServiceStatus(schedule, DateTime(2026, 7, 12, 0, 50));
      expect(s.state, MetroServiceState.ended);
      expect(s.lastTrain, '00:40');
      expect(s.firstTrain, '06:00');
      expect(s.firstDestination, '動物園');
    });

    test('an evening time before midnight is still running', () {
      final s = metroServiceStatus(schedule, DateTime(2026, 7, 12, 23, 30));
      expect(s.state, MetroServiceState.running);
    });

    test('pre-dawn before the first train counts as before-first', () {
      final s = metroServiceStatus(schedule, DateTime(2026, 7, 12, 5));
      expect(s.state, MetroServiceState.beforeFirst);
    });
  });

  testWidgets('closed-service card renders when service has ended', (
    tester,
  ) async {
    await pump(
      tester,
      MetroArrivalsEmpty(schedule: schedule, now: DateTime(2026, 7, 12, 0, 50)),
    );

    expect(find.text('今日已收班'), findsOneWidget);
    expect(find.text('末班車已於 00:40 發出'), findsOneWidget);
    expect(find.text('06:00'), findsOneWidget);
    expect(find.text('明日首班 · 往 動物園'), findsOneWidget);
    // Not the old dead-end string.
    expect(find.text('目前無列車資訊'), findsNothing);
  });

  testWidgets('running service with no live data keeps the quiet line', (
    tester,
  ) async {
    await pump(
      tester,
      MetroArrivalsEmpty(schedule: schedule, now: DateTime(2026, 7, 12, 12)),
    );

    expect(find.text('目前無列車資訊'), findsOneWidget);
    expect(find.text('今日已收班'), findsNothing);
  });

  testWidgets('no schedule at all falls back to the quiet line', (
    tester,
  ) async {
    await pump(tester, const MetroArrivalsEmpty(schedule: []));
    expect(find.text('目前無列車資訊'), findsOneWidget);
  });
}
