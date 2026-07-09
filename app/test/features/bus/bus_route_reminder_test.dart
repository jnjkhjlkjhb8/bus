import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/models/firebase_models.dart';
import 'package:wheres_the_car/data/repositories/firebase_repository.dart';
import 'package:wheres_the_car/data/repositories/reminders_repository.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_bloc.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_event.dart';

import '../../support/helpers/in_memory_reminders_store.dart';

class _FakeFirebaseRepository extends FirebaseRepository {
  _FakeFirebaseRepository({this.failCreate = false});
  final bool failCreate;
  final cancelled = <String>[];

  @override
  Future<ArrivalReminderReceipt> createArrivalReminder({
    required String routeType,
    required String routeKey,
    required String stopKey,
    required String direction,
    required int leadMinutes,
    required DateTime expiresAt,
  }) async {
    if (failCreate) throw Exception('grpc down');
    return const ArrivalReminderReceipt(reminderId: 'srv-1');
  }

  @override
  Future<FirebaseAck> cancelArrivalReminder(String reminderId) async {
    cancelled.add(reminderId);
    return const FirebaseAck(ok: true);
  }
}

void main() {
  test('toggle on stores server reminder id, toggle off cancels it', () async {
    final fake = _FakeFirebaseRepository();
    final reminders = RemindersRepository(store: InMemoryRemindersStore());
    final bloc = BusRouteBloc(
      subRouteUid: 'TPE1234',
      autoStart: false,
      firebaseRepository: fake,
      remindersRepository: reminders,
    );
    addTearDown(bloc.close);

    bloc.add(const BusRouteReminderToggled('STOP1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bloc.state.reminders['STOP1'], 'srv-1');
    // The armed reminder is mirrored locally so the bell survives restart.
    expect(reminders.active('TPE1234'), {'STOP1': 'srv-1'});

    bloc.add(const BusRouteReminderToggled('STOP1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bloc.state.reminders.containsKey('STOP1'), isFalse);
    expect(fake.cancelled, ['srv-1']);
    expect(reminders.active('TPE1234'), isEmpty);
  });

  test('failed create reverts the optimistic toggle', () async {
    final bloc = BusRouteBloc(
      subRouteUid: 'TPE1234',
      autoStart: false,
      firebaseRepository: _FakeFirebaseRepository(failCreate: true),
      remindersRepository: RemindersRepository(
        store: InMemoryRemindersStore(),
      ),
    );
    addTearDown(bloc.close);

    bloc.add(const BusRouteReminderToggled('STOP1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bloc.state.reminders.containsKey('STOP1'), isFalse);
  });
}
