import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/repositories/bus_stop_eta_repository.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_bloc.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_event.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_state.dart';

void main() {
  test('loads members and arrivals from repository', () async {
    final repository = _FakeBusStopEtaRepository(
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
          routeName: '307',
          destination: '板橋',
          state: BusArrivalState.scheduled,
          minutes: 3,
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
      repository: _FakeBusStopEtaRepository(),
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
    final repository = _FakeBusStopEtaRepository();
    final bloc = BusStopBloc(stopId: 'group-1', repository: repository);
    addTearDown(bloc.close);

    await Future<void>.delayed(Duration.zero);
    bloc.add(const BusStopRetryRequested());
    await Future<void>.delayed(Duration.zero);

    expect(repository.membersCalls, greaterThanOrEqualTo(2));
  });
}

class _FakeBusStopEtaRepository implements BusStopEtaRepository {
  _FakeBusStopEtaRepository({
    this.membersResult = const [],
    this.arrivalsResult = const [],
  });

  final List<BusStationMember> membersResult;
  final List<BusStopArrival> arrivalsResult;
  int membersCalls = 0;

  @override
  Future<List<BusStationMember>> members(String groupUid) async {
    membersCalls++;
    return membersResult;
  }

  @override
  Stream<List<BusStopArrival>> watchStop(String stopId, {String? city}) async* {
    yield arrivalsResult;
  }
}
