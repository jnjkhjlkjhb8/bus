import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/data/models/plan_models.dart';
import 'package:wheres_the_bus/features/go/view/go_screen.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_bus/features/live_activity/model/journey_models.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';

const JourneyLeg _leg = JourneyLeg(
  kind: JourneyLegKind.bus,
  routeLabel: '672 往榮總',
  boardStop: '捷運石牌站',
  alightStop: '榮總',
  stopNames: ['第一站', '第二站'],
  identity: PlanIdentity.empty(),
  leadingWalkMinutes: 3,
  scheduledDeparture: null,
  scheduledArrival: null,
  boardLocation: PlanPoint(lat: 25.03, lng: 121.03),
  stopLocations: [
    PlanPoint(lat: 25.11, lng: 121.11),
    PlanPoint(lat: 25.22, lng: 121.22),
    PlanPoint(lat: 25.33, lng: 121.33),
  ],
);

Widget _harness(JourneySessionBloc bloc) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppI18n.localizationsDelegates,
  supportedLocales: AppI18n.supportedLocales,

  home: Scaffold(
    body: BlocProvider<JourneySessionBloc>.value(
      value: bloc,
      child: const JourneyControls(),
    ),
  ),
);

void main() {
  testWidgets('waiting phase shows board button + due banner', (tester) async {
    // etaStream emits Duration.zero → EtaTicked(0) → suggestBoarding == true.
    final bloc = JourneySessionBloc(
      etaStream: (_) => Stream.value(Duration.zero),
      liveActivityEnabled: () => true,
    )..add(const JourneyStarted(legs: [_leg]));

    await tester.pumpWidget(_harness(bloc));
    // Drain the stream microtask (Stream.value) that flips suggestBoarding.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(bloc.state.phase, JourneyPhase.waiting);
    expect(bloc.state.suggestBoarding, isTrue);
    expect(find.text('我上車了'), findsOneWidget);
    expect(find.text('車來了——上車了嗎？'), findsOneWidget);

    // close under runAsync — plain bloc.close() deadlocks under FakeAsync.
    await tester.runAsync(bloc.close);
  });

  testWidgets('tapping board moves to riding and shows alight', (tester) async {
    final bloc = JourneySessionBloc(
      etaStream: (_) => Stream.value(Duration.zero),
      liveActivityEnabled: () => true,
    )..add(const JourneyStarted(legs: [_leg]));

    await tester.pumpWidget(_harness(bloc));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    await tester.tap(find.text('我上車了'));
    await tester.pump();

    expect(bloc.state.phase, JourneyPhase.riding);
    expect(find.text('我下車了'), findsOneWidget);
    // 於 {alightStop} 下車  剩 {remaining} 站 — 3 stopLocations, index 0.
    expect(find.text('於 榮總 下車  剩 3 站'), findsOneWidget);
    expect(find.text('我上車了'), findsNothing);

    await tester.runAsync(bloc.close);
  });
}
