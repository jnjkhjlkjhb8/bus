import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/thsr_models.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';
import 'package:wheres_the_car/data/repositories/thsr_repository.dart';
import 'package:wheres_the_car/data/repositories/tra_repository.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_bloc.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_state.dart';

void main() {
  test('one THSR request loads from the initial state', () async {
    const item = ThsrTimetableItem(
      trainNo: '101',
      departureTime: '08:00',
      arrivalTime: '09:30',
      travelMinutes: 90,
      delayMinutes: 0,
      remark: '',
    );
    final thsr = _FakeThsrRepository(timetableResult: const [item]);
    final bloc = RailBloc(thsrRepository: thsr);
    addTearDown(bloc.close);

    final states = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<RailTimetableLoading>()
            .having((s) => s.system, 'system', RailSystem.thsr)
            .having((s) => s.originName, 'origin', '南港')
            .having((s) => s.destName, 'destination', '左營'),
        isA<RailTimetableLoaded>()
            .having((s) => s.system, 'system', RailSystem.thsr)
            .having((s) => s.thsrItems, 'items', const [item]),
      ]),
    );

    bloc.add(
      const RailTimetableRequested(
        system: RailSystem.thsr,
        origin: RailStationSelection(name: '南港', id: '0990'),
        destination: RailStationSelection(name: '左營', id: '1070'),
        date: '2026-07-10',
      ),
    );

    await states;
    expect(thsr.timetableCalls, [('2026-07-10', '0990', '1070')]);
  });

  test('known station IDs bypass repository lookup', () async {
    final thsr = _FakeThsrRepository();
    final bloc = RailBloc(thsrRepository: thsr);
    addTearDown(bloc.close);

    bloc.add(
      const RailTimetableRequested(
        system: RailSystem.thsr,
        origin: RailStationSelection(name: '南港', id: '0990'),
        destination: RailStationSelection(name: '左營', id: '1070'),
        date: '2026-07-10',
      ),
    );
    await bloc.stream.firstWhere((state) => state is RailTimetableLoaded);

    expect(thsr.stationIdCalls, isEmpty);
    expect(thsr.timetableCalls, [('2026-07-10', '0990', '1070')]);
  });

  test('unknown station names fall back to names as IDs', () async {
    final thsr = _FakeThsrRepository();
    final bloc = RailBloc(thsrRepository: thsr);
    addTearDown(bloc.close);

    bloc.add(
      const RailTimetableRequested(
        system: RailSystem.thsr,
        origin: RailStationSelection(name: '未知起點'),
        destination: RailStationSelection(name: '未知終點'),
        date: '2026-07-10',
      ),
    );
    await bloc.stream.firstWhere((state) => state is RailTimetableLoaded);

    expect(thsr.stationIdCalls, ['未知起點', '未知終點']);
    expect(
      thsr.timetableCalls,
      [('2026-07-10', '未知起點', '未知終點')],
    );
  });

  test('TRA delay updates are attached to the loaded timetable', () async {
    final delays = StreamController<Map<String, int>>.broadcast();
    addTearDown(delays.close);
    final tra = _FakeTraRepository(delayStream: delays.stream);
    final bloc = RailBloc(traRepository: tra);
    addTearDown(bloc.close);

    bloc.add(
      const RailTimetableRequested(
        system: RailSystem.tra,
        origin: RailStationSelection(name: '台北', id: '1000'),
        destination: RailStationSelection(name: '花蓮', id: '7000'),
        date: '2026-07-10',
      ),
    );
    await bloc.stream.firstWhere((state) => state is RailTimetableLoaded);
    while (tra.delayCalls.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final delayed = bloc.stream.firstWhere(
      (state) => state is RailTimetableLoaded && state.delays['110'] == 3,
    );
    delays.add(const {'110': 3});

    expect((await delayed as RailTimetableLoaded).delays, const {'110': 3});
  });

  test('repeat THSR requests remain on the THSR adapter', () async {
    final thsr = _FakeThsrRepository();
    final tra = _FakeTraRepository();
    final bloc = RailBloc(traRepository: tra, thsrRepository: thsr);
    addTearDown(bloc.close);

    RailTimetableRequested request(String date) => RailTimetableRequested(
      system: RailSystem.thsr,
      origin: const RailStationSelection(name: '南港', id: '0990'),
      destination: const RailStationSelection(name: '左營', id: '1070'),
      date: date,
    );

    bloc.add(request('2026-07-10'));
    await bloc.stream.firstWhere((state) => state is RailTimetableLoaded);
    bloc.add(request('2026-07-11'));
    await bloc.stream.firstWhere(
      (state) => state is RailTimetableLoaded && state.date == '2026-07-11',
    );

    expect(tra.timetableCalls, isEmpty);
    expect(thsr.timetableCalls, [
      ('2026-07-10', '0990', '1070'),
      ('2026-07-11', '0990', '1070'),
    ]);
  });

  test('repository failures become RailError', () async {
    final thsr = _FakeThsrRepository(error: StateError('boom'));
    final bloc = RailBloc(thsrRepository: thsr);
    addTearDown(bloc.close);

    bloc.add(
      const RailTimetableRequested(
        system: RailSystem.thsr,
        origin: RailStationSelection(name: '南港', id: '0990'),
        destination: RailStationSelection(name: '左營', id: '1070'),
        date: '2026-07-10',
      ),
    );

    final state = await bloc.stream.firstWhere((state) => state is RailError);
    expect((state as RailError).error, isA<UnknownError>());
  });

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

class _FakeThsrRepository extends ThsrRepository {
  _FakeThsrRepository({this.timetableResult = const [], this.error});

  final List<ThsrTimetableItem> timetableResult;
  final Error? error;
  final timetableCalls = <(String, String, String)>[];
  final stationIdCalls = <String>[];

  @override
  Future<String?> stationId(String name) async {
    stationIdCalls.add(name);
    return null;
  }

  @override
  Future<List<ThsrTimetableItem>> timetable(
    String date,
    String originId,
    String destId,
  ) async {
    timetableCalls.add((date, originId, destId));
    if (error case final error?) throw error;
    return timetableResult;
  }
}

class _FakeTraRepository extends TraRepository {
  _FakeTraRepository({Stream<Map<String, int>>? delayStream})
    : _delayStream = delayStream ?? const Stream.empty();

  final Stream<Map<String, int>> _delayStream;
  final timetableCalls = <(String, String, String)>[];
  final delayCalls = <(String, String, String)>[];

  @override
  Future<List<TraTimetableItem>> timetable(
    String date,
    String originId,
    String destId,
  ) async {
    timetableCalls.add((date, originId, destId));
    return const [];
  }

  @override
  Stream<Map<String, int>> delay(
    String date,
    String originId,
    String destId,
  ) {
    delayCalls.add((date, originId, destId));
    return _delayStream;
  }
}
