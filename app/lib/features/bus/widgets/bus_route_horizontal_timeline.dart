part of '../view/bus_route_screen.dart';

const _busSpriteSize = 44.0;

class _HorizontalRouteTimeline extends StatelessWidget {
  const _HorizontalRouteTimeline({
    required this.stops,
    required this.vehicles,
    required this.direction,
  });

  final List<TimelineStop> stops;
  final List<_BusVehicle> vehicles;
  final int direction;

  _BusVehicle? _vehicleBetween(String currentUid, String? nextUid) {
    if (nextUid == null) return null;
    for (final v in vehicles) {
      if (v.afterStopUid == currentUid) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: stops.length,
        itemBuilder: (context, i) {
          final stop = stops[i];
          final nextStop = i < stops.length - 1 ? stops[i + 1] : null;
          final isFirst = i == 0;
          final isLast = i == stops.length - 1;

          final leftIsBuffer = stop.isBuffer && i > 0 && stops[i - 1].isBuffer;
          final rightIsBuffer =
              stop.isBuffer && nextStop != null && nextStop.isBuffer;

          final vehicle = _vehicleBetween(stop.uid, nextStop?.uid);

          var dotColor = cs.outline;
          if (stop.state == TimelineStopState.arriving) {
            dotColor = AppTheme.statusArriving;
          } else if (stop.state == TimelineStopState.approaching) {
            dotColor = AppTheme.statusApproach;
          } else if (stop.active) {
            dotColor = cs.primary;
          }

          return SizedBox(
            width: 120,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: CustomPaint(
                    painter: _HorizontalTimelinePainter(
                      isFirst: isFirst,
                      isLast: isLast,
                      leftIsBuffer: leftIsBuffer,
                      rightIsBuffer: rightIsBuffer,
                      lineColor: cs.outlineVariant,
                      dotColor: dotColor,
                      activeColor: cs.primary,
                      vehicleProgress: vehicle?.progress,
                      vehiclePlate: vehicle?.plate,
                      vehicleColor: AppTheme.trainRangecar,
                      isLeftActive:
                          stop.active && (i > 0 && stops[i - 1].active),
                      isRightActive:
                          stop.active && (nextStop != null && nextStop.active),
                      stopState: stop.state,
                      isActiveStop: stop.active,
                    ),
                  ),
                ),

                if (vehicle != null && !isLast)
                  Positioned(
                    left: 60 + 60 * vehicle.progress - _busSpriteSize / 2,
                    top: 52 - _busSpriteSize / 2,
                    child: IgnorePointer(
                      child: Image.asset(
                        busSpriteAsset(90),
                        width: _busSpriteSize,
                        height: _busSpriteSize,
                      ),
                    ),
                  ),

                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Text(
                    stop.name,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: stop.active
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: stop.active ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                Positioned(
                  bottom: 12,
                  left: 4,
                  right: 4,
                  child: _buildEtaLabel(context, stop, cs),
                ),

                if (rightIsBuffer && !isLast)
                  Positioned(
                    bottom: 34,
                    left: 60,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          '緩衝區',
                          style: AppTextStyles.bodyVerySmall.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEtaLabel(
    BuildContext context,
    TimelineStop stop,
    ColorScheme cs,
  ) {
    if (stop.state == TimelineStopState.arriving) {
      return Center(
        child: Text(
          '進站中',
          style: AppTextStyles.memo.copyWith(
            color: AppTheme.statusArriving,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            fontFeatures: _tnum,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (stop.state == TimelineStopState.approaching) {
      return Center(
        child: Text(
          '即將進站',
          style: AppTextStyles.memo.copyWith(
            color: AppTheme.statusApproach,
            fontWeight: FontWeight.w700,
            fontSize: 10,
            fontFeatures: _tnum,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (stop.primaryTime != null) {
      final isArrivingSoon =
          stop.primaryTime == '0' ||
          stop.primaryTime == '1' ||
          stop.primaryTime == '2';
      final textColor = isArrivingSoon
          ? AppTheme.statusArriving
          : (stop.active ? cs.primary : cs.onSurface);
      return Center(
        child: Text(
          stop.primaryTime!,
          style: AppTextStyles.memo.copyWith(
            color: textColor,
            fontWeight: isArrivingSoon ? FontWeight.w700 : FontWeight.w600,
            fontSize: 11,
            fontFeatures: _tnum,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _HorizontalTimelinePainter extends CustomPainter {
  const _HorizontalTimelinePainter({
    required this.isFirst,
    required this.isLast,
    required this.leftIsBuffer,
    required this.rightIsBuffer,
    required this.lineColor,
    required this.dotColor,
    required this.activeColor,
    required this.vehicleProgress,
    required this.vehiclePlate,
    required this.vehicleColor,
    required this.isLeftActive,
    required this.isRightActive,
    required this.stopState,
    required this.isActiveStop,
  });

  final bool isFirst;
  final bool isLast;
  final bool leftIsBuffer;
  final bool rightIsBuffer;
  final Color lineColor;
  final Color dotColor;
  final Color activeColor;
  final double? vehicleProgress;
  final String? vehiclePlate;
  final Color vehicleColor;
  final bool isLeftActive;
  final bool isRightActive;
  final TimelineStopState stopState;
  final bool isActiveStop;

  @override
  void paint(Canvas canvas, Size size) {
    final paintLineLeft = Paint()
      ..color = isLeftActive ? activeColor : lineColor.withValues(alpha: 0.4)
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round;

    final paintLineRight = Paint()
      ..color = isRightActive ? activeColor : lineColor.withValues(alpha: 0.4)
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round;

    const cy = 52.0;
    final cx = size.width / 2;

    if (!isFirst) {
      canvas.drawLine(const Offset(0, cy), Offset(cx, cy), paintLineLeft);
    }

    if (!isLast) {
      canvas.drawLine(Offset(cx, cy), Offset(size.width, cy), paintLineRight);
    }

    if (rightIsBuffer && !isLast) {
      final mx = cx + (size.width - cx) / 2;
      final paintDotted = Paint()
        ..color = lineColor.withValues(alpha: 0.6)
        ..strokeWidth = 1.5;

      const startY = cy + 6.0;
      const endY = 70.0;
      var y = startY;
      while (y < endY) {
        canvas.drawCircle(Offset(mx, y), 1, paintDotted);
        y += 4.0;
      }
    }

    final borderPaint = Paint()
      ..color = isActiveStop ? activeColor : lineColor.withValues(alpha: 0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    if (stopState == TimelineStopState.arriving ||
        stopState == TimelineStopState.approaching) {
      canvas
        ..drawCircle(
          Offset(cx, cy),
          13,
          Paint()..color = dotColor.withValues(alpha: 0.2),
        )
        ..drawCircle(
          Offset(cx, cy),
          8,
          Paint()..color = Colors.white,
        )
        ..drawCircle(
          Offset(cx, cy),
          8,
          borderPaint..color = dotColor,
        );
    } else {
      canvas
        ..drawCircle(
          Offset(cx, cy),
          7,
          Paint()..color = Colors.white,
        )
        ..drawCircle(
          Offset(cx, cy),
          7,
          borderPaint,
        );
    }

    if (vehicleProgress != null && !isLast) {
      final vx = cx + (size.width - cx) * vehicleProgress!;
      // Vehicle body is drawn as a sprite widget in the Stack above;
      // only the plate label is painted here.
      if (vehiclePlate != null && vehiclePlate!.isNotEmpty) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: vehiclePlate,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.85),
              fontSize: 9,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter
          ..layout()
          ..paint(
            canvas,
            Offset(vx - textPainter.width / 2, cy - 18.0),
          );
      }
    }
  }

  @override
  bool shouldRepaint(_HorizontalTimelinePainter old) =>
      old.isFirst != isFirst ||
      old.isLast != isLast ||
      old.leftIsBuffer != leftIsBuffer ||
      old.rightIsBuffer != rightIsBuffer ||
      old.lineColor != lineColor ||
      old.dotColor != dotColor ||
      old.activeColor != activeColor ||
      old.vehicleProgress != vehicleProgress ||
      old.vehiclePlate != vehiclePlate ||
      old.vehicleColor != vehicleColor ||
      old.isLeftActive != isLeftActive ||
      old.isRightActive != isRightActive ||
      old.stopState != stopState ||
      old.isActiveStop != isActiveStop;
}
