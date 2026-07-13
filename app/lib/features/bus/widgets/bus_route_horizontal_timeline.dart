part of '../view/bus_route_screen.dart';

const _arrowSize = 30.0;
const _pingBox = 48.0;

class _HorizontalRouteTimeline extends StatelessWidget {
  const _HorizontalRouteTimeline({
    required this.stops,
    required this.vehicles,
    required this.direction,
    required this.controller,
    required this.flashStopUid,
  });

  final List<TimelineStop> stops;
  final List<_BusVehicle> vehicles;
  final int direction;
  final ScrollController controller;
  /// The stop briefly highlighted after its map marker was tapped.
  final String? flashStopUid;

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
      height: 148,
      child: ListView.builder(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: stops.length,
        itemBuilder: (context, i) {
          final stop = stops[i];
          // A marker-tap flash reads the same as the live/active stop.
          final isEmphasised = stop.active || stop.uid == flashStopUid;
          final prevStop = i > 0 ? stops[i - 1] : null;
          final nextStop = i < stops.length - 1 ? stops[i + 1] : null;
          final isFirst = i == 0;
          final isLast = i == stops.length - 1;

          final leftIsBuffer = stop.isBuffer && i > 0 && stops[i - 1].isBuffer;
          final rightIsBuffer =
              stop.isBuffer && nextStop != null && nextStop.isBuffer;

          // Fare zone: only the 緩衝區 (buffer) run gets a band. Contiguous
          // buffer stops render one connected strip with rounded ends and a
          // single 緩衝區 label at the run's head; every other stop draws none.
          final showBand = stop.isBuffer;
          final isBandStart =
              showBand && (prevStop == null || !prevStop.isBuffer);
          final isBandEnd =
              showBand && (nextStop == null || !nextStop.isBuffer);

          final vehicle = _vehicleBetween(stop.uid, nextStop?.uid);

          var dotColor = cs.outline;
          if (stop.state == TimelineStopState.arriving) {
            dotColor = AppTheme.statusArriving;
          } else if (stop.state == TimelineStopState.approaching) {
            dotColor = AppTheme.statusApproach;
          } else if (isEmphasised) {
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
                      surfaceColor: cs.surface,
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

                if (stop.state == TimelineStopState.approaching)
                  const Positioned(
                    left: 60 - _pingBox / 2,
                    top: 52 - _pingBox / 2,
                    width: _pingBox,
                    height: _pingBox,
                    child: IgnorePointer(
                      child: _ApproachingPing(color: AppTheme.statusApproach),
                    ),
                  ),

                if (vehicle != null && !isLast)
                  Positioned(
                    left: 60 + 60 * vehicle.progress - _arrowSize / 2,
                    top: 52 - _arrowSize / 2,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.22),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: SizedBox.square(
                          dimension: _arrowSize,
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: cs.onPrimary,
                          ),
                        ),
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
                  top: 76,
                  left: 4,
                  right: 4,
                  child: _buildEtaLabel(context, stop, cs),
                ),

                if (showBand)
                  Positioned(
                    top: 104,
                    left: isBandStart ? 5 : 0,
                    right: isBandEnd ? 5 : 0,
                    height: 18,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(isBandStart ? 9 : 0),
                          right: Radius.circular(isBandEnd ? 9 : 0),
                        ),
                      ),
                    ),
                  ),

                if (isBandStart)
                  Positioned(
                    top: 124,
                    left: 8,
                    right: 0,
                    child: Text(
                      '緩衝區',
                      style: AppTextStyles.bodyVerySmall.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
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
    switch (timelineEtaLabel(stop)) {
      case TimelineEtaLabel.arriving:
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
      case TimelineEtaLabel.approaching:
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
      case TimelineEtaLabel.countdown:
      case TimelineEtaLabel.countdownSoon:
        final isArrivingSoon =
            timelineEtaLabel(stop) == TimelineEtaLabel.countdownSoon;
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
      case TimelineEtaLabel.none:
        return const SizedBox.shrink();
    }
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
    required this.surfaceColor,
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

  /// Surface behind the timeline; fills the hollow centre of each stop dot so
  /// the ring reads correctly in both light and dark themes.
  final Color surfaceColor;
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
    // Butt caps (not round) so each cell's half-segments abut the neighbours
    // into one continuous rail instead of reading as separate rounded stubs.
    final paintLineLeft = Paint()
      ..color = isLeftActive ? activeColor : lineColor.withValues(alpha: 0.4)
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.butt;

    final paintLineRight = Paint()
      ..color = isRightActive ? activeColor : lineColor.withValues(alpha: 0.4)
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.butt;

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

    // Every stop is a plain hollow dot; the live state (進站中 green, 即將進站
    // amber) is carried by the ring colour, and the approaching stop's radar
    // ping is drawn as an animated widget in the Stack above — no static halo.
    canvas
      ..drawCircle(
        Offset(cx, cy),
        7,
        Paint()..color = surfaceColor,
      )
      ..drawCircle(
        Offset(cx, cy),
        7,
        borderPaint..color = dotColor,
      );

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
      old.surfaceColor != surfaceColor ||
      old.activeColor != activeColor ||
      old.vehicleProgress != vehicleProgress ||
      old.vehiclePlate != vehiclePlate ||
      old.vehicleColor != vehicleColor ||
      old.isLeftActive != isLeftActive ||
      old.isRightActive != isRightActive ||
      old.stopState != stopState ||
      old.isActiveStop != isActiveStop;
}

/// The 即將進站 radar cue: a stroked ring expands out from the stop dot and
/// fades, mirroring the home screen's locate ping ([AppMotion.easeOut]). It
/// loops while the stop stays approaching, with a second ring half a cycle out
/// of phase so the radar reads continuous. Reduce-motion draws one static ring.
class _ApproachingPing extends StatefulWidget {
  const _ApproachingPing({required this.color});

  final Color color;

  @override
  State<_ApproachingPing> createState() => _ApproachingPingState();
}

class _ApproachingPingState extends State<_ApproachingPing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return CustomPaint(
        painter: _PingPainter(color: widget.color, phases: const [0.55]),
      );
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => CustomPaint(
        painter: _PingPainter(
          color: widget.color,
          phases: [_ctrl.value, (_ctrl.value + 0.5) % 1.0],
        ),
      ),
    );
  }
}

class _PingPainter extends CustomPainter {
  const _PingPainter({required this.color, required this.phases});

  final Color color;
  final List<double> phases;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (final t in phases) {
      // Grows from the 7px dot edge outward, fading as it expands.
      final radius = 7 + AppMotion.easeOut.transform(t) * 17;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: (1 - t) * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_PingPainter old) =>
      old.color != color ||
      old.phases.length != phases.length ||
      old.phases.first != phases.first;
}
