import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

class AvailabilityGauge extends StatelessWidget {
  const AvailabilityGauge({
    required this.available,
    required this.docks,
    super.key,
  });

  final int available;
  final int docks;

  static const _lowThreshold = 2;

  @override
  Widget build(BuildContext context) {
    final total = (available + docks).clamp(1, 1 << 20);
    final availFrac = available / total;

    final lowAvailable = available <= _lowThreshold;
    final fullDocks = docks == 0;

    final availColor = lowAvailable
        ? AppTheme.etaArriving
        : AppTheme.statusArriving;
    final docksColor = fullDocks
        ? AppTheme.etaArriving
        : AppTheme.statusApproach;

    final note = lowAvailable
        ? '車輛不足'
        : fullDocks
        ? '車位已滿'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _Count(label: '可借車輛', value: available, color: availColor),
            ),
            Expanded(
              child: _Count(
                label: '可還車位',
                value: docks,
                color: docksColor,
                alignEnd: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusStadium),
          child: SizedBox(
            height: 12,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: docksColor)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: availFrac,
                  child: ColoredBox(color: availColor),
                ),
              ],
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(
            note,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppTheme.etaArriving,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final int value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyRegular.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Text(
          '$value',
          style: AppTextStyles.heading1.copyWith(
            fontSize: 32,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
