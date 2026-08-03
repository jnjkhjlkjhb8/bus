import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/data/models/bus_models.dart';
import 'package:wheres_the_bus/data/models/eta_format.dart';
import 'package:wheres_the_bus/data/models/timeline_stop.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_route_state.dart';
import 'package:wheres_the_bus/features/bus/bus_vehicle_status.dart';
import 'package:wheres_the_bus/features/bus/widgets/bus_timeline_stops.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/map/bus_heading.dart';
import 'package:wheres_the_bus/shared/map/marker_factory.dart';
import 'package:wheres_the_bus/shared/map/wkt.dart';

/// The bus route screen's map layer, as one module.
///
/// This is a projection: route + direction + live ETAs + vehicle positions,
/// plus the rider's own selection state, become a set of markers and
/// polylines. It used to be a 203-line method on the screen's `State`, which
/// meant none of it could be reached from a test without mounting a
/// `GoogleMap`.
///
/// Two calls make up the interface. [resolve] is the expensive one: it runs on
/// every live frame, rasterises what changed, and returns null when there is
/// nothing new to show. [paint] is the cheap one: it runs on every animation
/// tick and is a pure function of what [resolve] last stored.
///
/// The module owns three caches so callers never have to reason about them: a
/// per-marker bitmap cache keyed on rendered inputs, the parsed route geometry,
/// and the in-flight glides. It also owns the supersede rule — a [resolve] that
/// is overtaken while awaiting bitmaps yields to the newer one instead of
/// committing a stale frame over it.
///
/// Markers stay bitmaps on purpose. Flutter widgets positioned over a
/// `GoogleMap` shake while the map pans, so everything pinned to a coordinate
/// here is rasterised through [MapMarkers].
class BusRouteOverlay {
  BusRouteOverlay({required this.onStopTap, required this.onVehicleTap});

  /// Tapping a stop plate; the screen scrolls its timeline to that stop.
  final void Function(String stopUid) onStopTap;

  /// Tapping a bus mark; the screen pins or unpins that plate.
  final void Function(String plate) onVehicleTap;

  final _markerCache = <String, ({String key, Marker marker})>{};
  final _glides = <String, BusGlide>{};

  String _frameSig = '';
  String? _geometrySig;
  List<List<LatLng>> _geometryLines = const [];
  Set<Marker> _stopMarkers = const {};
  Set<Polyline> _polylines = const {};
  List<LatLng> _stopPoints = const [];

  /// Bumped by every [resolve]; a call whose value no longer matches by the
  /// time it reaches the commit point was overtaken while awaiting bitmaps.
  int _generation = 0;

  /// The stop coordinates of the frame on screen, for the camera fit.
  List<LatLng> get stopPoints => _stopPoints;

  /// The in-flight glides, exposed so a test can assert continuity across
  /// frames; [paint] is the only production reader.
  @visibleForTesting
  Map<String, BusGlide> get glides => Map.unmodifiable(_glides);

  /// Installs glides directly so [paint] can be exercised without rasterising a
  /// frame first. [resolve] is the only production writer.
  @visibleForTesting
  void debugSeedGlides(Map<String, BusGlide> glides) {
    _glides
      ..clear()
      ..addAll(glides);
  }

  /// Drops every cached bitmap and forces the next [resolve] to rebuild.
  ///
  /// The screen calls this on a light/dark flip or a Dynamic Type change: those
  /// alter every rendered marker without changing any of the data the frame
  /// signature is built from, so without it the map would keep showing plates
  /// rasterised for the previous theme.
  void invalidate() {
    _markerCache.clear();
    _frameSig = '';
  }

