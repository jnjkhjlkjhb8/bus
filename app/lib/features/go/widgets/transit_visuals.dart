import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/data/models/plan_models.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';

// A section is a walk when TDX types it as anything other than transit
// (pedestrian legs). Keying off `type` — not `transport.mode` — because TDX
// still attaches a transport block to pedestrian sections, so a mode check
// misclassifies them as transit. Mirrors journey_models' `type != 'transit'`.
bool isWalk(PlanSection s) => s.type.toLowerCase() != 'transit';

// Walk sections carry a (non-walk) transport mode, so branch on isWalk before
// falling back to the transport mode for the glyph.
IconData sectionIcon(PlanSection s) =>
    isWalk(s) ? Icons.directions_walk_rounded : transitIcon(s.transport.mode);

// TDX MaaS reports modes in its own vocabulary (BUS/HighwayBus/MRT/SUBWAY/
// TRA/THSR) and the router forwards them verbatim, so every branch has to
// accept those spellings alongside the generic ones. Kept in step with the Go
// side's isBusMode/isMetroMode/isRailMode/isThsrMode.
IconData transitIcon(String mode) => switch (mode.toLowerCase()) {
  'walk' || 'pedestrian' => Icons.directions_walk_rounded,
  'subway' || 'metro' || 'mrt' || 'tram' => Icons.directions_subway_rounded,
  'bus' || 'highwaybus' => Icons.directions_bus_rounded,
  'rail' || 'tra' || 'train' || 'thsr' || 'hsr' => Icons.train_rounded,
  _ => Icons.directions_transit_rounded,
};

Color transitColor(PlanTransport t, ColorScheme cs) {
  final raw = t.routeColor.trim().replaceAll('#', '');
  if (raw.isNotEmpty) {
    final padded = raw.length == 6 ? 'FF$raw' : raw;
    final value = int.tryParse(padded, radix: 16);
    if (value != null) return Color(value);
  }
  // Same mode vocabulary as transitIcon; THSR is matched before the rail
  // aliases so it keeps its own color instead of the TRA fallback.
  return switch (t.mode.toLowerCase()) {
    'walk' || 'pedestrian' => cs.onSurfaceVariant,
    'subway' || 'metro' || 'mrt' || 'tram' => AppTheme.mrtBL,
    'thsr' || 'hsr' => AppTheme.trainThsr,
    'rail' || 'tra' || 'train' =>
      t.category.toUpperCase() == 'HSR'
          ? AppTheme.trainThsr
          : AppTheme.trainRangecar,
    _ => cs.onSurface,
  };
}

/// [line] adjusted until a 14px glyph of it is legible on [background].
///
/// A line colour used to survive on its own area — a chip filled edge to edge
/// with 環狀線 yellow reads as yellow whatever sits behind it. A 1.7px stroke
/// does not: the same yellow on `surface-press` lands at 1.3:1, well under the
/// 3:1 WCAG asks of a non-text graphic, and the glyph simply disappears. So the
/// colour is walked toward the far end of the ramp — darker on a light surface,
/// lighter on a dark one — until it clears the bar.
///
/// The hue is kept; only lightness moves, so 環狀線 stays recognisably yellow
/// and 文湖線 recognisably orange. A line that already clears 3:1 is returned
/// untouched, which is most of them, so the map and the card agree on almost
/// every line and diverge only where the alternative is an invisible icon.
Color legibleLineColor(Color line, Color background) {
  const minimumContrast = 3.0;
  if (_contrast(line, background) >= minimumContrast) return line;
  final hsl = HSLColor.fromColor(line);
  final darken = background.computeLuminance() > 0.5;
  // 2% lightness steps: fine enough that the shift is not a different colour,
  // coarse enough to settle in a couple of dozen iterations at worst.
  for (var step = 1; step <= 50; step++) {
    final shift = step * 0.02;
    final lightness = (darken ? hsl.lightness - shift : hsl.lightness + shift)
        .clamp(0.0, 1.0);
    final candidate = hsl.withLightness(lightness).toColor();
    if (_contrast(candidate, background) >= minimumContrast) return candidate;
  }
  // Black or white is the last resort, and it always clears the bar.
  return darken ? Colors.black : Colors.white;
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

String sectionLabel(AppI18n i18n, PlanSection s) {
  final t = s.transport;
  if (isWalk(s)) return i18n.goWalk;
  final name = t.shortName.isNotEmpty ? t.shortName : t.name;
  return name;
}

String minutesLabel(AppI18n i18n, int minutes) => i18n.minutesValue(minutes);

int sectionMinutes(PlanSection s) {
  final secs = s.travelSummary.duration;
  return (secs / 60).round().clamp(0, 999);
}
