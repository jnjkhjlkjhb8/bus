import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_bloc.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_event.dart';

const _late = TraLiveBoardItem(
  trainNo: '123',
  direction: '順行',
  trainType: '自強',
  destStation: '台北',
  departureTime: '15:30',
  delayMinutes: 5,
);

const _early = TraLiveBoardItem(
  trainNo: '456',
  direction: '逆行',
  trainType: '莒光',
  destStation: '高雄',
  departureTime: '08:10',
  delayMinutes: 0,
);

void main() {
  test('board update sorts items by departure time ascending', () async {
    final bloc = TraStationBloc();
    addTearDown(bloc.close);

    bloc.add(const TraStationBoardUpdated([_late, _early]));
    final state = await bloc.stream.first;

    expect(state.items.map((i) => i.trainNo), ['456', '123']);
    expect(state.loading, isFalse);
    expect(state.error, isNull);
  });

  test('failure maps error and stops loading', () async {
    final bloc = TraStationBloc();
    addTearDown(bloc.close);

    bloc.add(const TraStationFailed('boom'));
    final state = await bloc.stream.first;

    expect(state.loading, isFalse);
    expect(state.error, isA<AppError>());
  });

  test('initial state has no items and is not loading', () {
    final bloc = TraStationBloc();
    addTearDown(bloc.close);

    expect(bloc.state.items, isEmpty);
    expect(bloc.state.loading, isFalse);
  });
}
