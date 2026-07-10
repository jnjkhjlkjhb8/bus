import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/shared/widgets/status_banner.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required StatusSeverity severity,
    String? message,
    Brightness brightness = Brightness.light,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: StatusBanner(severity: severity, message: message),
      ),
    ),
  );

  testWidgets('collapses when the message is null or empty', (tester) async {
    for (final message in [null, '']) {
      await pump(
        tester,
        severity: StatusSeverity.maintenance,
        message: message,
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(StatusSeverity.maintenance.icon), findsNothing);
      expect(tester.getSize(find.byType(StatusBanner)).height, 0);
    }
  });

  testWidgets('shows message and severity icon when set', (tester) async {
    await pump(tester, severity: StatusSeverity.maintenance, message: '系統維護中');
    await tester.pumpAndSettle();
    expect(find.text('系統維護中'), findsOneWidget);
    expect(find.byIcon(Icons.build_rounded), findsOneWidget);
    expect(tester.getSize(find.byType(StatusBanner)).height, greaterThan(0));
  });

  testWidgets('severity picks its own icon', (tester) async {
    await pump(tester, severity: StatusSeverity.neutral, message: '目前離線');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    expect(find.byIcon(Icons.build_rounded), findsNothing);
  });

  testWidgets('long copy is clamped to two lines', (tester) async {
    await pump(
      tester,
      severity: StatusSeverity.maintenance,
      message: '系統維護中' * 40,
    );
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('maintenance uses warning ink, not the border colour', (
    tester,
  ) async {
    await pump(tester, severity: StatusSeverity.maintenance, message: '維護中');
    await tester.pumpAndSettle();
    final light = tester.widget<Text>(find.byType(Text)).style!.color;
    expect(light, AppTheme.warningInkLight);

    await pump(
      tester,
      severity: StatusSeverity.maintenance,
      message: '維護中',
      brightness: Brightness.dark,
    );
    await tester.pumpAndSettle();
    final dark = tester.widget<Text>(find.byType(Text)).style!.color;
    expect(dark, AppTheme.warningInkDark);
  });
}
