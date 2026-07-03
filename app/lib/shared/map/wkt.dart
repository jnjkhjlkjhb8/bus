import 'package:google_maps_flutter/google_maps_flutter.dart';

List<List<LatLng>> parseWktLines(String wkt) {
  final out = <List<LatLng>>[];
  for (final match in RegExp(r'\(([^()]*)\)').allMatches(wkt)) {
    final line = <LatLng>[];
    for (final pair in match.group(1)!.split(',')) {
      final parts = pair.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final lon = double.tryParse(parts[0]);
      final lat = double.tryParse(parts[1]);
      if (lon == null || lat == null) continue;
      line.add(LatLng(lat, lon));
    }
    if (line.length >= 2) out.add(line);
  }
  return out;
}
