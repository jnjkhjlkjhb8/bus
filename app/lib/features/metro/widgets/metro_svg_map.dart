import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wheres_the_car/data/models/metro_map_models.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

class MetroSvgMap extends StatelessWidget {
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final s = constraints.maxWidth / _mapW;
      final mapH = _mapH * s;

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
                child: SvgPicture.asset(
                  'assets/mrt/TRTC_map.svg',
                  fit: BoxFit.fill,
                ),
              ),
              for (final station in metroMapStations)
                if (station.id == selectedStationId)
                  _SelectedMarker(
                    key: ValueKey(selectedStationId),
                    x: station.x * s,
                    y: station.y * s,
                    animate: animate,
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
                      key: ValueKey(station.id),
                      onTap: () => onStationTap(station),
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              for (final station in metroMapStations)
                if (stationLabels[station.id] case final label?)
                  Positioned(
                    left: station.x * s - 24,
                    top: station.y * s - 2,
                    width: 48,
                    child: IgnorePointer(
                      child: _AnimatedLabel(
                        key: ValueKey(station.id),
                        label: label,
                        delayMs: getDelayMs(station),
                        animate: animate,
                        isSelected: station.id == selectedStationId,
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

class _AnimatedLabel extends StatefulWidget {
  const _AnimatedLabel({
    required this.label,
    required this.delayMs,
    required this.animate,
    required this.isSelected,
    super.key,
  });

  final String label;
  final int delayMs;
  final bool animate;
  final bool isSelected;

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
          style: const TextStyle(
            fontSize: 4,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            height: 1,
          ),
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
  late final AnimationController _ctrl;
  late final Animation<double> _markerScale;
  bool _motionSynced = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AppMotion.medium,
    );

    _markerScale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: AppMotion.easeOut,
      ),
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

    return Positioned(
      left: widget.x - 12,
      top: widget.y - 12,
      width: 24,
      height: 24,
      child: IgnorePointer(
        child: ScaleTransition(
          scale: _markerScale,
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
    );
  }
}
