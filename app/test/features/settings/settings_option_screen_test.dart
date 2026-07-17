import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/features/settings/settings_option_screen.dart';

void main() {
  testWidgets('option row tap target is at least 44x44 (HIG minimum)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsOptionScreen(
          title: 'Test',
          options: ['A', 'B', 'C'],
          initialSelected: 'A',
        ),
      ),
    );

    final inkWells = find.byType(InkWell);
    expect(inkWells, findsNWidgets(3));
    for (final element in inkWells.evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(
        size.height,
        greaterThanOrEqualTo(44),
        reason: 'option row tap target must be >= 44 logical px tall',
      );
    }
  });
}
