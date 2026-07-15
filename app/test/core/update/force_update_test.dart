import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

  group('isAllowedStoreUrl', () {
    test('allows the official App Store host over https', () {
      expect(
        isAllowedStoreUrl(Uri.parse('https://apps.apple.com/tw/app/x')),
        isTrue,
      );
    });

    test('allows the official Play Store host over https', () {
      expect(
        isAllowedStoreUrl(
          Uri.parse('https://play.google.com/store/apps/details?id=x'),
        ),
        isTrue,
      );
    });

    test('rejects non-https schemes even on an allowed host', () {
      expect(
        isAllowedStoreUrl(Uri.parse('http://apps.apple.com/tw/app/x')),
        isFalse,
      );
      expect(
        isAllowedStoreUrl(Uri.parse('javascript://apps.apple.com/x')),
        isFalse,
      );
    });

    test('rejects hosts outside the allowlist', () {
      expect(
        isAllowedStoreUrl(
          Uri.parse('https://evil.example.com/apps.apple.com'),
        ),
        isFalse,
      );
      expect(
        isAllowedStoreUrl(Uri.parse('https://apps.apple.com.evil.com/x')),
        isFalse,
      );
    });
  });

  group('ForceUpdateGate', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'wheres_the_car',
        packageName: 'tw.gov.bus',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
    });

    testWidgets('re-checks on each Remote Config revision', (tester) async {
      var minVersion = '0.9.0';
      final controller = StreamController<void>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
          home: ForceUpdateGate(
            revisions: controller.stream,
            minVersionOf: () => minVersion,
            child: const Text('home'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Current version (1.0.0) is not below the initial min (0.9.0).
      expect(find.text('home'), findsOneWidget);
      expect(find.text('請更新至最新版本'), findsNothing);

      // Remote Config raises the bar past the running version without a
      // relaunch; the gate must react to the next revision, not just the
      // initial check.
      minVersion = '5.0.0';
      controller.add(null);
      await tester.pumpAndSettle();

      expect(find.text('請更新至最新版本'), findsOneWidget);
    });
  });
}
