import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/models/journey_info.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_bloc.dart';
import 'package:wheres_the_car/features/metro/bloc/metro_event.dart';

const _info = JourneyInfo(toStationId: 'BL02', travelTimeMin: 5, fareNt: 20);

void main() {
  test('display mode change updates state', () async {
    final bloc = MetroBloc();
    addTearDown(bloc.close);

    bloc.add(const MetroDisplayModeChanged(MetroDisplayMode.fare));
    final state = await bloc.stream.first;

    expect(state.displayMode, MetroDisplayMode.fare);
  });

  test('matrix loaded stores journey matrix', () async {
    final bloc = MetroBloc();
    addTearDown(bloc.close);

    bloc.add(const MetroJourneyMatrixLoaded(matrix: {'BL02': _info}));
    final state = await bloc.stream.first;

    expect(state.journeyMatrix?['BL02']?.travelTimeMin, 5);
  });

  test('dismiss clears active station and matrix', () async {
    final bloc = MetroBloc();
    addTearDown(bloc.close);

    bloc
      ..add(const MetroJourneyMatrixLoaded(matrix: {'BL02': _info}))
      ..add(const MetroStationDismissed());
    final state = await bloc.stream.firstWhere(
      (s) => s.journeyMatrix == null,
    );

    expect(state.activeStationId, isNull);
    expect(state.journeyMatrix, isNull);
  });
}
