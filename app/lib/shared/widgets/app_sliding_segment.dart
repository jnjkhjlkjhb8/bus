import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

class AppSlidingSegment<T> extends StatefulWidget {
  const AppSlidingSegment({
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  }) : assert(options.length == 2, 'Exactly two options are required.');

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  State<AppSlidingSegment<T>> createState() => _AppSlidingSegmentState<T>();
}

class _AppSlidingSegmentState<T> extends State<AppSlidingSegment<T>>
    with SingleTickerProviderStateMixin {
  // Thumb position as a 0..1 progress between the two segments — 0 sits on
  // the first option, 1 on the second. Unbounded controller so a
  // SpringSimulation can drive it directly by value instead of fighting the
  // default 0..1 clamp mid-flight.
  late final AnimationController _thumb = AnimationController.unbounded(
    vsync: this,
    value: _indexOf(widget.value).toDouble(),
  );

  /// Pill width + inter-pill gap in logical pixels, refreshed every layout —
  /// converts a horizontal drag delta into thumb progress.
  double _pillStride = 0;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  int _indexOf(T value) => widget.options.keys.toList().indexOf(value);

  @override
  void didUpdateWidget(AppSlidingSegment<T> old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _springTo(_indexOf(widget.value).toDouble(), _thumb.velocity);
    }
  }

  @override
  void dispose() {
    _thumb.dispose();
    super.dispose();
  }

  void _springTo(double target, double velocity) {
    if (_reduceMotion) {
      _thumb.value = target;
      return;
    }
    unawaited(
      _thumb.animateWith(
        SpringSimulation(AppMotion.spring, _thumb.value, target, velocity),
      ),
    );
  }

  void _commit(int index) {
    final keys = widget.options.keys.toList();
    if (keys[index] == widget.value) return;
    unawaited(HapticService.instance.lightTap());
    widget.onChanged(keys[index]);
  }

  void _handleTap(int index) {
    _commit(index);
    _springTo(index.toDouble(), 0);
  }

  void _handleDragStart(DragStartDetails details) {
    _thumb.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_pillStride <= 0) return;
    final delta = details.delta.dx / _pillStride;
    _thumb.value = (_thumb.value + delta).clamp(0.0, 1.0);
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocityProgress = _pillStride > 0
        ? details.velocity.pixelsPerSecond.dx / _pillStride
        : 0.0;
    // A decisive flick commits by direction even mid-crossing; otherwise the
    // segment nearest to where the thumb stopped wins.
    final target = velocityProgress.abs() > 1.5
        ? (velocityProgress > 0 ? 1 : 0)
        : _thumb.value.round().clamp(0, 1);
    _commit(target);
    _springTo(target.toDouble(), velocityProgress);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = _reduceMotion;
    final entries = widget.options.entries.toList();

    // A recessed groove holding a raised, lighter thumb. The track is a
    // translucent black overlay, not an opaque surface token, so it darkens
    // whatever hosts the control — scaffold or bottom sheet alike. An opaque
    // track keyed to a fixed surface collides with the sheet colour in dark
    // mode (surfaceContainerLow == the sheet), which erases the track entirely.
    final isDark = cs.brightness == Brightness.dark;
    final trackColor = Colors.black.withValues(alpha: isDark ? 0.30 : 0.05);
    final thumbColor = isDark
        ? cs.surfaceContainerHighest
        : cs.surfaceContainerLow;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pillWidth = (constraints.maxWidth - 8) / 2;
          _pillStride = pillWidth + 4;
          return GestureDetector(
            onHorizontalDragStart: _handleDragStart,
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: _handleDragEnd,
            child: SizedBox(
              height: 36,
              child: Stack(
                children: [
                  AnimatedBuilder(
                    animation: _thumb,
                    builder: (context, child) => Positioned(
                      left: _thumb.value.clamp(0.0, 1.0) * _pillStride,
                      top: 0,
                      bottom: 0,
                      width: pillWidth,
                      child: child!,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: thumbColor,
                        borderRadius: BorderRadius.circular(7),
                        // Light: a hairline defines the white thumb when it
                        // sits on an equally white sheet. Dark needs no edge
                        // — the lighter thumb already separates from the
                        // groove.
                        border: isDark
                            ? null
                            : Border.all(
                                color: Colors.black.withValues(alpha: .04),
                                width: .5,
                              ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? .25 : .05,
                            ),
                            blurRadius: isDark ? 2 : 4,
                            offset: Offset(0, isDark ? 1 : 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: entries.asMap().entries.map((indexed) {
                      final index = indexed.key;
                      final entry = indexed.value;
                      final selected = entry.key == widget.value;
                      return Expanded(
                        child: Semantics(
                          button: true,
                          selected: selected,
                          child: Pressable(
                            onTap: () => _handleTap(index),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : AppMotion.medium,
                                curve: AppMotion.easeOut,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: selected
                                      ? cs.onSurface
                                      : cs.onSurfaceVariant,
                                ),
                                child: Text(entry.value),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
