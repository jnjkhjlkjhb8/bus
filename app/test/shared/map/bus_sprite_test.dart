import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/shared/map/bus_sprite.dart';

// bus_sprite.dart: 60 frames at 6 degrees/frame, frame index wraps via
// `((headingDegrees / 6).round() % 60 + 60) % 60`. These tests pin the
// wrap-around behavior at the exact boundaries a naive `.round() % 60`
// (without the `+ 60` guard) would get wrong for negative or 360-degree
// headings.
void main() {
  test('heading 0 selects frame 00 (north)', () {
    expect(busSpriteAsset(0), 'assets/sprites/bus_00.png');
  });

  test('heading 360 wraps to the same frame as heading 0', () {
    expect(busSpriteAsset(360), busSpriteAsset(0));
    expect(busSpriteAsset(360), 'assets/sprites/bus_00.png');
  });

  test('heading 359.9 rounds up and wraps to frame 00, not frame 60', () {
    // (359.9 / 6) = 59.98 -> round() = 60 -> 60 % 60 = 0. A missing wrap
    // guard would index frame 60, which does not exist as an asset.
    expect(busSpriteAsset(359.9), busSpriteAsset(0));
    expect(busSpriteAsset(359.9), 'assets/sprites/bus_00.png');
  });

  test('heading 180 selects frame 30 (south)', () {
    expect(busSpriteAsset(180), 'assets/sprites/bus_30.png');
  });

  test(
    'heading 3 (exact tie between frame 0 and frame 1) rounds to frame 1',
    () {
      // 3 / 6 = 0.5 -> Dart's num.round() rounds half away from zero, so 0.5
      // rounds to 1. Pinned so a future refactor can't silently flip this.
      expect(busSpriteAsset(3), 'assets/sprites/bus_01.png');
    },
  );

  test('a small negative heading wraps into the top of the frame range', () {
    // -6 degrees is one frame counter-clockwise from north -> frame 59.
    expect(busSpriteAsset(-6), 'assets/sprites/bus_59.png');
  });
}
