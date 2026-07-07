import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

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

sealed class EtaStatus {
  const EtaStatus();
  factory EtaStatus.arriving() = _Arriving;
  factory EtaStatus.approaching() = _Approaching;
  factory EtaStatus.minutes(int m) = _Minutes;
  factory EtaStatus.label(String text) = _Label;
  factory EtaStatus.unknown() = _Unknown;
}

final class _Arriving extends EtaStatus {
  const _Arriving();
}

final class _Approaching extends EtaStatus {
  const _Approaching();
}

final class _Minutes extends EtaStatus {
  const _Minutes(this.value);
  final int value;
}

/// A service-state label (e.g. 尚未發車, 末班已過, or a scheduled clock time)
/// carried verbatim from the one status-label mapping in eta_format.dart.
final class _Label extends EtaStatus {
  const _Label(this.text);
  final String text;
}

final class _Unknown extends EtaStatus {
  const _Unknown();
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
    final routeColor = highlighted ? cs.onPrimaryContainer : cs.onSurface;
    final destColor = highlighted
        ? cs.onPrimaryContainer.withValues(alpha: 0.8)
        : cs.onSurfaceVariant;

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
        margin: highlighted
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
            : EdgeInsets.zero,
        decoration: highlighted
            ? BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              )
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
      _Arriving() => Text(
        '進站中',
        style: AppTextStyles.heading2.copyWith(
          fontWeight: FontWeight.w700,
          color: AppTheme.statusArrivingText,
        ),
      ),
      _Approaching() => Text(
        '即將進站',
        style: AppTextStyles.heading2.copyWith(
          fontWeight: FontWeight.w700,
          color: AppTheme.etaApproaching,
        ),
      ),
      _Minutes(:final value) => Row(
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
      _Label(:final text) => Text(
        text,
        style: AppTextStyles.bodyLarge.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
      _Unknown() => Text(
        '—',
        semanticsLabel: '目前無到站資訊',
        style: AppTextStyles.bodyLarge.copyWith(color: cs.outline),
      ),
    };
  }
}
