import 'dart:math';
import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/timeline_stop.dart';

double haversineSegmentHeight(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final km = r * 2 * atan2(sqrt(a), sqrt(1 - a));
  return max(64, km * 600.0);
}

class RouteStopItem extends StatelessWidget {
  const RouteStopItem({
    required this.stop,
    required this.segmentHeight,
    super.key,
    this.vehicleProgress,
    this.isFirst = false,
    this.isLast = false,
  });

  final TimelineStop stop;
  final double segmentHeight;
  final double? vehicleProgress;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color dotColor;
    if (stop.state == TimelineStopState.arriving) {
      dotColor = AppTheme.statusArriving;
    } else if (stop.active) {
      dotColor = cs.primary;
    } else {
      dotColor = cs.outline;
    }

    final lineColor = stop.active ? cs.primary : cs.outline;

    return SizedBox(
      height: segmentHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            height: segmentHeight,
            child: CustomPaint(
              painter: _SegmentPainter(
                lineColor: lineColor,
                dotColor: dotColor,
                vehicleBarColor: AppTheme.trainRangecar,
                vehicleProgress: vehicleProgress,
                isFirst: isFirst,
                isLast: isLast,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.name,
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (stop.primaryTime != null)
                    Text(
                      stop.primaryTime!,
                      style: AppTextStyles.memo.copyWith(
                        fontSize: 13,
                        color: cs.onSurface,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (stop.state == TimelineStopState.arriving)
            const Padding(
              padding: EdgeInsets.only(top: 12, right: 8),
              child: Text(
                '進站中',
                style: TextStyle(
                  color: AppTheme.statusArriving,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (stop.state == TimelineStopState.approaching)
            const Padding(
              padding: EdgeInsets.only(top: 12, right: 8),
              child: Text(
                '即將進站',
                style: TextStyle(
                  color: AppTheme.statusApproach,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  const _SegmentPainter({
    required this.lineColor,
    required this.dotColor,
    required this.vehicleBarColor,
    required this.vehicleProgress,
    required this.isFirst,
    required this.isLast,
  });

  final Color lineColor;
  final Color dotColor;
  final Color vehicleBarColor;
  final double? vehicleProgress;
  final bool isFirst;
  final bool isLast;

  static const _cx = 24.0;
  static const _dotY = 20.0;
  static const _dotR = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    if (!isFirst) {
      canvas.drawLine(
        const Offset(_cx, 0),
        const Offset(_cx, _dotY - _dotR),
        linePaint,
      );
    }
    if (!isLast) {
      canvas.drawLine(
        const Offset(_cx, _dotY + _dotR),
        Offset(_cx, size.height),
        linePaint,
      );
    }

    canvas.drawCircle(
      const Offset(_cx, _dotY),
      _dotR,
      Paint()..color = dotColor,
    );

    if (vehicleProgress != null && !isLast) {
      const lineStart = _dotY + _dotR;
      final lineEnd = size.height;
      final barY = lineStart + (lineEnd - lineStart) * vehicleProgress!;
      canvas.drawLine(
        Offset(_cx - 14, barY),
        Offset(_cx + 14, barY),
        Paint()
          ..color = vehicleBarColor
          ..strokeWidth = 6.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SegmentPainter old) =>
      old.vehicleProgress != vehicleProgress ||
      old.lineColor != lineColor ||
      old.dotColor != dotColor ||
      old.vehicleBarColor != vehicleBarColor;
}
