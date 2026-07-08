import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';

class RouteTimeline extends StatelessWidget {
  const RouteTimeline({
    required this.sections,
    required this.totalDuration,
    this.canvasHeight = 240,
    super.key,
  });

  final List<PlanSection> sections;
  final int totalDuration;
  final double canvasHeight;

  static Color _modeColor(String mode, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (mode.toLowerCase()) {
      case 'rail':
        return AppTheme.trainRangecar;
      case 'subway':
        return AppTheme.mrtBL;
      case 'bus':
        return cs.tertiary;
      case 'tram':
        return AppTheme.statusArriving;
      case 'ferry':
        return AppTheme.ferryBlue;
      default:
        return cs.onSurfaceVariant;
    }
  }

  double _segmentHeight(PlanSection s) {
    if (totalDuration == 0) return 32;
    final ratio = s.travelSummary.duration / totalDuration;
    return (ratio * canvasHeight).clamp(32, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: sections.map((s) {
          final h = _segmentHeight(s);
          final color = _modeColor(s.transport.mode, context);
          return _Segment(
            section: s,
            height: h,
            color: color,
          );
        }).toList(),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.section,
    required this.height,
    required this.color,
  });

  final PlanSection section;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _timeHHmm(section.departure.time),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _VerticalLine(color: color, height: height),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.circle, size: 8, color: color),
                const SizedBox(height: 4),
                Text(
                  section.transport.shortName.isNotEmpty
                      ? section.transport.shortName
                      : section.transport.mode,
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _timeHHmm(String iso) {
    if (iso.length >= 16) return iso.substring(11, 16);
    return iso;
  }
}

class _VerticalLine extends StatelessWidget {
  const _VerticalLine({required this.color, required this.height});
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(width: 2, height: height, color: color);
  }
}
