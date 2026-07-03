import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';

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
  late final AnimationController _controller;
  Animation<double> _hand = const AlwaysStoppedAnimation(0);
  double _angle = 0;
  bool _reduceMotion = false;

  double get _radius => widget.size / 2 - 24;

  double _angleFor(int index) {
    if (widget.items.isEmpty) return 0;
    final i = index.clamp(0, widget.items.length - 1);
    return -pi / 2 + (i / widget.items.length) * 2 * pi;
  }

  @override
  void initState() {
    super.initState();
    _angle = _angleFor(widget.selectedIndex);
    _hand = AlwaysStoppedAnimation(_angle);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didUpdateWidget(ClockDial old) {
    super.didUpdateWidget(old);
    if (old.items.length != widget.items.length) {
      setState(() => _angle = _angleFor(widget.selectedIndex));
      _hand = AlwaysStoppedAnimation(_angle);
    } else if (old.selectedIndex != widget.selectedIndex) {
      _animateTo(_angleFor(widget.selectedIndex));
    }
  }

  void _animateTo(double target) {
    if (_reduceMotion) {
      setState(() => _angle = target);
      _hand = AlwaysStoppedAnimation(target);
      return;
    }
    var t = target;
    while (t - _angle > pi) {
      t -= 2 * pi;
    }
    while (t - _angle < -pi) {
      t += 2 * pi;
    }
    _hand = Tween<double>(begin: _angle, end: t).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    )..addListener(() => setState(() => _angle = _hand.value));
    unawaited(_controller.forward(from: 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePointer(Offset local) {
    if (widget.items.isEmpty) return;
    final center = widget.size / 2;
    final theta = atan2(local.dy - center, local.dx - center);
    final n = widget.items.length;
    var idx = (((theta + pi / 2) / (2 * pi)) * n).round() % n;
    if (idx < 0) idx += n;
    if (idx != widget.selectedIndex) {
      unawaited(HapticFeedback.selectionClick());
      widget.onSelected(idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final items = widget.items;
    final selectedIndex = widget.selectedIndex;
    final size = widget.size;
    final hasSelection = selectedIndex >= 0 && selectedIndex < items.length;
    final angle = _angle;
    final dx = _radius * cos(angle);
    final dy = _radius * sin(angle);

    return GestureDetector(
      onTapDown: (d) => _handlePointer(d.localPosition),
      onPanStart: (d) => _handlePointer(d.localPosition),
      onPanUpdate: (d) => _handlePointer(d.localPosition),
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
              Positioned(
                left: size / 2,
                top: size / 2,
                child: Transform.rotate(
                  angle: angle - pi / 2,
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 2,
                    height: _radius,
                    color: cs.primary,
                  ),
                ),
              ),
              Positioned(
                left: size / 2 + dx - 24,
                top: size / 2 + dy - 24,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary,
                  ),
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