  /// Resolves one frame, or null when there is nothing to commit.
  ///
  /// Null means one of: the route has no stops yet, the inputs are unchanged
  /// since the last frame, or a newer resolve overtook this one. All three are
  /// "leave the map alone", which is why they share a return value.
  ///
  /// [glideProgress] is where the current glide sits (0..1). Every new glide
  /// starts from where its mark is *right now*, mid-glide included, so a frame
  /// landing during a turn retargets smoothly instead of snapping back.
  Future<BusOverlayFrame?> resolve({
    required BusRouteState state,
    required AppI18n i18n,
    required ColorScheme colors,
    required double glideProgress,
    required DateTime now,
    String? selectedStopUid,
    String? pinnedPlate,
    String? trackedPlate,
    bool pickingStop = false,
  }) async {
    final route = state.route;
    if (route == null) return null;
    final stops = state.direction == 0 ? route.stopsGo : route.stopsReturn;
    if (stops.isEmpty) return null;

    final generation = ++_generation;
    final vehicles = vehiclePositionsFor(state);

    // The one rule for who gets a bubble, shared with the signature below so
    // the two cannot drift: a signature that omitted a shown bubble's clock
    // would freeze its freshness label at whatever it read when it appeared.
    bool showsBubble(BusVehiclePosition v) =>
        pinnedPlate == v.plate ||
        busVehicleStatus(i18n, v).tone == BusStatusTone.warning;

    final sig = frameSignature(
      state: state,
      stops: stops,
      vehicles: vehicles,
      i18n: i18n,
      showsBubble: showsBubble,
      // Both glyph inputs, or arming a 追蹤 would leave the bubble showing ＋.
      // The selected stop belongs here too: it is the only input a tap changes,
      // so leaving it out held the capsule back until the next live ETA frame
      // moved the signature on its own — up to ~30 s after the tap.
      glyphSalt: '$pinnedPlate|$trackedPlate|$pickingStop|$selectedStopUid',
    );
    if (sig == _frameSig) return null;
    _frameSig = sig;

    final stopPoints = [
      for (final st in stops)
        if (st.lat != 0 || st.lon != 0) LatLng(st.lat, st.lon),
    ];

    // Geometry only changes with the route or the direction, and parsing WKT is
    // the one genuinely expensive non-bitmap step here, so it is cached apart
    // from the frame signature that live ETAs churn every 30 s.
    final geometrySig = '${route.subRouteUid}:${state.direction}';
    if (geometrySig != _geometrySig) {
      _geometrySig = geometrySig;
      final geometry = state.direction == 0
          ? route.geometryGo
          : route.geometryReturn;
      var lines = parseWktLines(geometry);
      if (lines.isEmpty && stopPoints.length >= 2) lines = [stopPoints];
      _geometryLines = lines;
    }

    final isDark = colors.brightness == Brightness.dark;
    final isLight = !isDark;

    // colors.onSurface already flips between near-black and near-white, and
    // reads at high contrast on both basemap styles (see
    // map_color_scheme.dart), so the route line needs no token of its own —
    // only a rebuild when the theme changes, which is what invalidate() is
    // for.
    final polylines = <Polyline>{
      for (var i = 0; i < _geometryLines.length; i++)
        Polyline(
          polylineId: PolylineId('route_$i'),
          points: _geometryLines[i],
          color: colors.onSurface,
          width: 4,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
    };

    final bounds = stopPoints.isEmpty ? null : boundsOf(stopPoints);
    final stopMarkers = await _buildStopMarkers(
      stops: stops,
      etaFor: (st) => etaFor(state, st),
      cs: colors,
      i18n: i18n,
      selectedUid: selectedStopUid,
      // A selected stop's name leans away from the route's mid-longitude, so it
      // falls outside the line rather than over the next stop along.
      midLon: bounds == null
          ? 0
          : (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
      cache: _markerCache,
      onTap: onStopTap,
    );

    // A newer frame may have started and finished while this one awaited the
    // bitmap lookups above; yield rather than spend more time rasterising
    // vehicles for a frame that is about to be discarded.
    if (generation != _generation) return null;

    final nextGlides = await _resolveGlides(
      vehicles: vehicles,
      i18n: i18n,
      colors: colors,
      isLight: isLight,
      glideProgress: glideProgress,
      now: now,
      pinnedPlate: pinnedPlate,
      trackedPlate: trackedPlate,
      pickingStop: pickingStop,
      showsBubble: showsBubble,
    );

    // Same check, now guarding the commit itself: this is the write, so a stale
    // call must not reach it even if everything above finished.
    if (generation != _generation) return null;

    _stopMarkers = stopMarkers;
    _polylines = polylines;
    _stopPoints = stopPoints;
    _glides
      ..clear()
      ..addAll(nextGlides);

    return BusOverlayFrame(
      stopMarkers: stopMarkers,
      polylines: polylines,
      stopPoints: stopPoints,
      hasVehicles: nextGlides.isNotEmpty,
      showsAnyBubble: nextGlides.values.any((g) => g.rebuildBubble != null),
    );
  }

  /// Composes the layer for one animation tick: stop plates and route lines
  /// unchanged, vehicles interpolated to [glideProgress].
  ///
  /// Pure with respect to what [resolve] stored, so a test drives it directly.
  BusMapLayer paint({required double glideProgress, String? pinnedPlate}) {
    final vehicleMarkers = <Marker>{};
    _glides.forEach((plate, g) {
      final pos = lerpLatLng(g.from, g.to, glideProgress);
      // Once a bus is pinned, the others recede so the pinned one leads.
      final dimmed = pinnedPlate != null && plate != pinnedPlate;
      final alpha = dimmed ? 0.35 : 1.0;
      vehicleMarkers.add(
        Marker(
          markerId: MarkerId('bus:$plate'),
          position: pos,
          icon: g.icon,
          anchor: const Offset(0.5, 0.5),
          alpha: alpha,
          // The mark is painted north-up; rotation points it along the heading,
          // and `flat` makes that a bearing on the ground rather than a spin on
          // the screen.
          rotation: g.headingAt(glideProgress) ?? 0,
          flat: true,
          // Above every stop plate, selected capsule included: the live bus is
          // the one thing on this map that outranks the rider's own tap.
          zIndexInt: 4,
          onTap: () => onVehicleTap(plate),
        ),
      );
      final bubbleIcon = g.bubbleIcon;
      if (bubbleIcon != null) {
        vehicleMarkers.add(
          Marker(
            markerId: MarkerId('bubble:$plate'),
            position: pos,
            icon: bubbleIcon,
            alpha: alpha,
            zIndexInt: 5,
          ),
        );
      }
    });
    // Rebuilds the whole marker set per tick. The stop plates are the same
    // instances every time so the plugin's diff sees them unchanged, but the
    // union is still re-allocated and re-crossed ~48 times per glide; on a
    // 60-stop route that is the first thing to measure if a position update
    // ever hitches. Splitting the vehicle layer onto its own channel is the
    // upgrade path.
    return (
      markers: {..._stopMarkers, ...vehicleMarkers},
      polylines: _polylines,
    );
  }

  /// Repaints every on-screen bubble against a fresh clock, reporting whether
  /// any of them actually changed.
  ///
  /// Live frames land every ~30 s but the bubble carries a GPS-freshness
  /// line, which is the one number on this map whose whole job is to say how
  /// old the rest of it is. `busGpsAge` only spells out seconds between 15
  /// and 59, so outside that window the text is unchanged, [MapMarkers]
  /// hands back the very bitmap already on screen, and the identity check
  /// below skips the repaint — which is what makes a once-a-second wake-up
  /// cost a cache lookup per bubble.
  ///
  /// The values are snapshotted first because [resolve] may clear and refill
  /// the glides across the awaits here.
  Future<bool> tickBubbles(DateTime now) async {
    var changed = false;
    for (final glide in _glides.values.toList()) {
      final rebuild = glide.rebuildBubble;
      if (rebuild == null) continue;
      final icon = await rebuild(now);
      if (identical(icon, glide.bubbleIcon)) continue;
      glide.bubbleIcon = icon;
      changed = true;
    }
    return changed;
  }

  Future<Map<String, BusGlide>> _resolveGlides({
    required List<BusVehiclePosition> vehicles,
    required AppI18n i18n,
    required ColorScheme colors,
    required bool isLight,
    required double glideProgress,
    required DateTime now,
    required String? pinnedPlate,
    required String? trackedPlate,
    required bool pickingStop,
    required bool Function(BusVehiclePosition) showsBubble,
  }) async {
    final next = <String, BusGlide>{};
    for (final v in vehicles) {
      final status = busVehicleStatus(i18n, v);
      final statusColor = switch (status.tone) {
        BusStatusTone.normal => colors.onSurface,
        BusStatusTone.notice =>
          isLight ? AppTheme.etaApproaching : AppTheme.statusApproach,
        BusStatusTone.warning => colors.error,
        BusStatusTone.muted => colors.onSurfaceVariant,
      };

      final target = LatLng(v.lat, v.lon);
      final prev = _glides[v.plate];
      // A newly-seen bus starts at its target (no fly-in from nowhere);
      // otherwise it glides from wherever it sits right now.
      final from = prev == null
          ? target
          : lerpLatLng(prev.from, prev.to, glideProgress);

      final heading = headingFor(
        azimuth: v.azimuth,
        previousTo: prev?.to,
        target: target,
        previousHeading: prev?.toHeading,
      );

      // Escalate by fill before colour, the same ladder the stop markers use: a
      // warning takes the whole body, a notice or a muted state only a ring,
      // and a bus with nothing to report stays ink.
      final (Color markBody, Color? markRing) = switch (status.tone) {
        BusStatusTone.normal => (colors.onSurface, null),
        BusStatusTone.warning => (statusColor, null),
        BusStatusTone.notice || BusStatusTone.muted => (
          colors.onSurface,
          statusColor,
        ),
      };
      final icon = await MapMarkers.busMark(
        body: markBody,
        halo: isLight ? AppTheme.surfaceCardLight : AppTheme.surfaceDark,
        ring: markRing,
        showHeading: heading != null,
        // The dark basemap gives a drop shadow nothing to land on; there the
        // near-black halo is what separates the mark (see docs/design.md).
        shadow: isLight,
      );

      // Takes [at] rather than closing over `now`, so tickBubbles can call it
      // again on a later clock with nothing else about the bubble moving.
      Future<BitmapDescriptor> buildBubble(DateTime at) => MapMarkers.busBubble(
        plate: v.plate,
        fill: isLight ? Colors.white : colors.surfaceContainerHigh,
        inkSecondary: colors.onSurfaceVariant,
        statusLabel: status.label,
        statusColor: statusColor,
        gpsText: busGpsAge(i18n, v.gpsTimeUnix, at).text,
        // Three states, not two: ＋ while this bus is the one whose alight
        // stop is being chosen, ✓ once a 追蹤 is actually running for it, and
        // nothing when it is merely selected. Selecting a bus is a glance, so
        // it must not claim a reminder has been set.
        trackGlyph: switch (v.plate) {
          _ when pickingStop && pinnedPlate == v.plate => '＋',
          _ when trackedPlate == v.plate => '✓',
          _ => null,
        },
      );

      // Progressive detail: the plate and GPS freshness belong to the bus the
      // rider asked about, not to all five running the route — five always-on
      // bubbles overlap each other and the stop plates under them. A warning is
      // the exception: a broken-down bus shouldn't need a tap to say so.
      final rebuildBubble = showsBubble(v) ? buildBubble : null;

      next[v.plate] = BusGlide(
        from: from,
        to: target,
        icon: icon,
        // Where the mark points right now, so the turn continues from there.
        fromHeading: prev?.headingAt(glideProgress),
        toHeading: heading,
        bubbleIcon: await rebuildBubble?.call(now),
        rebuildBubble: rebuildBubble,
      );
    }
    return next;
  }
}

/// What one resolved frame committed. The markers and polylines are what the
/// map shows; the rest is what the screen needs to decide follow-up work
/// (fit the camera, run or stop the bubble ticker).
class BusOverlayFrame {
  const BusOverlayFrame({
    required this.stopMarkers,
    required this.polylines,
    required this.stopPoints,
    required this.hasVehicles,
    required this.showsAnyBubble,
  });

  final Set<Marker> stopMarkers;
  final Set<Polyline> polylines;
  final List<LatLng> stopPoints;
  final bool hasVehicles;

  /// Whether any vehicle is showing a bubble, and therefore whether the
  /// once-a-second freshness clock has anything to update.
  final bool showsAnyBubble;
}

/// One layer handed to the `GoogleMap`.
typedef BusMapLayer = ({Set<Marker> markers, Set<Polyline> polylines});

/// A vehicle mark between two live frames.
///
/// Live frames land every ~30 s and Google Maps markers have no position
/// tween, so without this they teleport. Each glide holds the interpolation
/// endpoints — position and heading both — plus the bitmaps, reused
/// unchanged across every tick of one glide.
class BusGlide {
  BusGlide({
    required this.from,
    required this.to,
    required this.icon,
    this.fromHeading,
    this.toHeading,
    this.bubbleIcon,
    this.rebuildBubble,
  });

  final LatLng from;
  final LatLng to;
  final BitmapDescriptor icon;

  /// Heading to glide away from, null on a vehicle's first frame — there is no
  /// previous direction to turn out of, so it starts pointed at [toHeading].
  final double? fromHeading;

  /// Heading to glide to, null when the vehicle has no usable one at all. The
  /// mark is then painted without its chevron and the rotation means nothing.
  final double? toHeading;

  /// Only the pinned bus and any vehicle in a warning state carries one.
  ///
  /// Mutable, unlike everything else here: the bubble's GPS-freshness line is a
  /// clock, so the ticker swaps this in place between live frames rather than
  /// rebuilding the glide (and the 60 stop plates a full resync would drag
  /// along) once a second.
  BitmapDescriptor? bubbleIcon;

  /// Repaints [bubbleIcon] against a fresh clock. Held instead of only the
  /// finished bitmap because everything else the bubble says — status, plate,
  /// pin glyph, theme colours — is fixed until the next live frame, so the
  /// ticker has nothing to recompute but the time.
  final Future<BitmapDescriptor> Function(DateTime now)? rebuildBubble;

  /// Heading to paint at glide progress [t]. Read live for the same reason
  /// [from] is: a frame landing mid-turn has to retarget from where the mark is
  /// actually pointing, not snap back to where that turn began.
  double? headingAt(double t) => toHeading == null
      ? null
      : lerpHeading(fromHeading ?? toHeading!, toHeading!, t);
}

LatLng lerpLatLng(LatLng a, LatLng b, double t) => LatLng(
  a.latitude + (b.latitude - a.latitude) * t,
  a.longitude + (b.longitude - a.longitude) * t,
);

/// Which way a vehicle mark points.
///
/// TDX sends azimuth 0 for "no heading" as readily as for "due north", so
/// the reported value only counts when it is non-zero. Failing that, the
/// bearing of the move between the last two reported points is the honest
/// answer, and a bus that hasn't moved keeps whatever it last had. None of
/// the three and the mark drops its chevron rather than claiming north.
double? headingFor({
  required int azimuth,
  required LatLng? previousTo,
  required LatLng target,
  required double? previousHeading,
}) {
  if (azimuth != 0) return azimuth.toDouble();
  if (previousTo == null) return previousHeading;
  return bearingIfMoved(previousTo, target) ?? previousHeading;
}

/// The ETA reading for one stop, tolerating both key shapes the feed uses.
BusStopEtaViewModel? etaFor(BusRouteState state, BusStopModel stop) =>
    state.etaMap['seq:${state.direction}:${stop.sequence}'] ??
    state.etaMap['uid:${stop.stopUid}'];

/// The live vehicles on the state's current direction, one entry per plate.
List<BusVehiclePosition> vehiclePositionsFor(BusRouteState state) {
  final byPlate = <String, BusVehiclePosition>{};
  for (final eta in state.etaMap.values) {
    if (eta.direction != state.direction) continue;
    for (final v in eta.vehicles) {
      byPlate[v.plate] = v;
    }
  }
  return byPlate.values.toList();
}

LatLngBounds boundsOf(List<LatLng> pts) {
  var minLat = pts.first.latitude;
  var maxLat = pts.first.latitude;
  var minLng = pts.first.longitude;
  var maxLng = pts.first.longitude;
  for (final p in pts) {
    minLat = p.latitude < minLat ? p.latitude : minLat;
    maxLat = p.latitude > maxLat ? p.latitude : maxLat;
    minLng = p.longitude < minLng ? p.longitude : minLng;
    maxLng = p.longitude > maxLng ? p.longitude : maxLng;
  }
  return LatLngBounds(
    southwest: LatLng(minLat, minLng),
    northeast: LatLng(maxLat, maxLng),
  );
}

/// Everything one frame renders from, as a string.
///
/// Only a vehicle actually showing a bubble contributes its GPS clock:
/// `gpsTimeUnix` advances every live frame and nothing but the bubble reads it,
/// so including it unconditionally would invalidate every marker on the map
/// twice a minute to refresh a label that is not on screen.
@visibleForTesting
String frameSignature({
  required BusRouteState state,
  required List<BusStopModel> stops,
  required List<BusVehiclePosition> vehicles,
  required AppI18n i18n,
  required bool Function(BusVehiclePosition) showsBubble,
  String glyphSalt = '',
}) {
  final route = state.route;
  return '${route?.subRouteUid}:${state.direction}:${stops.length}:$glyphSalt:'
      '${stops.map((st) => markerEta(i18n, etaFor(state, st))).join(',')}:'
      '${vehicles.map((v) => '${v.plate}@${v.lat},${v.lon},${v.azimuth},'
          '${v.dutyStatus},${v.busStatus}'
          '${showsBubble(v) ? ',${v.gpsTimeUnix}' : ''}').join(';')}';
}

