import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/core/live_activity/live_activity_channel.dart';

void main() {
  test('toArgs includes plate and routeNumber when provided', () {
    const content = LiveActivityContent(
      mode: 'waiting',
      type: 'bus',
      routeOrTrain: '672 往科技大樓',
      fromStation: 'A',
      nextStation: 'B',
      plate: 'KKA-1288',
      routeNumber: '672',
    );

    final args = content.toArgs();

    expect(args['plate'], 'KKA-1288');
    expect(args['routeNumber'], '672');
  });

  test('toArgs includes null plate and routeNumber when omitted', () {
    const content = LiveActivityContent(
      mode: 'waiting',
      type: 'bus',
      routeOrTrain: '672 往科技大樓',
      fromStation: 'A',
      nextStation: 'B',
    );

    final args = content.toArgs();

    expect(args.containsKey('plate'), isTrue);
    expect(args['plate'], isNull);
    expect(args.containsKey('routeNumber'), isTrue);
    expect(args['routeNumber'], isNull);
  });
}
