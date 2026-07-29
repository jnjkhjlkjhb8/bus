/// 3D bus render sprites: 60 frames at 6° per frame.
/// `bus_00.webp` faces up (heading 0°); frame index increases clockwise.
/// 192px source — markers render at 54lp × DPR ≤ ~3.5, so nothing larger
/// ever reaches the screen.
String busSpriteAsset(double headingDegrees) {
  final frame = ((headingDegrees / 6).round() % 60 + 60) % 60;
  return 'assets/sprites/bus_${frame.toString().padLeft(2, '0')}.webp';
}
