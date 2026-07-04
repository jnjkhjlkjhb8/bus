import 'dart:convert';

import 'package:wheres_the_car/data/models/bus_route_detail.dart';

Set<int> decodeBufferSequences(BusFareInfo? fare) {
  if (fare == null || fare.sectionFaresJson.isEmpty) return const {};
  try {
    final parsed = jsonDecode(utf8.decode(fare.sectionFaresJson));
    if (parsed is! List) return const {};
    final out = <int>{};
    for (final section in parsed) {
      if (section is! Map) continue;
      final zones = section['BufferZones'];
      if (zones is! List) continue;
      for (final zone in zones) {
        if (zone is Map && zone['StopSequence'] is num) {
          out.add((zone['StopSequence'] as num).toInt());
        }
      }
    }
    return out;
  } on Object catch (_) {
    return const {};
  }
}
