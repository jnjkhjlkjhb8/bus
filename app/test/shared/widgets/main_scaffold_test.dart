import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_bus/features/alerts/view/notice_rail_host.dart';
import 'package:wheres_the_bus/features/go/bloc/plan_bloc.dart';
import 'package:wheres_the_bus/shared/widgets/main_scaffold.dart';
import 'package:wheres_the_bus/shared/widgets/nav_mini_bar.dart';
import 'package:wheres_the_bus/shared/widgets/notice_rail.dart';

import '../../support/helpers/i18n.dart';

void main() {
  Future<AlertBloc> pump(WidgetTester tester) async {
    final alertBloc = AlertBloc();
    final planBloc = PlanBloc();
    addTearDown(alertBloc.close);
    addTearDown(planBloc.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AlertBloc>.value(value: alertBloc),
          BlocProvider<PlanBloc>.value(value: planBloc),
        ],
        child: i18nApp(
          const MainScaffold(shell: Text('branch content')),
        ),
      ),
    );
    return alertBloc;
  }

  testWidgets('renders the notice rail, mini bar, and the branch content', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(NoticeRailHost), findsOneWidget);
    // One rail slot for ops notices, one for conditions; both empty here.
    expect(find.byType(NoticeRail), findsNWidgets(2));
    expect(find.byType(NavMiniBar), findsOneWidget);
    expect(find.text('branch content'), findsOneWidget);
  });

  testWidgets('surfaces the offline rail when alerts go offline', (
    tester,
  ) async {
    final alertBloc = await pump(tester);
    expect(find.text('目前離線，無法取得即時資訊。'), findsNothing);
    alertBloc.add(const AlertStreamFailed(OfflineError()));
    await tester.pump();
    expect(find.text('目前離線，無法取得即時資訊。'), findsOneWidget);
  });

  testWidgets(
    'republishes the banner height as a top inset, so a branch that insets '
    'by MediaQuery.padding.top is not painted over by the banner',
    (tester) async {
      late double topInset;
      late double topViewInset;
      final alertBloc = AlertBloc();
      final planBloc = PlanBloc();
      addTearDown(alertBloc.close);
      addTearDown(planBloc.close);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AlertBloc>.value(value: alertBloc),
            BlocProvider<PlanBloc>.value(value: planBloc),
          ],
          child: i18nApp(
            MainScaffold(
              shell: Builder(
                builder: (context) {
                  topInset = MediaQuery.paddingOf(context).top;
                  topViewInset = MediaQuery.viewPaddingOf(context).top;
                  return const Text('branch content');
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final withoutBanner = topInset;

      alertBloc.add(const AlertStreamFailed(OfflineError()));
      await tester.pumpAndSettle();

      expect(
        topInset,
        greaterThan(withoutBanner),
        reason: 'the rail must reserve space for non-full-bleed branches',
      );
      expect(
        topInset,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byType(NoticeRailHost)).dy,
        ),
        reason: 'the inset must clear the whole rail stack, not part of it',
      );
      expect(
        topViewInset,
        topInset,
        reason:
            'a sheet rebuilds its padding from viewPadding rather than '
            'inheriting it, so a padding-only override is dropped at the '
            'sheet boundary and its pages pad by the bare status bar',
      );
    },
  );
}
