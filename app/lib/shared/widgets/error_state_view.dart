import 'package:flutter/material.dart';

import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({required this.error, this.onRetry, super.key});

  final AppError error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A bottom sheet's height can be as short as its peek detent, so this
    // must scroll rather than overflow when content + text scale exceed
    // the available space; ConstrainedBox(minHeight:) keeps it centred
    // when there's room to spare.
    //
    // Callers also place this inside unbounded-height contexts (a sliver via
    // SliverToBoxAdapter, a ListView child), where maxHeight is infinite.
    // Forcing that as a minimum would size the box infinitely, so fall back
    // to sizing to content and let the host scroll.
    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0.0;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(error.icon, size: 40, color: cs.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      error.titleOf(AppI18n.of(context)),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      error.hintOf(AppI18n.of(context)),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 20),
                      Pressable(
                        onTap: onRetry,
                        semanticLabel: AppI18n.of(context).commonRetryShort,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusButton,
                            ),
                          ),
                          child: Text(
                            AppI18n.of(context).commonRetryShort,
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
              ),
            ),
          ),
        );
      },
    );
  }
}