/// What a stop marker's plate says. 進站中 is spelled out rather than abbreviated
/// to 即: the plate turns into a pill for this one state precisely so the word
/// fits, and an abbreviation nobody has to decode is worth the extra width.
String markerEta(AppI18n i18n, BusStopEtaViewModel? eta) {
  if (eta == null) return '–';
  final status = busStopDisplayStatus(
    estimateSeconds: eta.estimateSeconds,
    stopStatus: eta.stopStatus,
  );
  if (status == BusStopDisplayStatus.arriving) return i18n.etaArriving;
  if (eta.estimateSeconds > 0) return '${eta.estimateMinutes}';
  return '–';
}

/// A not-yet-departed stop whose arrival is a scheduled clock time — the map
/// marker shows a clock icon instead of a countdown number.
bool _markerIsScheduled(BusStopEtaViewModel? eta) =>
    eta != null && eta.stopStatus == 1 && eta.nextBusTime.isNotEmpty;

/// A stop whose service is over for the day (末班已過 / 今日未營運) — the map
/// marker shows a cross instead of a countdown, since nothing more is coming.
bool _markerIsEnded(BusStopEtaViewModel? eta) {
  if (eta == null) return false;
  final status = busStopDisplayStatus(
    estimateSeconds: eta.estimateSeconds,
    stopStatus: eta.stopStatus,
  );
  return status == BusStopDisplayStatus.lastBusPassed ||
      status == BusStopDisplayStatus.notOperating;
}

