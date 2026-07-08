import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/shared/widgets/app_snackbar.dart';

void main() {
  Future<void> tap(WidgetTester tester, void Function(BuildContext) onTap) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => onTap(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

  testWidgets('neutral shows the message with no leading icon', (tester) async {
    await tap(tester, (c) => AppSnackbar.show(c, '開發者模式已啟用'));
    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.text('開發者模式已啟用'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('success shows a leading icon', (tester) async {
    await tap(
      tester,
      (c) => AppSnackbar.show(c, '已抵達目的地', type: SnackType.success),
    );
    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
  });

  testWidgets('action tap invokes callback and dismisses the toast', (
    tester,
  ) async {
    var undone = false;
    await tap(
      tester,
      (c) => AppSnackbar.show(
        c,
        '已清除 3 則通知',
        action: '復原',
        onAction: () => undone = true,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('復原'), findsOneWidget);

    await tester.tap(find.text('復原'));
    await tester.pumpAndSettle();

    expect(undone, isTrue);
    expect(find.text('已清除 3 則通知'), findsNothing);
  });
}
