import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_car/features/go/bloc/plan_bloc.dart';
import 'package:wheres_the_car/shared/widgets/main_scaffold.dart';
import 'package:wheres_the_car/shared/widgets/maintenance_banner.dart';
import 'package:wheres_the_car/shared/widgets/nav_mini_bar.dart';
import 'package:wheres_the_car/shared/widgets/offline_banner.dart';

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
        child: const MaterialApp(
          home: MainScaffold(shell: Text('branch content')),
        ),
      ),
    );
    return alertBloc;
  }

  testWidgets('renders banners, mini bar, and the branch content', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(MaintenanceBanner), findsOneWidget);
    expect(find.byType(OfflineBanner), findsOneWidget);
    expect(find.byType(NavMiniBar), findsOneWidget);
    expect(find.text('branch content'), findsOneWidget);
  });

  testWidgets('surfaces the offline banner when alerts go offline', (
    tester,
  ) async {
    final alertBloc = await pump(tester);
    expect(find.text('目前離線，顯示快取資料。'), findsNothing);
    alertBloc.add(const AlertStreamFailed(OfflineError()));
    await tester.pump();
    expect(find.text('目前離線，顯示快取資料。'), findsOneWidget);
  });
}
