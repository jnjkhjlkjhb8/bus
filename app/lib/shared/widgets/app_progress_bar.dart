import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    this.value,
    this.color,
    this.backgroundColor,
    this.borderRadius = AppTheme.radiusStadium,
  });

  final double? value;
  final Color? color;
  final Color? backgroundColor;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 6,
        color: color ?? cs.primary,
        backgroundColor: backgroundColor ?? cs.surfaceContainerHighest,
      ),
    );
  }
}
