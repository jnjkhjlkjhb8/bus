import 'package:flutter/material.dart';

import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/notice_tone.dart';
import 'package:wheres_the_bus/data/models/alert_models.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';

/// Full-bleed strip pinned above the app shell — the resident notice layer.
///
/// Only two things earn a rail: an ops-authored announcement, and a condition
/// that is true right now and that the rider cannot dismiss away (offline,
/// alert stream down, location denied). Anything that *happened* belongs in
/// the inbox instead; a rail that outlives its condition is a lie.
///
/// A null or empty [message] collapses the strip to zero height, so callers
/// just swap the message and get the transition for free. Announced as a live
/// region because it appears without user action; reduce-motion collapses the
/// growth to an instant swap.
class NoticeRail extends StatelessWidget {
  const NoticeRail({
    required this.tone,
    required this.icon,
    this.message,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    super.key,
  });

  final NoticeTone tone;
  final IconData icon;
  final String? message;

  /// Inline action, for a condition the rider can actually fix (「開啟定位」).
  /// Both this and [onAction] must be set for the action to render.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Null for notices the rider may not clear — an ops maintenance window
  /// goes away when ops turn it off, not when a rider taps.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return AnimatedSize(
      duration: AppMotion.reduced(context)
          ? AppMotion.instant
          : AppMotion.medium,
      curve: AppMotion.easeOut,
      alignment: Alignment.topCenter,
      child: text == null || text.isEmpty
          ? const SizedBox(width: double.infinity)
          : _Strip(
              tone: tone,
              icon: icon,
              message: text,
              actionLabel: actionLabel,
              onAction: onAction,
              onDismiss: onDismiss,
            ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.tone,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
  });

  final NoticeTone tone;
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = noticeColors(tone, cs);
    final label = actionLabel;

    return Semantics(
      container: true,
      liveRegion: true,
      child: SafeArea(
        bottom: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background,
            border: Border(
              bottom: BorderSide(
                color: colors.accent.withValues(alpha: 0.28),
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              11,
              onDismiss == null ? 16 : 4,
              12,
            ),
            child: Row(
              spacing: 10,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: colors.accent),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyRegular.copyWith(
                          color: colors.ink,
                          fontWeight: tone == NoticeTone.neutral
                              ? FontWeight.w400
                              : FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                      if (label != null && onAction != null)
                        Pressable(
                          onTap: onAction,
                          semanticLabel: label,
                          child: Padding(
                            // Vertical padding only: the label stays optically
                            // flush with the message above it while the tap
                            // target still clears the 44px floor with the row.
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              label,
                              style: AppTextStyles.bodyRegular.copyWith(
                                color: colors.ink,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: colors.ink.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: colors.accent,
                    onPressed: onDismiss,
                    tooltip: AppI18n.of(context).commonClose,
                    padding: EdgeInsets.zero,
                    // 18px glyph, but the hit target keeps the 44px floor.
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
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
