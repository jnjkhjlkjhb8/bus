import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

class RouteMiniTrack extends StatelessWidget {
  const RouteMiniTrack({
    this.progress,
    this.color,
    this.originLabel,
    this.destinationLabel,
    super.key,
  });

  final double? progress;
  final Color? color;
  final String? originLabel;
  final String? destinationLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    final p = progress?.clamp(0.0, 1.0);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final hasVehicle = p != null;

    final rail = SizedBox(
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (hasVehicle)
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: p,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: _endDot(cs.surface, cs.outlineVariant),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _endDot(cs.surface, c),
          ),
          if (hasVehicle)
            AnimatedAlign(
              duration: reduceMotion ? Duration.zero : AppMotion.medium,
              curve: AppMotion.easeInOut,
              alignment: Alignment(p * 2 - 1, 0),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 3),
                ),
              ),
            ),
        ],
      ),
    );

    if (originLabel == null && destinationLabel == null) return rail;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        rail,
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              originLabel ?? '',
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            Text(
              destinationLabel ?? '',
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _endDot(Color fill, Color border) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: fill,
      shape: BoxShape.circle,
      border: Border.all(color: border, width: 4),
    ),
  );
}
