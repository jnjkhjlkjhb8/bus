import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

enum _BadgeVariant { filled, outlined, dot }

class AppBadge extends StatefulWidget {
  const AppBadge({super.key, this.label})
    : _variant = label == null ? _BadgeVariant.dot : _BadgeVariant.filled;

  const AppBadge.outlined({super.key, this.label})
    : _variant = _BadgeVariant.outlined;

  final String? label;
  final _BadgeVariant _variant;

  @override
  State<AppBadge> createState() => _AppBadgeState();
}

class _AppBadgeState extends State<AppBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    unawaited(_controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget badge;
    if (widget._variant == _BadgeVariant.dot) {
      badge = Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle),
      );
    } else {
      final isOutlined = widget._variant == _BadgeVariant.outlined;
      badge = Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: isOutlined ? Colors.transparent : cs.primary,
          borderRadius: BorderRadius.circular(AppTheme.radiusStadium),
          border: isOutlined ? Border.all(color: cs.primary) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label ?? '',
          style: AppTextStyles.bodySmall.copyWith(
            color: isOutlined ? cs.primary : cs.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ScaleTransition(scale: _scale, child: badge);
  }
}
