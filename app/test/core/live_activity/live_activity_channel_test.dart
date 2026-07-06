import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/core/live_activity/live_activity_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.jnjk.bus/live_activity');
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
    await la.start(content);
    await la.update(content);
    await la.stop();
    expect(calls.map((c) => c.method), ['start', 'update', 'stop']);
  });

  test('platform errors are swallowed — navigation must not crash', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'LA_START_FAILED');
        });
    final la = LiveActivityChannel();
    await la.start(content); // must not throw
    await la.stop();
  });
}
