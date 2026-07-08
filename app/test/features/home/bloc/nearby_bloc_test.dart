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
}

class _FakeNearRepository implements NearRepository {
  _FakeNearRepository(this.result) : shouldThrow = false;
  _FakeNearRepository.throwing() : result = const [], shouldThrow = true;

  final List<NearStationViewModel> result;
  final bool shouldThrow;

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
    if (shouldThrow) throw Exception('boom');
    yield result;
  }
}
