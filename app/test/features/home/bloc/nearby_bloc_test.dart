import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/repositories/near_repository.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_bloc.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_event.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_state.dart';

NearStationViewModel _vm(String id, int distance) => NearStationViewModel(
  type: NearStationType.bus,
  stationId: id,
  stationName: id,
  lat: 25,
  lon: 121.5,
  walkingMinutes: 1,
  distanceMeters: distance,
);

void main() {
  test('loads and sorts stations by distance', () async {
    final repository = _FakeNearRepository([
      _vm('far', 900),
      _vm('near', 100),
      _vm('mid', 400),
    ]);
    final bloc = NearbyBloc(repository: repository);
    addTearDown(bloc.close);

    bloc.add(const NearbyRequested(radius: 800, lat: 25, lon: 121.5));

    await expectLater(
      bloc.stream,
      emitsThrough(
        isA<NearbyState>()
            .having((s) => s.loading, 'loading', isFalse)
            .having((s) => s.error, 'error', isNull)
            .having(
              (s) => s.stations.map((e) => e.stationId).toList(),
              'stations',
              ['near', 'mid', 'far'],
            ),
      ),
    );
  });

  test('surfaces repository errors as AppError', () async {
    final bloc = NearbyBloc(repository: _FakeNearRepository.throwing());
    addTearDown(bloc.close);

    bloc.add(const NearbyRequested(radius: 800, lat: 25, lon: 121.5));

    await expectLater(
      bloc.stream,
      emitsThrough(
        isA<NearbyState>()
            .having((s) => s.loading, 'loading', isFalse)
            .having((s) => s.error, 'error', isNotNull),
      ),
    );
  });

  test(
    'an older in-flight request completing after a newer one does not '
    'overwrite the newer result',
    () async {
      final firstCompleter = Completer<List<NearStationViewModel>>();
      final secondCompleter = Completer<List<NearStationViewModel>>();
      final repository = _ControlledNearRepository({
        800: firstCompleter,
        900: secondCompleter,
      });
      final bloc = NearbyBloc(repository: repository);
      addTearDown(bloc.close);

      bloc
        ..add(const NearbyRequested(radius: 800, lat: 25, lon: 121.5))
        ..add(const NearbyRequested(radius: 900, lat: 25.1, lon: 121.6));

      // Request 2 (radius 900) completes first...
      secondCompleter.complete([_vm('second', 200)]);
      await pumpEventQueue();
      // ...then the stale request 1 (radius 800) completes after it.
      firstCompleter.complete([_vm('first', 100)]);
      await pumpEventQueue();

      expect(
        bloc.state.stations.map((e) => e.stationId).toList(),
        ['second'],
      );
    },
  );

  test(
    'a stale failure arriving after a newer success does not overwrite it',
    () async {
      final firstCompleter = Completer<List<NearStationViewModel>>();
      final secondCompleter = Completer<List<NearStationViewModel>>();
      final repository = _ControlledNearRepository({
        800: firstCompleter,
        900: secondCompleter,
      });
      final bloc = NearbyBloc(repository: repository);
      addTearDown(bloc.close);

      bloc
        ..add(const NearbyRequested(radius: 800, lat: 25, lon: 121.5))
        ..add(const NearbyRequested(radius: 900, lat: 25.1, lon: 121.6));

      secondCompleter.complete([_vm('second', 200)]);
      await pumpEventQueue();
      firstCompleter.completeError(Exception('stale failure'));
      await pumpEventQueue();

      expect(bloc.state.error, isNull);
      expect(
        bloc.state.stations.map((e) => e.stationId).toList(),
        ['second'],
      );
    },
  );

  test(
    'retry re-queries the last attempted (dragged) viewport, not device GPS',
    () async {
      final repository = _FakeNearRepository.throwing();
      final bloc = NearbyBloc(repository: repository);
      addTearDown(bloc.close);

      bloc.add(
        const NearbyRequested(radius: 500, lat: 25.2, lon: 121.7),
      );
      await bloc.stream.firstWhere((s) => s.error != null);

      repository
        ..shouldThrow = false
        ..result = [_vm('retried', 50)];
      bloc.add(const NearbyRetried());

      final loaded = await bloc.stream.firstWhere(
        (s) => !s.loading && s.error == null && s.stations.isNotEmpty,
      );

      expect(repository.lastQuery, (25.2, 121.7, 500));
      expect(loaded.stations.single.stationId, 'retried');
    },
  );

  test('retry is a no-op before any query has been attempted', () async {
    final bloc = NearbyBloc(repository: _FakeNearRepository([]));
    addTearDown(bloc.close);

    bloc.add(const NearbyRetried());
    await pumpEventQueue();

    expect(bloc.state, const NearbyState());
  });
}

class _ControlledNearRepository implements NearRepository {
  _ControlledNearRepository(this.byRadius);

  /// Completers keyed by the requested radius, so each in-flight query in a
  /// test can be resolved independently and out of order.
  final Map<int, Completer<List<NearStationViewModel>>> byRadius;

  @override
  Stream<List<NearStationViewModel>> near(Stream<NearQuery> queries) =>
      queries.asyncMap((q) => byRadius[q.radius]!.future);

  @override
  Stream<List<NearStationViewModel>> nearOnce(
    double lat,
    double lon,
    int radius,
  ) async* {
    yield await byRadius[radius]!.future;
  }
}

class _FakeNearRepository implements NearRepository {
  _FakeNearRepository(this.result) : shouldThrow = false;
  _FakeNearRepository.throwing() : result = const [], shouldThrow = true;

  List<NearStationViewModel> result;
  bool shouldThrow;
  (double, double, int)? lastQuery;

  @override
  Stream<List<NearStationViewModel>> near(Stream<NearQuery> queries) =>
      queries.asyncMap((_) {
        if (shouldThrow) throw Exception('boom');
        return result;
      });

  @override
  Stream<List<NearStationViewModel>> nearOnce(
    double lat,
    double lon,
    int radius,
  ) async* {
    lastQuery = (lat, lon, radius);
    if (shouldThrow) throw Exception('boom');
    yield result;
  }
}
