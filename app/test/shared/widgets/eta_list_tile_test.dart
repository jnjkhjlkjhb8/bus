import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/arrival_display.dart';
import 'package:wheres_the_car/shared/widgets/eta_list_tile.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(theme: AppTheme.light, home: Scaffold(body: child)),
  );

  const arriving = ArrivalDisplay(
    label: '307',
    destination: '板橋',
    status: EtaArriving(),
    rank: 0,
  );

  testWidgets('renders label, destination, and status', (tester) async {
    await pump(
      tester,
      const EtaListTile(
        routeNo: '307',
        destination: '板橋',
        status: EtaArriving(),
      ),
    );

    expect(find.text('307'), findsOneWidget);
    expect(find.text('往 板橋'), findsOneWidget);
    expect(find.text('進站中'), findsOneWidget);
  });

  testWidgets('fromDisplay renders the ArrivalDisplay contract', (
    tester,
  ) async {
    await pump(tester, EtaListTile.fromDisplay(arriving));

    expect(find.text('307'), findsOneWidget);
    expect(find.text('往 板橋'), findsOneWidget);
    expect(find.text('進站中'), findsOneWidget);
  });

  testWidgets('time value uses the mono font (tabular figures)', (
    tester,
  ) async {
    await pump(
      tester,
      const EtaListTile(
        routeNo: '桃園106',
        destination: '中壢火車站',
        status: EtaMinutes(5),
      ),
    );

    final minutes = tester.widget<Text>(find.text('5'));
    expect(minutes.style?.fontFamily, 'IBMPlexMono');
    expect(
      minutes.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('highlight applies to the rank-0 row only', (tester) async {
    await pump(
      tester,
      Column(
        children: [
          EtaListTile.fromDisplay(arriving, highlighted: true),
          EtaListTile.fromDisplay(
            const ArrivalDisplay(
              label: '261',
              destination: '銘傳大學',
              status: EtaMinutes(5),
              rank: 5,
            ),
          ),
        ],
      ),
    );

    // Exactly one row draws the surface-highlight background; the plain row
    // draws no decoration.
    final highlighted = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final decoration = w.decoration;
      return decoration is BoxDecoration &&
          decoration.color == AppTheme.surfaceHighlightLight;
    });
    expect(highlighted, findsOneWidget);
  });
}
