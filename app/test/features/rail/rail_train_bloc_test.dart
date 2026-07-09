import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/firebase_models.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';
import 'package:wheres_the_car/data/repositories/firebase_repository.dart';
import 'package:wheres_the_car/data/repositories/tra_repository.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_train_bloc.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_train_event.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_train_state.dart';

// Fare resolution hits PowerSync, which is uninitialized under `flutter test`;
// that throws and _loadFare swallows it, so fullFare is always null here. These
// tests therefore cover stops mapping and status transitions only.

void main() {
  RailTrainBloc bloc(TraRepository tra) => RailTrainBloc(
    type: '台鐵',
    trainNo: '123',
    date: '2026-07-07',
    tra: tra,
  );

  test('stops loaded -> loaded state with mapped stops', () async {
    final b = bloc(
      _FakeTraRepository(
        stopsResult: const [
          TraStopTime(
            stationName: '台北',
            arrivalTime: '',
            departureTime: '08:00',
            sequence: 1,
          ),
          TraStopTime(
            stationName: '台中',
            arrivalTime: '09:00',
            departureTime: '09:02',
            sequence: 2,
          ),
          TraStopTime(
            stationName: '高雄',
            arrivalTime: '11:00',
            departureTime: '',
            sequence: 3,
          ),
        ],
      ),
    );
    addTearDown(b.close);

    final next = expectLater(
      b.stream,
      emitsThrough(
        isA<RailTrainState>()
            .having((s) => s.status, 'status', RailTrainStatus.loaded)
            .having((s) => s.stops.length, 'stops.length', 3)
            .having((s) => s.stops.first.name, 'first', '台北')
            .having((s) => s.stops.last.name, 'last', '高雄'),
      ),
    );

    b.add(const RailTrainStarted());
    await next;
  });

  test('empty stops -> empty state', () async {
    final b = bloc(_FakeTraRepository());
    addTearDown(b.close);

    final next = expectLater(
      b.stream,
      emitsThrough(
        isA<RailTrainState>().having(
          (s) => s.status,
          'status',
          RailTrainStatus.empty,
        ),
      ),
    );

    b.add(const RailTrainStarted());
    await next;
  });

  test('NotFound -> empty state (not error)', () async {
    final b = bloc(
      _FakeTraRepository(error: const GrpcError.notFound('no train')),
    );
    addTearDown(b.close);

    final next = expectLater(
      b.stream,
      emitsThrough(
        isA<RailTrainState>().having(
          (s) => s.status,
          'status',
          RailTrainStatus.empty,
        ),
      ),
    );

    b.add(const RailTrainStarted());
    await next;
  });

  test('non-NotFound error -> error state', () async {
    final b = bloc(
      _FakeTraRepository(error: const GrpcError.unavailable('offline')),
    );
    addTearDown(b.close);

    final next = expectLater(
      b.stream,
      emitsThrough(
        isA<RailTrainState>()
            .having((s) => s.status, 'status', RailTrainStatus.error)
            .having((s) => s.error, 'error', isA<OfflineError>()),
      ),
    );

    b.add(const RailTrainStarted());
    await next;
  });

  test('loaded state has null fare when resolution unavailable', () async {
    final b = bloc(
      _FakeTraRepository(
        stopsResult: const [
          TraStopTime(
            stationName: '台北',
            arrivalTime: '',
            departureTime: '08:00',
            sequence: 1,
          ),
          TraStopTime(
            stationName: '高雄',
            arrivalTime: '11:00',
            departureTime: '',
            sequence: 2,
          ),
        ],
      ),
    );
    addTearDown(b.close);

    final next = expectLater(
      b.stream,
      emitsThrough(
        isA<RailTrainState>()
            .having((s) => s.status, 'status', RailTrainStatus.loaded)
            .having((s) => s.fullFare, 'fullFare', isNull),
      ),
    );

    b.add(const RailTrainStarted());
    await next;
  });

  test('toggling a reminder arms then cancels it', () async {
    final fb = _FakeFirebase();
    final b = RailTrainBloc(
      type: '台鐵',
      trainNo: '123',
      date: '2099-01-01', // far future so the stop's arrival is armable
      tra: _FakeTraRepository(stopsResult: _threeStops),
      firebase: fb,
    );
    addTearDown(b.close);

    b.add(const RailTrainStarted());
    await b.stream.firstWhere((s) => s.status == RailTrainStatus.loaded);

    final armed = expectLater(
      b.stream,
      emitsThrough(
        isA<RailTrainState>().having(
          (s) => s.reminders['台中'],
          'reminder',
          'rid-台中',
        ),
      ),
    );
    b.add(const RailTrainReminderToggled('台中'));
    await armed;
    expect(fb.created, ['台中']);

    final cleared = expectLater(
      b.stream,
      emitsThrough(
        isA<RailTrainState>().having(
          (s) => s.reminders.containsKey('台中'),
          'reminder gone',
          false,
        ),
      ),
    );
    b.add(const RailTrainReminderToggled('台中'));
    await cleared;
    expect(fb.cancelled, ['rid-台中']);
  });

  test('reminder for an already-departed stop is a no-op', () async {
    final fb = _FakeFirebase();
    final b = RailTrainBloc(
      type: '台鐵',
      trainNo: '123',
      date: '2000-01-01', // in the past — nothing to arm
      tra: _FakeTraRepository(stopsResult: _threeStops),
      firebase: fb,
    );
    addTearDown(b.close);

    b.add(const RailTrainStarted());
    await b.stream.firstWhere((s) => s.status == RailTrainStatus.loaded);

    b.add(const RailTrainReminderToggled('台中'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(fb.created, isEmpty);
    expect(b.state.reminders, isEmpty);
  });
}

const _threeStops = [
  TraStopTime(
    stationName: '台北',
    arrivalTime: '',
    departureTime: '08:00',
    sequence: 1,
  ),
  TraStopTime(
    stationName: '台中',
    arrivalTime: '09:00',
    departureTime: '09:02',
    sequence: 2,
  ),
  TraStopTime(
    stationName: '高雄',
    arrivalTime: '11:00',
    departureTime: '',
    sequence: 3,
  ),
];

class _FakeTraRepository implements TraRepository {
  _FakeTraRepository({this.stopsResult = const [], this.error});

  final List<TraStopTime> stopsResult;
  final Exception? error;

  @override
  Future<List<TraStopTime>> stops(String date, String trainNo) async {
    if (error != null) throw error!;
    return stopsResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakeFirebase implements FirebaseRepository {
  final List<String> created = [];
  final List<String> cancelled = [];

  @override
  Future<ArrivalReminderReceipt> createArrivalReminder({
    required String routeType,
    required String routeKey,
    required String stopKey,
    required String direction,
    required int leadMinutes,
    required DateTime expiresAt,
  }) async {
    created.add(stopKey);
    return ArrivalReminderReceipt(reminderId: 'rid-$stopKey');
  }

  @override
  Future<FirebaseAck> cancelArrivalReminder(String reminderId) async {
    cancelled.add(reminderId);
    return const FirebaseAck(ok: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}
