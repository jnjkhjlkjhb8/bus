import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

/// Severity of a [StatusBanner]. Carries the icon so callers can't pair a
/// maintenance message with an offline glyph.
enum StatusSeverity {
  /// Ops-controlled service notice. Amber, semantic, meant to be noticed.
  maintenance(Icons.build_rounded),

  /// Degraded-but-usable state (offline, cached data). Neutral, informative.
  neutral(Icons.cloud_off_rounded);

  const StatusSeverity(this.icon);

  final IconData icon;
}

/// Full-bleed status strip shown above the app shell.
///
/// A null or empty [message] collapses the strip to zero height; a non-empty
/// one grows it from the top, pushing the content below down. Callers just
/// swap the message and get the transition for free.
///
/// Announced as a live region: the strip appears without user action, so a
/// screen reader has to hear it. Reduce-motion collapses the growth to an
/// instant swap.
class StatusBanner extends StatelessWidget {
  const StatusBanner({required this.severity, this.message, super.key});

  final StatusSeverity severity;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.medium,
      curve: AppMotion.easeOut,
      alignment: Alignment.topCenter,
      child: text == null || text.isEmpty
          ? const SizedBox(width: double.infinity)
          : _Strip(severity: severity, message: text),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.severity, required this.message});

  final StatusSeverity severity;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    final (background, ink, accent) = switch (severity) {
      StatusSeverity.maintenance => dark
          ? (
              AppTheme.warningBgDark,
              AppTheme.warningInkDark,
              AppTheme.warningAccentDark,
            )
          : (
              AppTheme.warningBg,
              AppTheme.warningInkLight,
              AppTheme.warningBorder,
            ),
      StatusSeverity.neutral => (
        cs.surfaceContainerHighest,
        cs.onSurface,
        cs.onSurfaceVariant,
      ),
    };

    return Semantics(
      container: true,
      liveRegion: true,
      child: SafeArea(
        bottom: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            border: Border(
              bottom: BorderSide(color: accent.withValues(alpha: 0.28)),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
            child: Row(
              spacing: 10,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(severity.icon, size: 18, color: accent),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: ink,
                      fontWeight: severity == StatusSeverity.maintenance
                          ? FontWeight.w500
                          : FontWeight.w400,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