/// A stop with no reading at all — no live estimate and no scheduled time (a
/// missing ETA frame, or 交管 with nothing behind it). Tested against the raw
/// status rather than the rendered '–' so it keeps working in every locale.
bool _markerIsUnknown(BusStopEtaViewModel? eta) =>
    eta == null ||
    (eta.estimateSeconds <= 0 &&
        busStopDisplayStatus(
              estimateSeconds: eta.estimateSeconds,
              stopStatus: eta.stopStatus,
            ) !=
            BusStopDisplayStatus.arriving);

typedef MarkerStyle = ({
  Color fill,
  Color content,
  Color? ring,
  double ringWidth,
  double height,
  String? text,
  IconData? glyph,
  bool pill,
  int zIndex,
});

/// The stop marker's whole state ladder, quietest to loudest: nothing more
/// today, a scheduled departure, no reading, a countdown, 即將進站, 進站中.
///
/// The escalation runs on fill before colour — at arm's length in sunlight the
/// eye reads a light/dark mass long before it reads a hue — so the plate goes
/// hollow, then washed, then solid. Shape moves only once, on the one state
/// whose content is a word rather than a number.
///
/// 即將進站 comes from [timelineStopState], the same derivation the sheet's
/// timeline uses, so the map and the timeline cannot disagree about which stop
/// the bus is nearly at.
@visibleForTesting
MarkerStyle markerStyle(
  AppI18n i18n,
  BusStopEtaViewModel? eta,
  ColorScheme cs,
) {
  final isDark = cs.brightness == Brightness.dark;
  // Dark mode's plate can't stay white against the dark basemap, so it borrows
  // the elevated-surface pairing the app's other floating map chrome uses.
  final plate = isDark ? cs.surfaceContainerHigh : AppTheme.surfaceCardLight;
  // Recessive form shared by the three states that carry no live time. It used
  // to be a full-ink ring, which put the loudest marker on the least useful
  // fact — a stop whose last bus has gone shouted as loudly as one a minute
  // away.
  MarkerStyle quiet({String? text, IconData? glyph}) => (
    fill: plate,
    content: cs.onSurfaceVariant,
    ring: cs.onSurfaceVariant,
    ringWidth: 1.5,
    height: 30,
    text: text,
    glyph: glyph,
    pill: false,
    zIndex: 0,
  );

  if (_markerIsEnded(eta)) return quiet(glyph: Icons.close_rounded);
  if (_markerIsScheduled(eta)) return quiet(glyph: Icons.schedule_rounded);
  if (_markerIsUnknown(eta)) return quiet(text: markerEta(i18n, eta));

  final approach = isDark ? AppTheme.statusApproach : AppTheme.etaApproaching;
  return switch (timelineStopState(eta)) {
    TimelineStopState.arriving => (
      // Green, not red: an arriving bus is the moment to act, not an alarm
      // (docs/design.md). The light shade is the darker text-weight green,
      // because white sits on this fill and the badge green fails there.
      fill: isDark ? AppTheme.statusArriving : AppTheme.statusArrivingText,
      content: isDark ? AppTheme.inkLight : AppTheme.surfaceCardLight,
      ring: null,
      ringWidth: 0,
      height: 32,
      text: markerEta(i18n, eta),
      glyph: null,
      pill: true,
      zIndex: 2,
    ),
    TimelineStopState.approaching => (
      // The wash is what makes this readable without reading: colour alone is a
      // hue change, colour plus a lighter body is a change in weight.
      fill: Color.alphaBlend(
        approach.withValues(alpha: isDark ? 0.14 : 0.10),
        plate,
      ),
      content: cs.onSurface,
      ring: approach,
      ringWidth: 3,
      height: 34,
      text: markerEta(i18n, eta),
      glyph: null,
      pill: false,
      zIndex: 1,
    ),
    TimelineStopState.none => (
      fill: plate,
      content: cs.onSurface,
      // Thinner than the 3.6 it replaces: the number is the content, the ring
      // only has to lift it off the tiles.
      ring: cs.onSurface,
      ringWidth: 2,
      height: 32,
      text: markerEta(i18n, eta),
      glyph: null,
      pill: false,
      zIndex: 0,
    ),
  };
}

