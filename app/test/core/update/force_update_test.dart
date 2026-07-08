import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/update/force_update.dart';

void main() {
  test('below the minimum', () {
    expect(isBelowMinVersion('1.0.0', '1.2.0'), isTrue);
    expect(isBelowMinVersion('1.9.9', '2.0.0'), isTrue);
    expect(isBelowMinVersion('1.2', '1.2.1'), isTrue);
  });

  test('equal or above is not blocked', () {
    expect(isBelowMinVersion('1.2.0', '1.2.0'), isFalse);
    expect(isBelowMinVersion('2.0.0', '1.9.9'), isFalse);
    expect(isBelowMinVersion('1.2.1', '1.2'), isFalse);
  });

  test('build/pre-release suffix on current is ignored', () {
    expect(isBelowMinVersion('1.2.0+42', '1.2.0'), isFalse);
    expect(isBelowMinVersion('1.1.0-beta', '1.2.0'), isTrue);
  });

  test('malformed input fails open (never locks users out)', () {
    expect(isBelowMinVersion('1.0.0', 'garbage'), isFalse);
    expect(isBelowMinVersion('', '1.0.0'), isFalse);
    expect(isBelowMinVersion('1.x.0', '1.2.0'), isFalse);
  });
}
