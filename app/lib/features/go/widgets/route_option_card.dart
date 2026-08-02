import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/data/models/plan_models.dart';
import 'package:wheres_the_bus/features/go/widgets/transit_visuals.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';
import 'package:wheres_the_bus/shared/widgets/app_badge.dart';

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

/// Scheduled wait before `sections[i]` departs: the gap between the previous
/// section's arrival and this one's departure. TDX covers transfer waiting with
/// no section of its own — it exists only as this gap, which is why the leg
/// durations alone fall short of the route total. Applies to any pair of
/// sections, so a same-platform metro transfer (no pedestrian leg between the
/// two rides) reports its wait too.
///
/// Zero when either timestamp is missing or unparseable, and when the gap is
/// negative. A walk section whose duration OSRM could not resolve keeps TDX's
/// own figure, which may already span the wait; that case leaves no gap here
/// and still reads as walking.
int waitMinutesBefore(List<PlanSection> sections, int i) {
  if (i <= 0 || i >= sections.length) return 0;
  final arrival = DateTime.tryParse(sections[i - 1].arrival.time);
  final departure = DateTime.tryParse(sections[i].departure.time);
  if (arrival == null || departure == null) return 0;
  final seconds = departure.difference(arrival).inSeconds;
  return seconds <= 0 ? 0 : (seconds / 60).round();
}

/// Total scheduled waiting across all of a route's transfers.
int waitMinutes(PlanRoute route) {
  var total = 0;
  for (var i = 1; i < route.sections.length; i++) {
    total += waitMinutesBefore(route.sections, i);
  }
  return total;
}

class RouteOptionCard extends StatelessWidget {
  const RouteOptionCard({
    required this.route,
    required this.highlighted,
    required this.onTap,
    this.badge,
    this.isSaved = false,
    this.onToggleSave,
    super.key,
  });

  final PlanRoute route;
  final bool highlighted;
  final String? badge;
  final VoidCallback onTap;

  /// Whether this route is currently in the saved snapshots.
  final bool isSaved;

  /// Tapping the bookmark toggles save state; hidden when null.
  final VoidCallback? onToggleSave;

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
          style: AppTextStyles.timeValue(
            size: AppTextStyles.heading1.fontSize,
            weight: AppTextStyles.heading1.fontWeight,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(width: 2),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            AppI18n.of(context).goMinutesUnit,
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppI18n.of(context).goArriveLabel,
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                arrival,
                style: AppTextStyles.timeValue(
                  size: AppTextStyles.bodySmall.fontSize,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        if (onToggleSave != null) ...[
          const SizedBox(width: 8),
          _SaveButton(saved: isSaved, onTap: onToggleSave!),
        ],
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 10),
        LegStrip(sections: sections, detailed: highlighted),
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
              route.transfers == 0
                  ? AppI18n.of(context).goDirect
                  : AppI18n.of(context).transfersCount(route.transfers),
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
              AppI18n.of(context).walkMinutes(walkMinutes(route)),
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (route.totalFare > 0) ...[
              const Spacer(),
              Text(
                r'NT$ ',
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                '${route.totalFare}',
                style: AppTextStyles.timeValue(
                  size: AppTextStyles.bodySmall.fontSize,
                  color: cs.onSurface,
                ),
              ),
            ],
          ],
        ),
      ],
    );

    return Pressable(
      onTap: onTap,
      semanticLabel: AppI18n.of(
        context,
      ).routeSummarySemantics(minutes, arrival, dest),
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

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saved, required this.onTap});

  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: saved
          ? AppI18n.of(context).goUnsaveRoute
          : AppI18n.of(context).goSaveRoute,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedSwitcher(
          duration: AppMotion.short,
          child: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            key: ValueKey(saved),
            size: 20,
            // Saved: solid Ink black. Unsaved: hollow, muted outline.
            color: saved ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The route's legs as a chip run: line badges for transit, a walking glyph
/// for the pedestrian stretches, chevrons between. Shared with the waiting
/// state's "last time" card, which shows the same shape at a glance.
class LegStrip extends StatelessWidget {
  const LegStrip({required this.sections, required this.detailed, super.key});

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
          AppBadge(
            label: detailed
                ? AppI18n.of(context).legLabelWithMinutes(
                    sectionLabel(AppI18n.of(context), s),
                    sectionMinutes(s),
                  )
                : sectionLabel(AppI18n.of(context), s),
            color: color,
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
            AppI18n.of(context).minutesTight(minutes),
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
