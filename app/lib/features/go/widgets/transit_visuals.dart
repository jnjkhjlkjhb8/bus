import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';

// TDX emits an empty mode (not "walk") for pedestrian sections, and the router
// only populates Transport when mode is non-empty — so an unset/empty mode is a
// walk. Must match services/router/maas.go isWalkMode.
bool isWalk(PlanSection s) {
  final mode = s.transport.mode.toLowerCase();
  return mode.isEmpty || mode == 'walk';
}

IconData transitIcon(String mode) => switch (mode.toLowerCase()) {
  'walk' => Icons.directions_walk_rounded,
  'subway' || 'tram' => Icons.directions_subway_rounded,
  'bus' => Icons.directions_bus_rounded,
  'rail' => Icons.train_rounded,
  _ => Icons.directions_transit_rounded,
};

Color transitColor(PlanTransport t, ColorScheme cs) {
  final raw = t.routeColor.trim().replaceAll('#', '');
  if (raw.isNotEmpty) {
    final padded = raw.length == 6 ? 'FF$raw' : raw;
    final value = int.tryParse(padded, radix: 16);
    if (value != null) return Color(value);
  }
  switch (t.mode.toLowerCase()) {
    case 'walk':
      return cs.onSurfaceVariant;
    case 'subway':
    case 'tram':
      return AppTheme.mrtBL;
    case 'rail':
      return t.category.toUpperCase() == 'HSR'
          ? AppTheme.trainThsr
          : AppTheme.trainRangecar;
    case 'bus':
    default:
      return cs.onSurface;
  }
}

String sectionLabel(PlanSection s) {
  final t = s.transport;
  if (isWalk(s)) return '步行';
  final name = t.shortName.isNotEmpty ? t.shortName : t.name;
  return switch (t.mode.toLowerCase()) {
    'bus' => '$name 路',
    _ => name,
  };
}

String minutesLabel(int minutes) => '$minutes 分';

int sectionMinutes(PlanSection s) {
  final secs = s.travelSummary.duration;
  return (secs / 60).round().clamp(0, 999);
}
