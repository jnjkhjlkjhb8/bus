import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

class AppTooltip extends StatelessWidget {
  const AppTooltip({required this.message, required this.child, super.key});
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: message,
      preferBelow: false,
      triggerMode: TooltipTriggerMode.longPress,
      showDuration: const Duration(seconds: 2),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      textStyle: AppTextStyles.bodySmall.copyWith(color: cs.onInverseSurface),
      child: child,
    );
  }
}
