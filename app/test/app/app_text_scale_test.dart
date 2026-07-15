import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/app/app.dart';

void main() {
  group('applyLargeTextFloor', () {
    test('raises a system scale below the large-text floor', () {
      final result = applyLargeTextFloor(TextScaler.noScaling);
      expect(result.scale(10), const TextScaler.linear(1.3).scale(10));
    });

    test('leaves a system scale already above the floor untouched', () {
      final result = applyLargeTextFloor(const TextScaler.linear(1.5));
      expect(result.scale(10), const TextScaler.linear(1.5).scale(10));
    });

    // F51: the old implementation additionally capped at 1.6, silently
    // rolling back a larger system-level accessibility preference. The
    // floor must never become a ceiling.
    test('does not cap a system scale above the old 1.6 ceiling', () {
      final result = applyLargeTextFloor(const TextScaler.linear(3));
      expect(result.scale(10), const TextScaler.linear(3).scale(10));
    });
  });
}
