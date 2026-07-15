import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_eta_state.dart';
import 'package:wheres_the_car/features/metro/view/metro_station_detail_view.dart';
import 'package:wheres_the_car/shared/widgets/eta_list_tile.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    ),
  );

  testWidgets('metro arrival renders through the shared EtaListTile', (
    tester,
  ) async {
    await pump(
      tester,
      const MetroArrivalTile(
        arrival: MetroArrival(
          line: 'R',
          destination: '淡水',
          estimateMinutes: 4,
          approaching: false,
        ),
      ),
    );

    // Metro rows go through the shared tile (in its bare variant), not a
    // hand-rolled Row.
    expect(find.byType(EtaListTile), findsOneWidget);
    expect(find.text('往 淡水'), findsOneWidget);
    // The minute value renders through the shared mono time column.
    final minutes = tester.widget<Text>(find.text('4'));
    expect(minutes.style?.fontFamily, 'IBMPlexMono');
    expect(
      minutes.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('an approaching train shows the approaching label', (
    tester,
  ) async {
    await pump(
      tester,
      const MetroArrivalTile(
        arrival: MetroArrival(
          line: 'BL',
          destination: '南港',
          estimateMinutes: 0,
          approaching: true,
        ),
      ),
    );

    expect(find.byType(EtaListTile), findsOneWidget);
    expect(find.text('即將進站'), findsOneWidget);
  });
}
