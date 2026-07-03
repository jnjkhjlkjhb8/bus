import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: child)),
  );

  testWidgets('shows offline copy', (tester) async {
    await pump(
      tester,
      const ErrorStateView(error: OfflineError()),
    );
    expect(find.text('目前無法取得即時資訊'), findsOneWidget);
    expect(find.text('已離線,連上網路後可重新整理'), findsOneWidget);
    expect(find.text('重試'), findsNothing);
  });

  testWidgets('retry button fires callback', (tester) async {
    var tapped = false;
    await pump(
      tester,
      ErrorStateView(
        error: const OfflineError(),
        onRetry: () => tapped = true,
      ),
    );
    await tester.tap(find.text('重試'));
    expect(tapped, isTrue);
  });
}
