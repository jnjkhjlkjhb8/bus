import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';
import 'package:wheres_the_car/data/repositories/tra_repository.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_bloc.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_event.dart';
import 'package:wheres_the_car/features/rail/bloc/tra_station_state.dart';

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
    // The sort lives in the feed now, so drive it through a streamed board
    // rather than adding a pre-sorted event by hand.
    final bloc = TraStationBloc(
      today: () => '2026-07-08',
      repository: _FakeTraRepository([_late, _early]),
    );
    addTearDown(bloc.close);

    bloc.add(const LoadTraStation('1000'));

    await expectLater(
      bloc.stream,
      emitsThrough(
        isA<TraStationState>()
            .having(
              (s) => s.items.map((i) => i.trainNo).toList(),
              'order',
              ['456', '123'],
            )
            .having((s) => s.loading, 'loading', isFalse)
            .having((s) => s.error, 'error', isNull),
      ),
    );
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

class _FakeTraRepository implements TraRepository {
  _FakeTraRepository(this._board);

  final List<TraLiveBoardItem> _board;

  @override
  Stream<List<TraLiveBoardItem>> liveBoard(String stationId, String date) =>
      Stream.value(_board);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}
