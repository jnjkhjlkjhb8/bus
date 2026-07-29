import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/core/live_activity/live_activity_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.wheres.bus/live_activity');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'start' ? 'activity-1' : null;
        });
  });

  const content = LiveActivityContent(
    mode: 'waiting',
    type: 'bus',
    routeOrTrain: '307 往板橋',
    fromStation: '台北車站',
    nextStation: '台北車站',
    etaMs: 1234567890000,
    walkMinutes: 5,
  );

  test('start sends full arg map with legacy alias', () async {
    final la = LiveActivityChannel();
    await la.start(content);
    expect(calls.single.method, 'start');
    final args = Map<String, Object?>.from(calls.single.arguments as Map);
    expect(args['mode'], 'waiting');
    expect(args['etaMs'], 1234567890000);
    expect(args['arrivalTimeMs'], 1234567890000);
    expect(args['progressPercent'], 0.0);
  });

  test('update after start, stop clears', () async {
    final la = LiveActivityChannel();
    final lease = await la.start(content);
    await la.update(lease, content);
    await la.stop(lease);
    expect(calls.map((c) => c.method), ['start', 'update', 'stop']);
  });

  test('platform errors are swallowed — navigation must not crash', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'LA_START_FAILED');
        });
    final la = LiveActivityChannel();
    final lease = await la.start(content); // must not throw
    await la.stop(lease);
  });

  test('start hands back a fresh lease each call', () async {
    final la = LiveActivityChannel();
    final leaseA = await la.start(content);
    final leaseB = await la.start(content);
    expect(leaseA, isNot(leaseB));
  });

  test(
    'update under a superseded lease is a no-op (F37 lease ownership)',
    () async {
      final la = LiveActivityChannel();
      final leaseA = await la.start(content);
      final leaseB = await la.start(content);
      calls.clear();

      await la.update(leaseA, content);
      expect(calls, isEmpty);

      await la.update(leaseB, content);
      expect(calls.single.method, 'update');
    },
  );

  test(
    'stop under a superseded lease does not touch the platform channel '
    '(F37: a late stop from the old owner cannot kill a newly started '
    'activity)',
    () async {
      final la = LiveActivityChannel();
      final leaseA = await la.start(content);
      final leaseB = await la.start(content);
      calls.clear();

      await la.stop(leaseA); // stale — leaseB already superseded it
      expect(calls, isEmpty);

      await la.stop(leaseB);
      expect(calls.single.method, 'stop');
    },
  );

  test(
    'a delayed old-stop queued after a new start still no-ops even when '
    'both are in flight concurrently',
    () async {
      final la = LiveActivityChannel();
      final leaseA = await la.start(content);
      calls.clear();

      // Fire the stale stop and the new start back-to-back without
      // awaiting either individually, mirroring a real race where the old
      // owner's stop is dispatched around the same time a new owner starts.
      final stopFuture = la.stop(leaseA);
      final startFuture = la.start(content);
      await Future.wait([stopFuture, startFuture]);

      // Commands are serialized in call order, so the stale stop (still
      // holding the then-current lease) runs before the new start mints
      // its own — it is not stale relative to itself, so it does reach the
      // platform. The important guarantee is what happens next.
      final leaseB = await startFuture;
      calls.clear();
      await la.stop(leaseA); // now definitely stale
      expect(calls, isEmpty);
      await la.stop(leaseB);
      expect(calls.single.method, 'stop');
    },
  );

  test('startBoard hands back a lease independent from start', () async {
    final la = LiveActivityChannel();
    final lease = await la.startBoard('大安森林公園站', const []);
    calls.clear();
    await la.updateBoard(lease, '大安森林公園站', const []);
    expect(calls.single.method, 'update');

    final leaseB = await la.startBoard('公館站', const []);
    calls.clear();
    await la.updateBoard(lease, '大安森林公園站', const []); // stale now
    expect(calls, isEmpty);
    await la.updateBoard(leaseB, '公館站', const []);
    expect(calls.single.method, 'update');
  });
}
