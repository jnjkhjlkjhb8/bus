import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

class ClockDial extends StatefulWidget {
  const ClockDial({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
    this.size = 256.0,
  });

  final List<String> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double size;

  @override
  State<ClockDial> createState() => _ClockDialState();
}

class _ClockDialState extends State<ClockDial>
    with SingleTickerProviderStateMixin {
  // Unbounded: the hand angle isn't a 0..1 progress value, it's the raw
  // radian position, and it needs to be able to accumulate past ±π as the
  // finger crosses the wrap boundary without clamping.
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
  );
  bool _reduceMotion = false;

  /// Last pointer position during a pan, used at release to convert linear
  /// flick velocity into an angular velocity for the spring hand-off.
  Offset? _lastLocal;

  double get _radius => widget.size / 2 - 24;

  double _angleFor(int index) {
    if (widget.items.isEmpty) return 0;
    final i = index.clamp(0, widget.items.length - 1);
    return -pi / 2 + (i / widget.items.length) * 2 * pi;
  }

  /// Shifts [target] by whole turns so it lands within half a turn of
  /// [reference] — the shortest path, and no visual jump across the ±π seam.
  double _unwrapNear(double target, double reference) {
    var t = target;
    while (t - reference > pi) {
      t -= 2 * pi;
    }
    while (t - reference < -pi) {
      t += 2 * pi;
    }
    return t;
  }

  @override
  void initState() {
    super.initState();
    _controller.value = _angleFor(widget.selectedIndex);
  }

  @override
  void didUpdateWidget(ClockDial old) {
    super.didUpdateWidget(old);
    if (old.items.length != widget.items.length) {
      _controller.value = _angleFor(widget.selectedIndex);
    } else if (old.selectedIndex != widget.selectedIndex) {
      _animateTo(_angleFor(widget.selectedIndex));
    }
  }

  /// Programmatic retarget (e.g. selection changed from outside the dial):
  /// springs from wherever the hand currently is — including mid-flight —
  /// carrying its current velocity, instead of cutting to a fixed-duration
  /// tween from a standing start.
  void _animateTo(double target) {
    final unwrapped = _unwrapNear(target, _controller.value);
    if (_reduceMotion) {
      _controller.value = unwrapped;
      return;
    }
    final sim = SpringSimulation(
      AppMotion.spring,
      _controller.value,
      unwrapped,
      _controller.velocity,
    );
    unawaited(_controller.animateWith(sim));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Sector-crossing commit: fires the haptic and reports the new index the
  /// instant the pointer crosses a sector midpoint, independent of whether
  /// the hand itself has finished tracking there yet. Returns the sector the
  /// pointer is over now (whether or not it was newly committed), so callers
  /// don't have to wait a frame for `widget.selectedIndex` to catch up.
  int? _commitSector(Offset local) {
    if (widget.items.isEmpty) return null;
    final center = widget.size / 2;
    final theta = atan2(local.dy - center, local.dx - center);
    final n = widget.items.length;
    var idx = (((theta + pi / 2) / (2 * pi)) * n).round() % n;
    if (idx < 0) idx += n;
    if (idx != widget.selectedIndex) {
      unawaited(HapticFeedback.selectionClick());
      widget.onSelected(idx);
    }
    return idx;
  }

  /// Tap: jump straight to the tapped sector (no drag to track).
  void _handleTap(Offset local) {
    final idx = _commitSector(local);
    if (idx != null) _animateTo(_angleFor(idx));
  }

  /// Drag: the hand follows the raw finger angle 1:1, live — not quantized
  /// to the nearest sector and then animated over. Index commits (and their
  /// haptic) still happen the instant a sector midpoint is crossed.
  void _trackPointer(Offset local) {
    _lastLocal = local;
    final idx = _commitSector(local);
    if (idx == null) return;
    if (_reduceMotion) {
      _controller.value = _angleFor(idx);
      return;
    }
    final center = widget.size / 2;
    final theta = atan2(local.dy - center, local.dx - center);
    final unwrapped = _unwrapNear(theta, _controller.value);
    _controller
      ..stop()
      ..value = unwrapped;
  }

  /// Release: springs the hand the rest of the way from wherever the raw
  /// angle stopped to the selected sector's centre, carrying the finger's
  /// release velocity (converted from linear to angular) so the settle
  /// reads as a continuation of the flick, not a reset.
  void _settle(Velocity velocity) {
    final local = _lastLocal;
    var angularVelocity = 0.0;
    if (local != null) {
      final center = widget.size / 2;
      final x = local.dx - center;
      final y = local.dy - center;
      final r2 = x * x + y * y;
      if (r2 > 0) {
        final v = velocity.pixelsPerSecond;
        angularVelocity = (x * v.dy - y * v.dx) / r2;
      }
    }
    _lastLocal = null;
    final target = _unwrapNear(
      _angleFor(widget.selectedIndex),
      _controller.value,
    );
    if (_reduceMotion) {
      _controller.value = target;
      return;
    }
    final sim = SpringSimulation(
      AppMotion.spring,
      _controller.value,
      target,
      angularVelocity,
    );
    unawaited(_controller.animateWith(sim));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final items = widget.items;
    final selectedIndex = widget.selectedIndex;
    final size = widget.size;
    final hasSelection = selectedIndex >= 0 && selectedIndex < items.length;

    return GestureDetector(
      onTapDown: (d) => _handleTap(d.localPosition),
      onPanStart: (d) => _trackPointer(d.localPosition),
      onPanUpdate: (d) => _trackPointer(d.localPosition),
      onPanEnd: (d) => _settle(d.velocity),
      onPanCancel: () => _settle(Velocity.zero),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.surfaceContainerHighest,
              ),
            ),
            if (hasSelection) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary,
                ),
              ),
              AnimatedBuilder(
                animation: _controller,
                child: Container(
                  width: 2,
                  height: _radius,
                  color: cs.primary,
                ),
                builder: (context, child) => Positioned(
                  left: size / 2,
                  top: size / 2,
                  child: Transform.rotate(
                    angle: _controller.value - pi / 2,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _controller,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary,
                  ),
                ),
                builder: (context, child) => Positioned(
                  left: size / 2 + _radius * cos(_controller.value) - 24,
                  top: size / 2 + _radius * sin(_controller.value) - 24,
                  child: child!,
                ),
              ),
            ],
            ...items.asMap().entries.map((entry) {
              final i = entry.key;
              final label = entry.value;
              final itemAngle = -pi / 2 + (i / items.length) * 2 * pi;
              final itemDx = _radius * cos(itemAngle);
              final itemDy = _radius * sin(itemAngle);
              final isSelected = i == selectedIndex;

              return Positioned(
                left: size / 2 + itemDx - 24,
                top: size / 2 + itemDy - 24,
                child: IgnorePointer(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: Duration(
                          milliseconds: _reduceMotion ? 0 : 150,
                        ),
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected ? cs.onPrimary : cs.onSurface,
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
