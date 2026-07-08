import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/reminders/reminder_toggle.dart';

/// Drives [ReminderToggle.run] over a plain mutable map, standing in for a
/// bloc's state so the state machine is exercised without any Bloc.
class _Harness {
  _Harness({
    this.failCreate = false,
    this.failCancel = false,
    Map<String, String>? initial,
  }) : reminders = {...?initial};

  final bool failCreate;
  final bool failCancel;
  final Map<String, String> reminders;
  final List<String> created = [];
  final List<String> cancelled = [];
  final List<String> armed = [];
  final List<String> disarmed = [];
  final List<bool> toggled = [];
  final errors = <Object>[];
  bool done = false;

  ReminderToggle build() => ReminderToggle(
    createReminder: ({
      required stopKey,
      required direction,
      required expiresAt,
    }) async {
      created.add(stopKey);
      if (failCreate) throw Exception('create down');
      return 'srv-$stopKey';
    },
    cancelReminder: (id) async {
      cancelled.add(id);
      if (failCancel) throw Exception('cancel down');
    },
    persistArm: (key, id, expiresAt) async => armed.add(key),
    persistDisarm: (key) async => disarmed.add(key),
    onToggled: ({required enabled}) => toggled.add(enabled),
    reportError: (e, _) => errors.add(e),
  );

  Future<void> run(String key, {DateTime? armAt, String direction = '0'}) =>
      build().run(
        readReminders: () => reminders,
        emit: (next) {
          reminders
            ..clear()
            ..addAll(next);
        },
        isDone: () => done,
        key: key,
        direction: direction,
        armAt: armAt ?? DateTime.now().add(const Duration(hours: 2)),
      );
}

void main() {
  test('toggle on stores the server id and persists + telemetry', () async {
    final h = _Harness();

    await h.run('STOP1');

    expect(h.reminders['STOP1'], 'srv-STOP1');
    expect(h.created, ['STOP1']);
    expect(h.armed, ['STOP1']);
    expect(h.toggled, [true]);
  });

  test('toggle on failure rolls back the optimistic entry', () async {
    final h = _Harness(failCreate: true);

    await h.run('STOP1');

    expect(h.reminders.containsKey('STOP1'), isFalse);
    expect(h.errors, isNotEmpty);
    expect(h.armed, isEmpty);
    expect(h.toggled, isEmpty);
  });

  test('toggle off cancels the server reminder and persists disarm', () async {
    final h = _Harness(initial: {'STOP1': 'srv-STOP1'});

    await h.run('STOP1');

    expect(h.reminders.containsKey('STOP1'), isFalse);
    expect(h.cancelled, ['srv-STOP1']);
    expect(h.disarmed, ['STOP1']);
    expect(h.toggled, [false]);
  });

  test('toggle off failure restores the entry', () async {
    final h = _Harness(failCancel: true, initial: {'STOP1': 'srv-STOP1'});

    await h.run('STOP1');

    expect(h.reminders['STOP1'], 'srv-STOP1');
    expect(h.errors, isNotEmpty);
    expect(h.disarmed, isEmpty);
  });

  test('a pending entry guards against a mid-flight toggle', () async {
    final h = _Harness(initial: {'STOP1': 'pending'});

    await h.run('STOP1');

    // Still pending; no cancel attempted.
    expect(h.reminders['STOP1'], 'pending');
    expect(h.cancelled, isEmpty);
  });

  test('a local: id skips the server cancel on toggle off', () async {
    final h = _Harness(initial: {'STOP1': 'local:bus:R1:STOP1:3'});

    await h.run('STOP1');

    expect(h.reminders.containsKey('STOP1'), isFalse);
    expect(h.cancelled, isEmpty);
    expect(h.disarmed, ['STOP1']);
  });

  test('a null/past arm time makes toggle on a no-op', () async {
    final h = _Harness();

    await h.run('STOP1', armAt: DateTime(2000));

    expect(h.reminders, isEmpty);
    expect(h.created, isEmpty);
  });
}
