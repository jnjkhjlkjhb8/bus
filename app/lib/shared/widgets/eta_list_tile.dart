import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/arrival_display.dart';
import 'package:wheres_the_car/data/models/eta_status.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

export 'package:wheres_the_car/data/models/eta_status.dart';

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
    this.track,
  });

  /// Builds a tile straight from the shared [ArrivalDisplay] contract. The
  /// caller decides [highlighted] from the list position and
  /// [ArrivalDisplay.isComingSoon] so at most the soonest row lights up; modes
  /// without the coming-soon highlight (metro) leave it false.
  factory EtaListTile.fromDisplay(
    ArrivalDisplay display, {
    Key? key,
    String? direction,
    VoidCallback? onTap,
    bool highlighted = false,
    Widget? track,
  }) => EtaListTile(
    key: key,
    routeNo: display.label,
    status: display.status,
    destination: display.destination,
    direction: direction,
    onTap: onTap,
    highlighted: highlighted,
    track: track,
  );

  final String routeNo;
  final EtaStatus status;
  final String destination;
  final String? direction;
  final VoidCallback? onTap;
  final bool highlighted;
  final Widget? track;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // The coming-soon highlight is achromatic: same Ink text as every other
    // row, emphasis carried by the surface-highlight background alone.
    final routeColor = cs.onSurface;
    final destColor = cs.onSurfaceVariant;

    final row = Row(
      children: [
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
                '往 $destination',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyRegular.copyWith(color: destColor),
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
        EtaValue(status: status),
      ],
    );

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
      semanticLabel: '$routeNo 往 $destination',
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
  const EtaValue({required this.status, super.key});
  final EtaStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      EtaArriving() => Text(
        '進站中',
        style: AppTextStyles.heading2.copyWith(
          fontWeight: FontWeight.w700,
          color: AppTheme.statusArrivingText,
        ),
      ),
      EtaApproaching() => Text(
        '即將進站',
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
            style: AppTextStyles.memo.copyWith(
              fontSize: AppTextStyles.heading1.fontSize,
              fontWeight: AppTextStyles.heading1.fontWeight,
              color: cs.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 2),
          Text(
            '分',
            style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
      EtaLabel(:final text) => Text(
        text,
        style: AppTextStyles.bodyLarge.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
      EtaUnknown() => Text(
        '—',
        semanticsLabel: '目前無到站資訊',
        style: AppTextStyles.bodyLarge.copyWith(color: cs.outline),
      ),
    };
  }
}
