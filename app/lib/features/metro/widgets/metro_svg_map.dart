import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/data/models/metro_map_models.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/widgets/app_bars.dart';

final RegExp _mapDigits = RegExp(r'\d+');

/// Line colour for a station id: the prefix of the first (primary) line code.
/// Interchange ids combine codes (e.g. 'BL15_BR10'); the first wins.
Color metroLineColor(String id) {
  final code = id.split('_').first.replaceAll(_mapDigits, '');
  switch (code) {
    case 'BL':
      return AppTheme.mrtBL;
    case 'R':
      return AppTheme.mrtR;
    case 'G':
      return AppTheme.mrtG;
    case 'O':
      return AppTheme.mrtO;
    case 'BR':
      return AppTheme.mrtBR;
    case 'Y':
      return AppTheme.mrtY;
    default:
      return AppTheme.mrtBL;
  }
}

class MetroSvgMap extends StatefulWidget {
  const MetroSvgMap({
    required this.onStationTap,
    this.selectedStationId,
    this.stationLabels = const {},
    this.animate = true,
    super.key,
  });

  final ValueChanged<MetroMapStation> onStationTap;
  final String? selectedStationId;
  final Map<String, String> stationLabels;
  final bool animate;

  static const double _mapW = 1080;
  static const double _mapH = 1920;

  /// Slack allowed around the map beyond the viewport edges, so the edge
  /// stations can be dragged clear of the sheet and the top controls.
  static const double _boundaryMargin = 120;

  /// Zoom the map opens at. Below 1 so the network reads as a whole on first
  /// sight instead of filling the viewport edge to edge.
  static const double _initialScale = .8;

  /// Blank canvas above the map, so it opens clear of the floating app bar
  /// instead of starting at the viewport's top edge with the northern end of
  /// the network (淡水/北投) behind the status bar and the system pill.
  ///
  /// Part of the canvas rather than a translation in the transform: it grows
  /// the pan boundary with it, so the gap can't be dragged away and the map
  /// can't slide back under the bar. Measured in map pixels — on screen it is
  /// this times the current zoom, which is the top inset plus one bar at
  /// [_initialScale].
  static double _topGutter(BuildContext context) =>
      (MediaQuery.paddingOf(context).top + AppBarMetrics.barHeight) /
      _initialScale;

  /// Starts rasterizing the current theme's map bitmap so it is ready before
  /// the user navigates here — the one-time ~400ms rasterization otherwise
  /// lands in the middle of the push transition. Safe to call repeatedly.
  static void precache(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    unawaited(
      _RasterSvgState.ensure(
        isDark
            ? 'assets/mrt/TRTC_map_dark.svg'
            : 'assets/mrt/TRTC_map_light.svg',
        _RasterSvgState.targetWidthFor(context),
      ),
    );
  }

  @override
  State<MetroSvgMap> createState() => _MetroSvgMapState();
}

class _MetroSvgMapState extends State<MetroSvgMap> {
  /// The 120 per-station Semantics nodes (accessibility only — hit-testing
  /// itself is handled by the single map-spanning GestureDetector in
  /// [_StationHitLayer], which is always live) are built one frame after the
  /// route transition instead of during it — their one-time ~80ms build
  /// would stutter the push animation. Ordinary taps are never dropped: only
  /// screen-reader activation depends on this flag.
  bool _semanticsReady = false;
  Timer? _deferTimer;

  final _transform = TransformationController();
  bool _framed = false;

