import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/data/models/arrival_display.dart';
import 'package:wheres_the_bus/data/models/eta_status.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';

export 'package:wheres_the_bus/data/models/eta_status.dart';

@Preview(name: 'EtaListTile — arriving', group: 'ETA')
@Preview(name: 'EtaListTile — minutes', group: 'ETA')
@Preview(name: 'EtaListTile — highlighted', group: 'ETA')
@Preview(name: 'EtaListTile — unknown', group: 'ETA')
Widget etaListTilePreviews() {
  return MaterialApp(
    home: Scaffold(
      body: ListView(
        children: [
          EtaListTile(
            routeNo: '307',
            destination: '板橋',
            status: EtaStatus.arriving(),
          ),
          EtaListTile(
            routeNo: '261',
            destination: '銘傳大學',
            status: EtaStatus.approaching(),
          ),
          EtaListTile(
            routeNo: '桃園106',
            destination: '中壢火車站',
            status: EtaStatus.minutes(5),
            highlighted: true,
          ),
          EtaListTile(
            routeNo: '652',
            destination: '台北車站',
            status: EtaStatus.unknown(),
          ),
        ],
      ),
    ),
  );
}

class EtaListTile extends StatelessWidget {
  const EtaListTile({
    required this.routeNo,
    required this.status,
    required this.destination,
    super.key,
    this.direction,
    this.onTap,
    this.highlighted = false,
    this.muted = false,
    this.track,
    this.leading,
    this.destinationStyle,
    this.bare = false,
  });

  /// Builds a tile straight from the shared [ArrivalDisplay] contract. The
  /// caller decides [highlighted] from the list position and
  /// [ArrivalDisplay.isComingSoon] so at most the soonest row lights up; modes
  /// without the coming-soon highlight (metro) leave it false.
  ///
  /// [leading] replaces the [routeNo] text with a custom lead (metro's line
  /// roundel); [destinationStyle] overrides the default destination text style;
  /// [bare] drops the tap/highlight/min-height chrome, leaving just the row so
  /// a caller can supply its own list chrome (metro's divider-separated rows).
  factory EtaListTile.fromDisplay(
    ArrivalDisplay display, {
    Key? key,
    String? direction,
    VoidCallback? onTap,
    bool highlighted = false,
    bool muted = false,
    Widget? track,
    Widget? leading,
    TextStyle? destinationStyle,
    bool bare = false,
  }) => EtaListTile(
    key: key,
    routeNo: display.label,
    status: display.status,
    destination: display.destination,
    direction: direction,
    onTap: onTap,
    highlighted: highlighted,
    muted: muted,
    track: track,
    leading: leading,
    destinationStyle: destinationStyle,
    bare: bare,
  );

  final String routeNo;
  final EtaStatus status;
  final String destination;
  final String? direction;
  final VoidCallback? onTap;
  final bool highlighted;

  /// Mutes the whole row to the disabled ink (service-over states like
  /// 末班已過 / 今日未營運), so ended rows stop competing with live ETAs.
  final bool muted;

  final Widget? track;

  /// Custom leading widget in place of the [routeNo] text (a line roundel).
  final Widget? leading;

  /// Overrides the destination text style; defaults to `bodyRegular`.
  final TextStyle? destinationStyle;

  /// When true, renders only the row (no Pressable, highlight, min-height, or
  /// padding), letting the caller own the surrounding list chrome.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // The coming-soon highlight is achromatic: same Ink text as every other
    // row, emphasis carried by the surface-highlight background alone.
    final routeColor = muted ? cs.outline : cs.onSurface;
    final destColor = muted ? cs.outline : cs.onSurfaceVariant;

    final row = Row(
      children: [
        leading ??
            Text(
              routeNo,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w700,
                color: routeColor,
              ),
            ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppI18n.of(context).towardsSpaced(destination),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // A custom destination style (metro's heading2) is used
                // verbatim, keeping its own colour; the default path carries
                // the muted destination colour.
                style:
                    destinationStyle ??
                    AppTextStyles.bodyRegular.copyWith(color: destColor),
              ),
              if (direction != null)
                Text(
                  direction!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(color: destColor),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        EtaValue(status: status, muted: muted),
      ],
    );

