import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wheres_the_car/data/models/metro_map_models.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

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

  @override
  State<MetroSvgMap> createState() => _MetroSvgMapState();
}

class _MetroSvgMapState extends State<MetroSvgMap> {
  // The base layer (SVG + 120 gesture targets) depends only on the layout
  // scale, never on selection or labels. Cache it so selecting a station or
  // toggling time/fare doesn't rebuild the 360KB SVG widget + every hit target.
  late Widget _baseLayer;
  double _baseScale = double.nan;

  Widget _buildBaseLayer(double s) => RepaintBoundary(
    child: Stack(
      children: [
        // Isolated so marker/label/ring animations never recomposite the
        // large rasterised SVG.
        Positioned.fill(
          child: RepaintBoundary(
            child: SvgPicture.asset(
              'assets/mrt/TRTC_map.svg',
              fit: BoxFit.fill,
            ),
          ),
        ),
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
                onTap: () => widget.onStationTap(station),
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final s = constraints.maxWidth / MetroSvgMap._mapW;
      final mapH = MetroSvgMap._mapH * s;

      if (_baseScale != s) {
        _baseScale = s;
        _baseLayer = _buildBaseLayer(s);
      }

      final selectedStation = widget.selectedStationId != null
          ? metroMapStations.firstWhere(
              (st) => st.id == widget.selectedStationId,
              orElse: () => metroMapStations.first,
            )
          : null;

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
              _baseLayer,
              if (selectedStation != null)
                _SelectedMarker(
                  key: ValueKey(widget.selectedStationId),
                  x: selectedStation.x * s,
                  y: selectedStation.y * s,
                  animate: widget.animate,
                ),
              RepaintBoundary(
                child: _StationLabels(
                  labels: widget.stationLabels,
                  scale: s,
                  selectedStation: selectedStation,
                  animate: widget.animate,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// All travel-time / fare labels driven by a single [AnimationController].
/// Each label staggers via an [Interval] computed from its distance to the
/// selected station — replacing the previous one-controller-plus-Timer per
/// label (120 tickers on every selection).
class _StationLabels extends StatefulWidget {
  const _StationLabels({
    required this.labels,
    required this.scale,
    required this.selectedStation,
    required this.animate,
  });

  final Map<String, String> labels;
  final double scale;
  final MetroMapStation? selectedStation;
  final bool animate;

  @override
  State<_StationLabels> createState() => _StationLabelsState();
}

class _LabelEntry {
  const _LabelEntry({
    required this.left,
    required this.top,
    required this.begin,
    required this.end,
    required this.label,
  });

  final double left;
  final double top;
  final double begin; // normalised window start (0..1)
  final double end; // normalised window end (0..1)
  final String label;
}

class _StationLabelsState extends State<_StationLabels>
    with SingleTickerProviderStateMixin {
  // Total timeline = max stagger delay (600ms) + per-label window (200ms).
  static const double _windowMs = 200;
  static const double _totalMs = 800;

  late final AnimationController _ctrl;
  List<_LabelEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _rebuildEntries();
    _play();
  }

  @override
  void didUpdateWidget(covariant _StationLabels old) {
    super.didUpdateWidget(old);
    final selChanged = old.selectedStation?.id != widget.selectedStation?.id;
    if (selChanged ||
        old.scale != widget.scale ||
        !identical(old.labels, widget.labels)) {
      _rebuildEntries();
    }
    if (selChanged || old.animate != widget.animate) {
      _play();
    }
  }

  void _rebuildEntries() {
    final sel = widget.selectedStation;
    final list = <_LabelEntry>[];
    for (final station in metroMapStations) {
      final label = widget.labels[station.id];
      if (label == null) continue;
      var delay = 0.0;
      if (sel != null) {
        final dx = station.x - sel.x;
        final dy = station.y - sel.y;
        delay = (math.sqrt(dx * dx + dy * dy) * 0.25).clamp(0.0, 600.0);
      }
      list.add(
        _LabelEntry(
          left: station.x * widget.scale - 24,
          top: station.y * widget.scale - 2,
          begin: delay / _totalMs,
          end: (delay + _windowMs) / _totalMs,
          label: label,
        ),
      );
    }
    _entries = list;
  }

  void _play() {
    _ctrl.value = 0;
    if (!widget.animate) {
      _ctrl.value = 1;
      return;
    }
    unawaited(_ctrl.forward());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final v = _ctrl.value;
          return Stack(
            children: [
              for (final e in _entries)
                Positioned(
                  left: e.left,
                  top: e.top,
                  width: 48,
                  child: _label(e, v),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _label(_LabelEntry e, double v) {
    final raw = ((v - e.begin) / (e.end - e.begin)).clamp(0.0, 1.0);
    final scale = 0.5 + 0.5 * Curves.easeOutBack.transform(raw);
    final opacity = Curves.easeOut.transform(raw);
    // Opacity is baked into the text colour (no saveLayer per label).
    return Transform.scale(
      scale: scale,
      child: Text(
        e.label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 4,
          fontWeight: FontWeight.w800,
          color: Colors.black.withValues(alpha: opacity),
          height: 1,
        ),
      ),
    );
  }
}

class _SelectedMarker extends StatefulWidget {
  const _SelectedMarker({
    required this.x,
    required this.y,
    required this.animate,
    super.key,
  });

  final double x;
  final double y;
  final bool animate;

  @override
  State<_SelectedMarker> createState() => _SelectedMarkerState();
}

class _SelectedMarkerState extends State<_SelectedMarker>
    with SingleTickerProviderStateMixin {
  static const double _ringMax = 72;

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
    final cs = Theme.of(context).colorScheme;

    // Static marker (no scale-in); a locate-me-style ring pings out from it on
    // each selection. Box is sized to _ringMax so the expanding ring isn't
    // clipped; the marker stays centred within it.
    return Positioned(
      left: widget.x - _ringMax,
      top: widget.y - _ringMax,
      width: _ringMax * 2,
      height: _ringMax * 2,
      child: RepaintBoundary(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              final t = _ctrl.value;
              final radius = 12 + AppMotion.easeOut.transform(t) * 60;
              return Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size.square(radius * 2),
                    painter: _RingPainter(
                      color: cs.onSurface,
                      opacity: (1 - t) * 0.4,
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
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.onSurface.withValues(alpha: 0.15),
                  ),
                ),
                Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Expanding, fading stroke ring — the locate-me "ping" reused for metro
/// station selection. Copied from the home locate-me cue.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    canvas.drawCircle(
      Offset(r, r),
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.opacity != opacity || old.color != color;
}
