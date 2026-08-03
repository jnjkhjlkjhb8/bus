import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/shared/map/marker_factory.dart';

/// The cache behaviour `bus_route_screen.dart`'s bubble clock is built on.
///
/// That clock wakes once a second while a bubble is on screen and rebuilds it,
/// then skips the repaint when the returned bitmap is `identical` to the one
/// already published. Both halves have to hold: a freshness label that changed
/// must produce a new bitmap (or the bubble freezes), and one that didn't must
/// return the very same instance (or the map repaints every second for nothing,
/// which is what the always-on-bubble version used to do).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => MapMarkers.configure(devicePixelRatio: 3));

  Future<Object> build(String gpsText) => MapMarkers.busBubble(
    plate: 'KKA-0512',
    fill: Colors.white,
    inkSecondary: Colors.grey,
    statusLabel: '正常行駛',
    statusColor: Colors.black,
    gpsText: gpsText,
  );

  test('an unchanged clock hands back the bitmap already on screen', () async {
    expect(await build('18 秒前'), same(await build('18 秒前')));
  });

  test('a ticked clock hands back a new bitmap', () async {
    final at18 = await build('18 秒前');
    expect(await build('19 秒前'), isNot(same(at18)));
    // The label also stops spelling out seconds past a minute; that transition
    // has to invalidate too.
    expect(await build('1 分前'), isNot(same(at18)));
  });
}
