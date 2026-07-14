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

  testWidgets('tapping a metro arrival expands the 6-car crowding board', (
    tester,
  ) async {
    await pump(
      tester,
      const SizedBox(
        width: 390,
        child: MetroArrivalTile(
          arrival: MetroArrival(
            line: 'BL',
            destination: '南港展覽館',
            estimateMinutes: 0,
            approaching: true,
          ),
        ),
      ),
    );

    // Collapsed: no crowding board yet.
    expect(find.text('車廂擁擠度'), findsNothing);

    await tester.tap(find.byType(EtaListTile));
    await tester.pumpAndSettle();

    // Six car cells with their labels, plus the four-level legend.
    expect(find.text('車廂擁擠度'), findsOneWidget);
    expect(find.text('車廂1'), findsOneWidget);
    expect(find.text('車廂6'), findsOneWidget);
    expect(find.text('非常擁擠'), findsOneWidget);

    // Regression: the car shapes must actually paint (a no-child ColoredBox /
    // DecoratedBox under loose width collapses to zero — nothing shows).
    final head = tester.getSize(find.byType(ClipPath).first);
    expect(head.width, greaterThan(0));
    expect(head.height, 44);
  });
}
