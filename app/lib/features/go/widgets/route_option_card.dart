import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';
import 'package:wheres_the_car/features/go/widgets/transit_visuals.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

String formatClock(String raw) {
  if (raw.isEmpty) return '';
  final t = raw.contains('T') ? raw.split('T').last : raw;
  final match = RegExp(r'(\d{1,2}:\d{2})').firstMatch(t);
  return match?.group(1) ?? t;
}

int routeMinutes(PlanRoute route) {
  final value = route.travelTime;
  final minutes = value > 600 ? (value / 60).round() : value;
  return minutes.clamp(0, 999);
}

int walkMinutes(PlanRoute route) {
  var total = 0;
  for (final s in route.sections) {
    if (isWalk(s)) total += sectionMinutes(s);
  }
  return total;
}

class RouteOptionCard extends StatelessWidget {
  const RouteOptionCard({
    required this.route,
    required this.highlighted,
    required this.onTap,
    this.badge,
    super.key,
  });

  final PlanRoute route;
  final bool highlighted;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minutes = routeMinutes(route);
    final arrival = formatClock(route.endTime);
    final sections = route.sections;
    final origin = sections.isNotEmpty ? sections.first.departure.name : '';
    final dest = sections.isNotEmpty ? sections.last.arrival.name : '';

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$minutes',
          style: AppTextStyles.memo.copyWith(
            fontSize: AppTextStyles.heading1.fontSize,
            fontWeight: AppTextStyles.heading1.fontWeight,
            color: cs.onSurface,
            fontFeatures: AppTextStyles.tabularFigures,
          ),
        ),
        const SizedBox(width: 2),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            '分',
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          _Badge(label: badge!),
        ],
        const Spacer(),
        if (arrival.isNotEmpty)
          Text(
            '抵達 $arrival',
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              fontFeatures: AppTextStyles.tabularFigures,
            ),
          ),
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 10),
        _LegStrip(sections: sections, detailed: highlighted),
        if (highlighted && (origin.isNotEmpty || dest.isNotEmpty)) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  origin,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  dest,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.swap_horiz_rounded,
              size: 14,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              route.transfers == 0 ? '直達' : '轉乘 ${route.transfers} 次',
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.directions_walk_rounded,
              size: 14,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              '步行 ${walkMinutes(route)} 分',
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );

    return Pressable(
      onTap: onTap,
      semanticLabel: '$minutes 分，抵達 $arrival，往 $dest',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlighted ? cs.primaryContainer : cs.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: highlighted ? null : Border.all(color: cs.outlineVariant),
        ),
        child: content,
      ),
    );
  }
}

class _LegStrip extends StatelessWidget {
  const _LegStrip({required this.sections, required this.detailed});

  final List<PlanSection> sections;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (final (i, s) in sections.indexed) {
      final color = transitColor(s.transport, cs);
      if (isWalk(s)) {
        children.add(
          _WalkPill(minutes: sectionMinutes(s), detailed: detailed),
        );
      } else {
        children.add(
          _LinePill(
            label: sectionLabel(s),
            minutes: sectionMinutes(s),
            color: color,
            detailed: detailed,
          ),
        );
      }
      if (i < sections.length - 1) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: cs.outline,
            ),
          ),
        );
      }
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: children,
    );
  }
}

class _LinePill extends StatelessWidget {
  const _LinePill({
    required this.label,
    required this.minutes,
    required this.color,
    required this.detailed,
  });

  final String label;
  final int minutes;
  final Color color;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      ),
      child: Text(
        detailed ? '$label · $minutes分' : label,
        style: AppTextStyles.bodySmall.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _WalkPill extends StatelessWidget {
  const _WalkPill({required this.minutes, required this.detailed});

  final int minutes;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.directions_walk_rounded,
          size: 16,
          color: cs.onSurfaceVariant,
        ),
        if (detailed) ...[
          const SizedBox(width: 2),
          Text(
            '$minutes分',
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.onSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodyVerySmall.copyWith(
          color: cs.surface,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
