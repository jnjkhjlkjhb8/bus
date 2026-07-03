import 'package:flutter/material.dart';

import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({required this.error, this.onRetry, super.key});

  final AppError error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(error.icon, size: 40, color: cs.outline),
          const SizedBox(height: 16),
          Text(
            error.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            error.hint,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            Pressable(
              onTap: onRetry,
              semanticLabel: '重試',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                ),
                child: Text(
                  '重試',
                  style: AppTextStyles.bodyRegular.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
