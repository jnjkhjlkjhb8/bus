import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/repositories/bus_repository.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_bloc.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_event.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_state.dart';

void main() {
  test('loads members and arrivals from repository', () async {
    final repository = _FakeBusRepository(
      membersResult: const [
        BusStationMember(
          stationUid: 'stop-1',
          stationId: 'sid-1',
          stationName: '台北車站',
          lat: 25,
          lon: 121,
        ),
      ],
      arrivalsResult: const [
        BusStopArrival(
          stationId: 'stop-1',
          subRouteUid: 'sub-307',
          routeName: '307',
          destination: '板橋',
          estimateSeconds: 180,
        ),
      ],
    );
    final bloc = BusStopBloc(stopId: 'group-1', repository: repository);
    addTearDown(bloc.close);

    await expectLater(
      bloc.stream,
      emitsThrough(
        isA<BusStopState>()
            .having((s) => s.status, 'status', BusStopStatus.loaded)
            .having((s) => s.members, 'members', hasLength(1))
            .having((s) => s.arrivals, 'arrivals', hasLength(1)),
      ),
    );
  });

  test('BusStopFailed sets AppError', () async {
    final bloc = BusStopBloc(
      stopId: 'group-1',
      repository: _FakeBusRepository(),
    );
    addTearDown(bloc.close);

    final next = expectLater(
      bloc.stream,
      emitsThrough(
        isA<BusStopState>()
            .having((s) => s.status, 'status', BusStopStatus.error)
            .having((s) => s.error, 'error', isA<OfflineError>()),
      ),
    );

    bloc.add(const BusStopFailed(OfflineError()));
    await next;
  });

  test('retry requests a fresh load', () async {
    final repository = _FakeBusRepository();
    final bloc = BusStopBloc(stopId: 'group-1', repository: repository);
    addTearDown(bloc.close);

    await Future<void>.delayed(Duration.zero);
    bloc.add(const BusStopRetryRequested());
    await Future<void>.delayed(Duration.zero);

    expect(repository.groupCalls, greaterThanOrEqualTo(2));
  });
}

class _FakeBusRepository implements BusRepository {
  _FakeBusRepository({
    this.membersResult = const [],
    this.arrivalsResult = const [],
  });

  final List<BusStationMember> membersResult;
  final List<BusStopArrival> arrivalsResult;
  int groupCalls = 0;

  @override
  Future<List<BusStationMember>> stationGroup(String groupUid) async {
    groupCalls++;
    return membersResult;
  }

  @override
  Stream<List<BusStopArrival>> stationEta(String city, String groupUid) async* {
    yield arrivalsResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}
