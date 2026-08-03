import 'package:flutter/material.dart';

import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/data/models/alert_models.dart';

/// The three color roles every notice surface needs.
///
/// `background` fills the surface, `ink` carries the reading (and is the only
/// one that has to pass contrast against the background), `accent` is the
/// icon, border, and unread dot.
typedef NoticeColors = ({Color background, Color ink, Color accent});

/// Resolves a [NoticeTone] to its colors for the current brightness.
///
/// Single source for notice coloring: the rail, the toast, the home capsule,
/// the inbox row, and the inline route notice all read this, so a tone can
/// never mean two different things on two screens. Info and neutral resolve
/// off the scheme because they are the achromatic tones — Ink and the surface
/// ramp already invert correctly.
NoticeColors noticeColors(NoticeTone tone, ColorScheme cs) {
  final dark = cs.brightness == Brightness.dark;
  return switch (tone) {
    NoticeTone.critical =>
      dark
          ? (
              background: AppTheme.criticalBgDark,
              ink: AppTheme.criticalInkDark,
              accent: AppTheme.criticalAccentDark,
            )
          : (
              background: AppTheme.criticalBg,
              ink: AppTheme.criticalInkLight,
              accent: AppTheme.criticalAccent,
            ),
    NoticeTone.caution =>
      dark
          ? (
              background: AppTheme.warningBgDark,
              ink: AppTheme.warningInkDark,
              accent: AppTheme.warningAccentDark,
            )
          : (
              background: AppTheme.warningBg,
              ink: AppTheme.warningInkLight,
              accent: AppTheme.warningBorder,
            ),
    // Info and neutral share the quiet surface on purpose. `cs.surface` is
    // the scaffold itself, so an info rail painted with it disappeared into a
    // dark background with only a hairline to prove it was there. They stay
    // distinct where it counts: Ink accent and a heavier weight for the app's
    // own voice, muted accent and regular weight for a condition.
    NoticeTone.info => (
      background: cs.surfaceContainerHighest,
      ink: cs.onSurface,
      accent: cs.onSurface,
    ),
    NoticeTone.neutral => (
      background: cs.surfaceContainerHighest,
      ink: cs.onSurface,
      accent: cs.onSurfaceVariant,
    ),
  };
}
