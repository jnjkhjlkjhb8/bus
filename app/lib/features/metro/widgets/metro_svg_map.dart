import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/metro_map_models.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

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
  /// Station hit-targets (120 Semantics+GestureDetector subtrees) are built
  /// one frame after the route transition instead of during it — their
  /// one-time ~80ms build would stutter the push animation.
  bool _hitTargetsReady = false;
  Timer? _deferTimer;

  @override
  void initState() {
    super.initState();
    _deferTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _hitTargetsReady = true);
    });
  }

  @override
  void dispose() {
    _deferTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final s = constraints.maxWidth / MetroSvgMap._mapW;
      final mapH = MetroSvgMap._mapH * s;
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

      return InteractiveViewer(
        minScale: .45,
        maxScale: 4,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(120),
        child: SizedBox(
          width: constraints.maxWidth,
          height: mapH,
          child: Stack(
            children: [
              Positioned.fill(
                child: _RasterSvg(
                  asset: isDark
                      ? 'assets/mrt/TRTC_map_dark.svg'
                      : 'assets/mrt/TRTC_map_light.svg',
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
              if (_hitTargetsReady)
                for (final station in metroMapStations)
                  Positioned(
                    left: station.x * s - 12,
                    top: station.y * s - 12,
                    width: 24,
                    height: 24,
                    child: Semantics(
                      button: true,
                      label: '${station.id} ${station.name}',
                      child: GestureDetector(
                        key: ValueKey(station.id),
                        onTap: () => widget.onStationTap(station),
                        behavior: HitTestBehavior.opaque,
                        child: const SizedBox.expand(),
                      ),
                    ),
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
      );
    },
  );
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
  // ponytail: images cached for app lifetime (one per theme actually viewed,
  // ~20-30MB each); evict on memory pressure if this ever shows up in
  // profiling.
  static final Map<String, Future<ui.Image>> _cache = {};

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

  static Future<ui.Image> ensure(String asset, int targetW) => _cache
      .putIfAbsent('$asset@$targetW', () => _rasterize(asset, targetW));

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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = Tween<double>(begin: 0.5, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );

    _playEntry();
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
    if (!widget.animate) {
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
