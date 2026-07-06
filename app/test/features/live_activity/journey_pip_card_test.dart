import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';
import 'package:wheres_the_car/features/live_activity/view/journey_pip_card.dart';

// Local leg builder — a shared fixtures file across test files is not worth
// it for ~20 lines (see task-5 brief note).
JourneyLeg buildTestLeg(String routeLabel) {
  return JourneyLeg(
    kind: JourneyLegKind.bus,
    routeLabel: routeLabel,
    boardStop: '起點站',
    alightStop: '終點站',
    stopNames: const ['中間站'],
    identity: const PlanIdentity.empty(),
    leadingWalkMinutes: 3,
    scheduledDeparture: DateTime(2026, 7, 6, 10),
    scheduledArrival: DateTime(2026, 7, 6, 10, 30),
    boardLocation: const PlanPoint(lat: 25, lng: 121.5),
    stopLocations: const [
      PlanPoint(lat: 25.05, lng: 121.55),
      PlanPoint(lat: 25.1, lng: 121.6),
    ],
  );
}

void main() {
  testWidgets('waiting mode shows route and board stop', (tester) async {
    final bloc = JourneySessionBloc(etaStream: (_) => const Stream.empty())
      ..add(JourneyStarted(legs: [buildTestLeg('307 往板橋')]));
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: bloc, child: const JourneyPipCard()),
      ),
    );
    await tester.pump();
    expect(find.textContaining('307 往板橋'), findsOneWidget);
    expect(find.textContaining('起點站'), findsOneWidget);
    // Bloc.close() awaits stream teardown that never settles inside the
    // widget test's FakeAsync zone; run it on the real event loop.
    await tester.runAsync(bloc.close);
  });
}
