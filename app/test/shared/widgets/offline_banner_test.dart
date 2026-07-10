import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_car/shared/widgets/offline_banner.dart';

void main() {
  Future<AlertBloc> pump(WidgetTester tester) async {
    final bloc = AlertBloc();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AlertBloc>.value(
          value: bloc,
          child: const Scaffold(body: OfflineBanner()),
        ),
      ),
    );
    return bloc;
  }

  testWidgets('hidden when no error', (tester) async {
    final bloc = await pump(tester);
    addTearDown(bloc.close);
    expect(find.text('目前離線，顯示快取資料。'), findsNothing);
  });

  testWidgets('visible when offline', (tester) async {
    final bloc = await pump(tester);
    addTearDown(bloc.close);
    bloc.add(const AlertStreamFailed(OfflineError()));
    await tester.pump();
    expect(find.text('目前離線，顯示快取資料。'), findsOneWidget);
  });
}
