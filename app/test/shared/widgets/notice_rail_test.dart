import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/data/models/alert_models.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/widgets/notice_rail.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    NoticeRail rail, {
    double textScale = 1,
    Brightness brightness = Brightness.light,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppI18n.localizationsDelegates,
      supportedLocales: AppI18n.supportedLocales,

      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: Column(children: [rail])),
      ),
    ),
  );

  testWidgets('an empty message collapses the strip', (tester) async {
    await pump(
      tester,
      const NoticeRail(tone: NoticeTone.caution, icon: Icons.build_rounded),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('carries an action and a dismiss when both are given', (
    tester,
  ) async {
    var opened = 0;
    var dismissed = 0;
    await pump(
      tester,
      NoticeRail(
        tone: NoticeTone.neutral,
        icon: Icons.location_off_rounded,
        message: '未取得定位權限，地圖顯示預設位置。',
        actionLabel: '開啟定位權限',
        onAction: () => opened++,
        onDismiss: () => dismissed++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('開啟定位權限'));
    await tester.tap(find.byTooltip('關閉'));
    expect(opened, 1);
    expect(dismissed, 1);
  });

  testWidgets('the dismiss target keeps the 44px floor', (tester) async {
    await pump(
      tester,
      NoticeRail(
        tone: NoticeTone.info,
        icon: Icons.campaign_rounded,
        message: '新功能上線。',
        onDismiss: () {},
      ),
    );
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byTooltip('關閉'));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  // The rail is full-bleed and hosts long Traditional Chinese copy; older-user
  // mode scales it further. Any overflow here paints over the app shell.
  for (final scale in [1.0, 1.3, 2.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('lays out long copy at ${scale}x, ${brightness.name}', (
        tester,
      ) async {
        await pump(
          tester,
          NoticeRail(
            tone: NoticeTone.caution,
            icon: Icons.build_rounded,
            message:
                '系統維護中（03:00–05:00），即時到站與規劃可能暫停，'
                '靜態時刻表不受影響。造成不便敬請見諒，我們會盡快恢復服務。',
            actionLabel: '查看說明',
            onAction: () {},
            onDismiss: () {},
          ),
          textScale: scale,
          brightness: brightness,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
