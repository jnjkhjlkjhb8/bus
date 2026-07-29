import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_shadows.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';

/// Semantic variant of an [AppSnackbar]. Meaning is carried by a small leading
/// icon only; the surface stays ink so it reads calm (see design principle
/// "present uncertainty gracefully").
enum SnackType { neutral, success, error }

/// The single toast surface for the app. Replaces raw
/// `ScaffoldMessenger.showSnackBar` / `SnackBar` call sites.
///
/// A floating ink pill anchored to the bottom. Reuses [ScaffoldMessenger] so
/// queueing (one at a time), timing, dismissal and safe-area insets come from
/// the framework; only the content chrome is ours.
abstract final class AppSnackbar {
  /// On-dark error tint. The token red (#BA1A1A) is too dark to read on the
  /// ink surface, so the icon uses a lighter red at the same hue.
  static const Color _errorOnInk = Color(0xFFF97066);

  static void show(
    BuildContext context,
    String message, {
    SnackType type = SnackType.neutral,
    String? action,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    ScaffoldMessenger.of(context)
      // New toast replaces the current one instead of stacking behind it.
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          dismissDirection: DismissDirection.down,
          // Actions get a longer dwell so undo stays reachable.
          duration: duration ?? Duration(seconds: action != null ? 4 : 2),
          content: _SnackContent(
            message: message,
            type: type,
            action: action,
            onAction: onAction,
          ),
        ),
      );
  }
}

class _SnackContent extends StatelessWidget {
  const _SnackContent({
    required this.message,
    required this.type,
    this.action,
    this.onAction,
  });

  final String message;
  final SnackType type;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? AppTheme.inkLight : AppTheme.surfaceHighlightDark;
    final icon = switch (type) {
      SnackType.neutral => null,
      SnackType.success => (
        Icons.check_circle_outline_rounded,
        AppTheme.statusArriving,
      ),
      SnackType.error => (Icons.error_outline_rounded, AppSnackbar._errorOnInk),
    };

    return Center(
      child: Container(
        // 36 tall for the common single-line toast; a wrapped message still
        // grows past it rather than clipping.
        constraints: const BoxConstraints(maxWidth: 440, minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          boxShadow: AppShadows.floating,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon.$1, size: 20, color: icon.$2),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Text(
                message,
                style: AppTextStyles.bodySmall.copyWith(
                  // inkDark reads on both the light-mode ink and dark-mode
                  // elevated surfaces.
                  color: AppTheme.inkDark,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 12),
              Pressable(
                onTap: () {
                  onAction?.call();
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
                semanticLabel: action,
                // The label sets no height of its own — that would drive the
                // pill taller than 36. The 44px floor is met by the hit target.
                minTapSize: 44,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 44),
                  child: Align(
                    child: Text(
                      action!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