/// Builds the stop layer. Reuses any marker whose rendered inputs are unchanged
/// via [cache], so a live frame costs O(changed) bitmap lookups rather than one
/// per stop on a route that can run 60 stops long.
Future<Set<Marker>> _buildStopMarkers({
  required List<BusStopModel> stops,
  required BusStopEtaViewModel? Function(BusStopModel) etaFor,
  required ColorScheme cs,
  required AppI18n i18n,
  required String? selectedUid,
  required double midLon,
  required Map<String, ({String key, Marker marker})> cache,
  required void Function(String stopUid) onTap,
}) async {
  final markers = <Marker>{};
  // Thunks rather than futures so every plate starts at the Future.wait below
  // and the asynchronous toImage tails overlap. Slicing them across frames was
  // tried and measured worse on a cold frame (~215 ms against ~140 ms), because
  // it serialises exactly what the overlap was buying.
  final misses = <Future<Marker> Function()>[];
  for (final st in stops) {
    if (st.lat == 0 && st.lon == 0) continue;
    final style = markerStyle(i18n, etaFor(st), cs);
    final selected = st.stopUid == selectedUid;
    final key =
        '${cs.brightness}:${style.text}:${style.glyph?.codePoint}:'
        '${style.height}:${style.pill}:$selected:${st.lat},${st.lon}';
    final cached = cache[st.stopUid];
    if (cached != null && cached.key == key) {
      markers.add(cached.marker);
      continue;
    }
    // Rasterising is independent per stop, so the misses are started together
    // and awaited once. Serialising them meant a frame where the countdown
    // ticked over on many stops paid one full canvas round-trip after another,
    // all landing in the instant the live position update arrived.
    misses.add(
      () => _rasteriseStopMarker(
        stop: st,
        style: style,
        selected: selected,
        key: key,
        midLon: midLon,
        cs: cs,
        cache: cache,
        onTap: onTap,
      ),
    );
  }
  markers.addAll(await Future.wait([for (final start in misses) start()]));
  return markers;
}