    // Bare mode: just the row (plus any track), so the caller owns list chrome.
    if (bare) {
      if (track == null) return row;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [row, const SizedBox(height: 6), track!],
      );
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Align(alignment: Alignment.centerLeft, child: row),
        ),
        if (track != null) ...[const SizedBox(height: 6), track!],
      ],
    );

    return Pressable(
      onTap: onTap,
      semanticLabel: AppI18n.of(
        context,
      ).etaTowardsSemantics(routeNo, destination),
      child: Container(
        // Margin + padding sum to 16 on each side either way, so the highlight
        // tint insets without shifting the row's content off the 16px column.
        margin: highlighted
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : EdgeInsets.zero,
        decoration: highlighted
            ? BoxDecoration(
                color: cs.brightness == Brightness.light
                    ? AppTheme.surfaceHighlightLight
                    : AppTheme.surfaceHighlightDark,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              )
            : null,
        padding: EdgeInsets.symmetric(
          horizontal: highlighted ? 8 : 16,
          vertical: 10,
        ),
        child: content,
      ),
    );
  }
}

class EtaValue extends StatelessWidget {
  const EtaValue({required this.status, this.muted = false, super.key});
  final EtaStatus status;

  /// Disabled-ink rendering for service-over rows; only the label and unknown
  /// shapes can appear muted (live countdowns are never service-over).
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      EtaArriving() => Text(
        AppI18n.of(context).etaArriving,
        style: AppTextStyles.heading2.copyWith(
          fontWeight: FontWeight.w700,
          color: AppTheme.statusArrivingText,
        ),
      ),
      EtaApproaching() => Text(
        AppI18n.of(context).etaApproaching,
        style: AppTextStyles.heading2.copyWith(
          fontWeight: FontWeight.w700,
          color: AppTheme.etaApproaching,
        ),
      ),
      EtaMinutes(:final value) => Row(
        textBaseline: TextBaseline.alphabetic,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: _bigTime(cs),
          ),
          const SizedBox(width: 2),
          Text(
            AppI18n.of(context).goMinutesUnit,
            style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
      EtaMinutesSeconds(:final minutes, :final seconds) => Row(
        textBaseline: TextBaseline.alphabetic,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$minutes',
            style: _bigTime(cs),
          ),
          Text(
            AppI18n.of(context).goMinutesUnit,
            style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 2),
          Text(
            seconds.toString().padLeft(2, '0'),
            style: _bigTime(cs),
          ),
          Text(
            AppI18n.of(context).etaSecondsUnit,
            style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
      EtaLabel(:final text) when _isClock(text) => Text(
        text,
        style: AppTextStyles.memo.copyWith(
          fontSize: muted
              ? AppTextStyles.bodyRegular.fontSize
              : AppTextStyles.heading1.fontSize,
          fontWeight: muted
              ? FontWeight.w400
              : AppTextStyles.heading1.fontWeight,
          color: muted ? cs.outline : cs.onSurface,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      EtaLabel(:final text) => Text(
        text,
        style: AppTextStyles.bodyLarge.copyWith(
          fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
          fontSize: muted ? AppTextStyles.bodyRegular.fontSize : null,
          color: muted ? cs.outline : cs.onSurfaceVariant,
        ),
      ),
      EtaUnknown() => Text(
        '—',
        semanticsLabel: AppI18n.of(context).etaNoInfo,
        style: AppTextStyles.bodyLarge.copyWith(color: cs.outline),
      ),
    };
  }
}

final _clockPattern = RegExp(r'^\d{2}:\d{2}$');
bool _isClock(String text) => _clockPattern.hasMatch(text);

/// The prominent mono time-value style (heading1 size/weight, tabular figures)
/// shared by the minute and minute+second countdowns.
TextStyle _bigTime(ColorScheme cs) => AppTextStyles.memo.copyWith(
  fontSize: AppTextStyles.heading1.fontSize,
  fontWeight: AppTextStyles.heading1.fontWeight,
  color: cs.onSurface,
  fontFeatures: const [FontFeature.tabularFigures()],
);
