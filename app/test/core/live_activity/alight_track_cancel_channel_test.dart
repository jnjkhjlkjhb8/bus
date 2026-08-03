import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/core/live_activity/alight_track_cancel_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.wheres.bus/live_activity');

  Future<void> fireCancel() async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onCancelTrack'),
          ),
          (_) {},
        );
  }

  setUp(AlightTrackCancelChannel.reset);
  tearDown(AlightTrackCancelChannel.reset);

  test(
    "every owner hears the card's cancel, not just the last to bind",
    () async {
      // Bus/TRA/THSR sessions and metro sessions live in different blocs.
      // Bound one-at-a-time, whichever registered last would silently win
      // and 取消追蹤 would do nothing on the other network's card.
      final heard = <String>[];
      AlightTrackCancelChannel.bind(() => heard.add('journey'));
      AlightTrackCancelChannel.bind(() => heard.add('metro'));

      await fireCancel();

      expect(heard, ['journey', 'metro']);
    },
  );

  test('a listener added after a cancel still hears the next one', () async {
    final heard = <String>[];
    AlightTrackCancelChannel.bind(() => heard.add('first'));
    await fireCancel();
    AlightTrackCancelChannel.bind(() => heard.add('second'));
    await fireCancel();

    expect(heard, ['first', 'first', 'second']);
  });

  test('reset drops every binding', () async {
    final heard = <String>[];
    AlightTrackCancelChannel.bind(() => heard.add('x'));
    AlightTrackCancelChannel.reset();

    await fireCancel();

    expect(heard, isEmpty);
  });
}