  @override
  void initState() {
    super.initState();
    _deferTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _semanticsReady = true);
    });
  }

  @override
  void dispose() {
    _deferTimer?.cancel();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final s = constraints.maxWidth / MetroSvgMap._mapW;
      final mapH = MetroSvgMap._mapH * s;

      // Scale about the horizontal centre, once: after the first frame the
      // transform belongs to the user's pan/zoom.
      if (!_framed) {
        _framed = true;
        const k = MetroSvgMap._initialScale;
        _transform.value = Matrix4.identity()
          ..translateByDouble(constraints.maxWidth * (1 - k) / 2, 0, 0, 1)
          ..scaleByDouble(k, k, k, 1);
      }
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final selectedStationId = widget.selectedStationId;

      final selectedStation = selectedStationId != null
          ? metroMapStations.firstWhere(
              (st) => st.id == selectedStationId,
              orElse: () => metroMapStations.first,
            )
          : null;

      int getDelayMs(MetroMapStation station) {
        if (selectedStation == null) return 0;
        final dx = station.x - selectedStation.x;
        final dy = station.y - selectedStation.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        return (dist * 0.25).toInt().clamp(0, 600);
      }

      // Selecting a station never moves the map: the user tapped where the
      // station already is, and at high zoom a reframe would throw away the
      // area they deliberately framed. The sheet drops to `peek` instead —
      // the panel yields, not the content (see MetroScreen._selectStation).
      return InteractiveViewer(
        transformationController: _transform,
        minScale: .45,
        maxScale: 4,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(MetroSvgMap._boundaryMargin),
        child: Padding(
          padding: EdgeInsets.only(top: MetroSvgMap._topGutter(context)),
          child: SizedBox(
            width: constraints.maxWidth,
            height: mapH,
            child: Stack(
              children: [
                Positioned.fill(
                  // Isolates the static map raster from the marker/label
                  // layers above, which animate on selection — without this,
                  // every ping/label frame repaints the whole map bitmap too.
                  child: RepaintBoundary(
                    child: _RasterSvg(
                      asset: isDark
                          ? 'assets/mrt/TRTC_map_dark.svg'
                          : 'assets/mrt/TRTC_map_light.svg',
                    ),
                  ),
                ),
                for (final station in metroMapStations)
                  if (station.id == selectedStationId)
                    _SelectedMarker(
                      key: ValueKey(selectedStationId),
                      x: station.x * s,
                      y: station.y * s,
                      scale: s,
                      color: metroLineColor(station.id),
                      animate: widget.animate,
                    ),
                _StationHitLayer(
                  stations: metroMapStations,
                  scale: s,
                  onStationTap: widget.onStationTap,
                  semanticsReady: _semanticsReady,
                ),
                for (final station in metroMapStations)
                  if (widget.stationLabels[station.id] case final label?)
                    Positioned(
                      left: station.x * s - 24,
                      top: station.y * s - 2,
                      width: 48,
                      child: IgnorePointer(
                        child: _AnimatedLabel(
                          key: ValueKey(station.id),
                          label: label,
                          delayMs: getDelayMs(station),
                          animate: widget.animate,
                          isSelected: station.id == selectedStationId,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Station tap targets, sized to the 44×44 logical-pixel HIG minimum. Dense
/// clusters (interchanges) put adjacent stations' 44px regions well within
/// overlapping distance of each other, so a single [GestureDetector] spans
/// the whole map and resolves each tap to the *nearest* station center
/// within its 22px radius instead of relying on z-order between overlapping
/// per-station regions (which would make the topmost — an arbitrary paint
/// order — always win, not the one the user actually meant to hit).
///
/// This detector is always live, from the very first frame: only the
/// per-station [Semantics] nodes below are deferred (see [semanticsReady] on
/// [MetroSvgMap]) since building 120 of them is what costs ~80ms, not the
/// single hit-test region. Screen-reader activation bypasses the nearest-hit
/// arbitration entirely: each station's [Semantics] node carries its own
/// `onTap`, invoked directly by the accessibility service through the
/// semantics tree rather than through coordinate-based hit testing, so
/// overlapping regions there are harmless.
class _StationHitLayer extends StatefulWidget {
  const _StationHitLayer({
    required this.stations,
    required this.scale,
    required this.onStationTap,
    required this.semanticsReady,
  });

  final List<MetroMapStation> stations;
  final double scale;
  final ValueChanged<MetroMapStation> onStationTap;
  final bool semanticsReady;

  /// Half of the 44×44 minimum touch target.
  static const double hitRadius = 22;

  @override
  State<_StationHitLayer> createState() => _StationHitLayerState();
}

class _StationHitLayerState extends State<_StationHitLayer> {
  MetroMapStation? _pressedStation;

  @visibleForTesting
  MetroMapStation? nearestStation(Offset local) {
    MetroMapStation? nearest;
    var nearestDist = double.infinity;
    for (final station in widget.stations) {
      final dx = station.x * widget.scale - local.dx;
      final dy = station.y * widget.scale - local.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist <= _StationHitLayer.hitRadius && dist < nearestDist) {
        nearest = station;
        nearestDist = dist;
      }
    }
    return nearest;
  }

  void _setPressed(MetroMapStation? station) {
    if (_pressedStation != station) setState(() => _pressedStation = station);
  }

  @override
  Widget build(BuildContext context) {
    const hitRadius = _StationHitLayer.hitRadius;
    final pressed = _pressedStation;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (details) =>
            _setPressed(nearestStation(details.localPosition)),
        onTapCancel: () => _setPressed(null),
        onTapUp: (details) {
          final station = nearestStation(details.localPosition);
          _setPressed(null);
          if (station != null) widget.onStationTap(station);
        },
        child: Stack(
          children: [
            if (pressed != null)
              Positioned(
                left: pressed.x * widget.scale - hitRadius,
                top: pressed.y * widget.scale - hitRadius,
                width: hitRadius * 2,
                height: hitRadius * 2,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: metroLineColor(
                        pressed.id,
                      ).withValues(alpha: 0.16),
                    ),
                  ),
                ),
              ),
            if (widget.semanticsReady)
              for (final station in widget.stations)
                Positioned(
                  left: station.x * widget.scale - hitRadius,
                  top: station.y * widget.scale - hitRadius,
                  width: hitRadius * 2,
                  height: hitRadius * 2,
                  child: Semantics(
                    button: true,
                    label: '${station.id} ${station.name}',
                    onTap: () => widget.onStationTap(station),
                    child: const SizedBox.expand(),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Draws the metro map SVG as a pre-rasterized [ui.Image] instead of a live
/// vector picture. The ~600-path SVG costs >100ms per frame to rasterize
/// under [InteractiveViewer] pan/zoom (Impeller has no picture raster cache);
/// a texture pans at full frame rate. Nothing is painted while rasterization
/// runs (painting the live SVG as a placeholder costs 300-500ms raster frames
/// mid-transition); [MetroSvgMap.precache] hides even that gap.
class _RasterSvg extends StatefulWidget {
  const _RasterSvg({required this.asset});

  final String asset;

  @override
  State<_RasterSvg> createState() => _RasterSvgState();
}

class _RasterSvgState extends State<_RasterSvg> {
  // Each entry is a GPU-resident texture, ~20-30MB (one per theme × width
  // bucket). Unbounded, this leaks a new entry every time the device's
  // effective width bucket changes (e.g. rotation, split-view, or a
  // precache() call from a screen with a different MediaQuery). Eviction
  // below keeps the cache from growing without bound while staying safe for
  // the common case — quick light/dark toggling at a stable width, which
  // this app never actually triggers mid-session, but precache() does
  // populate ahead of the live entry.
  //
  // An entry is only evicted when the newly inserted key differs from it in
  // *both* asset and width — i.e. a fully unrelated theme+size combination.
  // That deliberately spares (a) the other theme at the same width, so a
  // theme switch never re-rasterizes, and (b) the same theme at a different
  // width. The residual risk: if some in-flight widget is still displaying
  // an image whose key differs in both dimensions from the newly requested
  // one (e.g. a stale precache from a since-resized window), eviction
  // disposes a texture a live RawImage may still reference. In practice
  // _RasterSvg only ever requests targetWidthFor(context) for the theme
  // actually on screen, and old build's widgets are unmounted before a new
  // width bucket is requested, so this shouldn't be reachable in normal
  // navigation — flagging it as the one unverified edge.
  static final Map<String, Future<ui.Image>> _cache = {};

  static void _evictStale(String keepAsset, int keepWidth) {
    final staleKeys = _cache.keys.where((key) {
      final at = key.lastIndexOf('@');
      final asset = key.substring(0, at);
      final width = int.parse(key.substring(at + 1));
      return asset != keepAsset && width != keepWidth;
    }).toList();
    for (final key in staleKeys) {
      final stale = _cache.remove(key);
      if (stale != null) {
        unawaited(stale.then((image) => image.dispose()));
      }
    }
  }

  ui.Image? _image;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant _RasterSvg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) {
      _image = null;
      _load();
    }
  }

  /// 2× the on-screen physical width keeps labels sharp up to ~2× zoom;
  /// height (map is 1080×1920) stays within the common 4096px texture cap.
  static int targetWidthFor(BuildContext context) =>
      (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context) *
              2)
          .round()
          .clamp(1080, 2304);

  static Future<ui.Image> ensure(String asset, int targetW) {
    final key = '$asset@$targetW';
    final cached = _cache[key];
    if (cached != null) return cached;
    final future = _rasterize(asset, targetW);
    _cache[key] = future;
    _evictStale(asset, targetW);
    return future;
  }

  void _load() {
    final asset = widget.asset;
    unawaited(
      ensure(asset, targetWidthFor(context)).then((img) {
        if (mounted && widget.asset == asset) {
          setState(() => _image = img);
        }
      }),
    );
  }

  static Future<ui.Image> _rasterize(String asset, int targetW) async {
    final info = await vg.loadPicture(SvgAssetLoader(asset), null);
    final scale = targetW / info.size.width;
    final targetH = (info.size.height * scale).round();
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..scale(scale)
      ..drawPicture(info.picture);
    final scaled = recorder.endRecording();
    try {
      // toImageSync keeps the result GPU-resident; toImage returns a host
      // image whose ~37MB texture upload would jank the first on-screen draw.
      return scaled.toImageSync(targetW, targetH);
    } finally {
      scaled.dispose();
      info.picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => _image != null
      ? RawImage(image: _image, fit: BoxFit.fill)
      : const SizedBox.shrink();
}

class _AnimatedLabel extends StatefulWidget {
  const _AnimatedLabel({
    required this.label,
    required this.delayMs,
    required this.animate,
    required this.isSelected,
    required this.color,
    super.key,
  });

  final String label;
  final int delayMs;
  final bool animate;
  final bool isSelected;
  final Color color;

  @override
  State<_AnimatedLabel> createState() => _AnimatedLabelState();
}

class _AnimatedLabelState extends State<_AnimatedLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  Timer? _timer;
  bool _entryPlayed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AppMotion.short,
    );
    _scale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: AppMotion.easeOut),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: AppMotion.easeOut),
    );
  }

  // MediaQuery.disableAnimationsOf requires an inherited-widget lookup,
  // which is unsafe in initState (no ancestor established yet); the first
  // entry play is deferred to here instead, mirroring _SelectedMarkerState.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_entryPlayed) {
      _entryPlayed = true;
      _playEntry();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelected != widget.isSelected) {
      _playEntry();
    }
  }

  void _playEntry() {
    _timer?.cancel();
    _ctrl.value = 0;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (!widget.animate || disableAnimations) {
      _ctrl.value = 1;
      return;
    }
    _timer = Timer(Duration(milliseconds: widget.delayMs), () {
      if (mounted) {
        unawaited(_ctrl.forward());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FadeTransition(
        opacity: _opacity,
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 4,
            fontWeight: FontWeight.w800,
            color: widget.color,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Line-coloured selection marker: a soft halo fill plus a ring drawn around
/// the station glyph (never over it), tinted the station's line colour. A
/// locate-me-style ping expands out on each selection. All radii are expressed
/// in SVG map units and multiplied by [scale] so the marker tracks the glyph
/// through zoom instead of floating at a fixed pixel size.
class _SelectedMarker extends StatefulWidget {
  const _SelectedMarker({
    required this.x,
    required this.y,
    required this.scale,
    required this.color,
    required this.animate,
    super.key,
  });

  final double x;
  final double y;
  final double scale;
  final Color color;
  final bool animate;

  // SVG-unit geometry (glyph radius is 14). The ring clears the glyph; the
  // ping expands from the ring out to [_pingMaxUnits].
  static const double _haloUnits = 26;
  static const double _ringUnits = 20;
  static const double _ringStrokeUnits = 4;
  static const double _pingStartUnits = 20;
  static const double _pingMaxUnits = 52;
  static const double _pingStrokeUnits = 2.5;

  @override
  State<_SelectedMarker> createState() => _SelectedMarkerState();
}

class _SelectedMarkerState extends State<_SelectedMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _motionSynced = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _SelectedMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      _motionSynced = false;
      _syncMotion();
    }
  }

  void _syncMotion() {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (!widget.animate || disableAnimations) {
      _ctrl.value = 1;
      _motionSynced = true;
      return;
    }
    if (!_motionSynced) {
      _motionSynced = true;
      unawaited(_ctrl.forward());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final color = widget.color;
    final boxHalf = _SelectedMarker._pingMaxUnits * s;

    // Box is sized to the ping's outer bound so the expanding ring isn't
    // clipped; the static halo + ring stay centred within it.
    return Positioned(
      left: widget.x - boxHalf,
      top: widget.y - boxHalf,
      width: boxHalf * 2,
      height: boxHalf * 2,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = AppMotion.easeOut.transform(_ctrl.value);
            final pingRadius =
                (_SelectedMarker._pingStartUnits +
                    (_SelectedMarker._pingMaxUnits -
                            _SelectedMarker._pingStartUnits) *
                        t) *
                s;
            return Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.square(pingRadius * 2),
                  painter: _RingPainter(
                    color: color,
                    opacity: (1 - _ctrl.value) * 0.4,
                    strokeWidth: _SelectedMarker._pingStrokeUnits * s,
                  ),
                ),
                child!,
              ],
            );
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: _SelectedMarker._haloUnits * 2 * s,
                height: _SelectedMarker._haloUnits * 2 * s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                ),
              ),
              CustomPaint(
                size: Size.square(_SelectedMarker._ringUnits * 2 * s),
                painter: _RingPainter(
                  color: color,
                  opacity: 1,
                  strokeWidth: _SelectedMarker._ringStrokeUnits * s,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stroke ring used both for the static selection ring and the expanding,
/// fading locate-me "ping".
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.color,
    required this.opacity,
    required this.strokeWidth,
  });

  final Color color;
  final double opacity;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    canvas.drawCircle(
      Offset(r, r),
      r - strokeWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.opacity != opacity ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
