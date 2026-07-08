/// 3D bus render sprites: 60 frames at 6° per frame.
/// `bus_00.png` faces up (heading 0°); frame index increases clockwise.
String busSpriteAsset(double headingDegrees) {
  final frame = ((headingDegrees / 6).round() % 60 + 60) % 60;
  return 'assets/sprites/bus_${frame.toString().padLeft(2, '0')}.png';
}
