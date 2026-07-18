import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:wheres_the_car/data/repositories/settings_repository.dart';
import 'package:wheres_the_car/features/settings/settings_screen.dart';

import '../../support/helpers/in_memory_settings_store.dart';

Future<PackageInfo> _packageInfo() async => PackageInfo(
  appName: 'wheres_the_car',
  packageName: 'tw.gov.bus',
  version: '4.5.6',
  buildNumber: '9',
);

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  SettingsRepository repo() =>
      SettingsRepository(store: InMemorySettingsStore());

  Widget buildScreen({DateTime? Function()? lastSyncedAtOf}) => SettingsScreen(
    settings: repo(),
    packageInfoLoader: _packageInfo,
    lastSyncedAtOf: lastSyncedAtOf ?? () => null,
  );

  testWidgets('shows the real PackageInfo version, not a hardcoded one', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(buildScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('目前版本'), 200);

    expect(find.text('4.5.6'), findsOneWidget);
    expect(find.text('1.0.0'), findsNothing);
  });

  testWidgets('shows real PowerSync freshness, not a hardcoded timestamp', (
    tester,
  ) async {
    final synced = DateTime.now().subtract(const Duration(hours: 1));
    await tester.pumpWidget(
      _wrap(buildScreen(lastSyncedAtOf: () => synced)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('TDX 靜態資料'), 200);

    expect(find.textContaining('今日'), findsOneWidget);
    expect(find.text('今日 06:00'), findsNothing);
  });

  testWidgets('shows a not-yet-synced fallback instead of a fake time', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(buildScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('TDX 靜態資料'), 200);

    expect(find.text('尚未同步'), findsOneWidget);
  });

  testWidgets('FAQ / report-issue / privacy-policy rows are not tappable', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(buildScreen()));
    await tester.pumpAndSettle();

    for (final label in ['常見問題 FAQ', '回報問題', '隱私權政策']) {
      final finder = find.ancestor(
        of: find.text(label),
        matching: find.byType(GestureDetector),
      );
      // No enabled tap target reaches these rows any more; each is either
      // absent or explicitly disabled (F45).
      for (final element in finder.evaluate()) {
        final widget = element.widget as GestureDetector;
        expect(
          widget.onTap,
          isNull,
          reason: '$label must not have a live tap handler',
        );
      }
    }
  });

  testWidgets('the language row is not an interactive picker (F48)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(buildScreen()));
    await tester.pumpAndSettle();

    final finder = find.ancestor(
      of: find.text('語言'),
      matching: find.byType(GestureDetector),
    );
    for (final element in finder.evaluate()) {
      final widget = element.widget as GestureDetector;
      expect(widget.onTap, isNull);
    }
  });

  testWidgets('a switch row merges its label and toggle into one node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_wrap(buildScreen()));
    await tester.pumpAndSettle();

    final node = tester.getSemantics(find.text('大字體模式'));
    final data = node.getSemanticsData();
    expect(data.label, contains('大字體模式'));
    expect(
      data.flagsCollection.isToggled,
      isNot(Tristate.none),
      reason: 'label and switch must be merged into a single semantics node',
    );
    handle.dispose();
  });

  testWidgets('rows reflow under a large text scale without overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3)),
          child: buildScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