Future<Marker> _rasteriseStopMarker({
  required BusStopModel stop,
  required MarkerStyle style,
  required bool selected,
  required String key,
  required double midLon,
  required ColorScheme cs,
  required Map<String, ({String key, Marker marker})> cache,
  required void Function(String stopUid) onTap,
}) async {
  final plate = await MapMarkers.stopMarker(
    fill: style.fill,
    content: style.content,
    ring: style.ring,
    ringWidth: style.ringWidth,
    height: style.height,
    text: style.text,
    glyph: style.glyph,
    pill: style.pill,
    label: selected ? stop.stopName : null,
    labelFill: cs.onSurface,
    labelInk: cs.surface,
    // The name leans away from the route's middle, so it falls outside the
    // line rather than over it and the next stop along.
    flip: stop.lon < midLon,
  );
  final stopUid = stop.stopUid;
  final marker = Marker(
    markerId: MarkerId(stopUid),
    position: LatLng(stop.lat, stop.lon),
    icon: plate.icon,
    anchor: plate.anchor,
    // A selected capsule is wider than its plate and has to sit over its
    // neighbours; otherwise the ladder decides who wins an overlap.
    zIndexInt: selected ? 3 : style.zIndex,
    onTap: () => onTap(stopUid),
  );
  cache[stopUid] = (key: key, marker: marker);
  return marker;
}
