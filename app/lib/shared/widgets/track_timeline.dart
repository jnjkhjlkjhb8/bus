import 'package:flutter/material.dart';

/// Vertical railway-style timeline used in bus/train detail pages.
/// Each stop has a circle on the left track and
/// `stationName` + `arrivalTime` / `departureTime` on the right.
class TrackTimeline extends StatelessWidget {
  const TrackTimeline({
    required this.stops,
    super.key,
    this.trackColor,
    this.passedOpacity = 0.35,
  });

  final List<TrackStop> stops;
  final Color? trackColor;
  final double passedOpacity;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tc = trackColor ?? cs.outlineVariant;

    return Column(
      children: List.generate(stops.length, (i) {
        final stop = stops[i];
        final isFirst = i == 0;
        final isLast = i == stops.length - 1;
        return Opacity(
          opacity: stop.passed ? passedOpacity : 1.0,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Track column ──────────────────────────────────────────
                SizedBox(
                  width: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (!isFirst)
                        Positioned(
                          top: 0,
                          left: 9,
                          child: Container(
                            width: 6,
                            height: 20,
                            color: tc,
                          ),
                        ),
                      if (!isLast)
                        Positioned(
                          top: 20,
                          bottom: 0,
                          left: 9,
                          child: Container(
                            width: 6,
                            color: tc,
                          ),
                        ),
                      Positioned(
                        top: 13,
                        left: 5,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.surface,
                            border: Border.all(color: tc, width: 3.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // ── Stop info ─────────────────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.stationName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: stop.current
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: cs.onSurface,
                          ),
                        ),
                        if (stop.arrivalTime != null ||
                            stop.departureTime != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              [
                                if (stop.arrivalTime != null) stop.arrivalTime!,
                                if (stop.departureTime != null)
                                  stop.departureTime!,
                              ].join('  '),
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (stop.etaMinutes != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${stop.etaMinutes} 分',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class TrackStop {
  const TrackStop({
    required this.stationName,
    this.arrivalTime,
    this.departureTime,
    this.etaMinutes,
    this.current = false,
    this.passed = false,
  });

  final String stationName;
  final String? arrivalTime;
  final String? departureTime;
  final int? etaMinutes;
  final bool current;
  final bool passed;
}
