import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/live_activity/live_activity_channel.dart';

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

  const rows = [
    StopBoardRow(
      routeNumber: '672',
      destination: '往科技大樓',
      etaLabel: '3分',
    ),
  ];

  test('startBoard sends board mode payload with routes', () async {
    final la = LiveActivityChannel();
    await la.startBoard('大安森林公園站', rows);

    expect(calls.single.method, 'start');
    final args = Map<String, Object?>.from(calls.single.arguments as Map);
    expect(args['mode'], 'board');
    expect(args['stopName'], '大安森林公園站');

    final routesArg = args['routes']! as List<Object?>;
    final row = Map<String, Object?>.from(routesArg[0]! as Map);
    expect(row['route'], '672');
    expect(row['destination'], '往科技大樓');
    expect(row['eta'], '3分');
  });

  test('updateBoard after startBoard, stop clears', () async {
    final la = LiveActivityChannel();
    await la.startBoard('大安森林公園站', rows);
    await la.updateBoard('大安森林公園站', rows);
    await la.stop();
    expect(calls.map((c) => c.method), ['start', 'update', 'stop']);
  });

  test('updateBoard without prior start is a no-op', () async {
    final la = LiveActivityChannel();
    await la.updateBoard('大安森林公園站', rows); // must not throw, no call sent
    expect(calls, isEmpty);
  });

  test('platform errors on startBoard are swallowed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'LA_START_FAILED');
        });
    final la = LiveActivityChannel();
    await la.startBoard('大安森林公園站', rows); // must not throw
    await la.stop();
  });
}
