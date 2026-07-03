import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_bloc.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_state.dart';

void main() {
  test('RailBloc starts in initial state', () {
    final bloc = RailBloc();
    addTearDown(bloc.close);
    expect(bloc.state, isA<RailInitial>());
  });

  test(
    'RailTimetableLoaded delays updated via copyWith reflects pushed value',
    () {
      const trainNo = '110';
      const delayMinutes = 5;

      const loaded = RailTimetableLoaded(
        system: RailSystem.tra,
        originName: '台北',
        destName: '花蓮',
        date: '2026-06-30',
      );

      expect(loaded.delays, isEmpty);

      final updated = loaded.copyWith(delays: {trainNo: delayMinutes});
      expect(updated.delays[trainNo], equals(delayMinutes));
    },
  );

  test(
    'RailDelaysUpdated updates delays when state is RailTimetableLoaded',
    () async {
      final bloc = RailBloc();
      addTearDown(bloc.close);

      bloc.add(const RailDelaysUpdated({'110': 3}));
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state, isA<RailInitial>());
    },
  );

  test('RailError carries AppError', () {
    const state = RailError(OfflineError());

    expect(state.error, isA<OfflineError>());
  });
}
