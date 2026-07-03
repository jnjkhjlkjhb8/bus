import 'dart:math';
import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/data/models/timeline_stop.dart';

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

class BusRouteTimeline extends StatelessWidget {
  const BusRouteTimeline({
    required this.stops,
    this.minSegmentHeight = 80.0,
    this.scrollController,
    super.key,
  });

  final List<TimelineStop> stops;
  final double minSegmentHeight;
  final ScrollController? scrollController;

  List<double> _segmentHeights(double canvasH) {
    final n = stops.length;
    if (n < 2) return [];
    final hasCoords = stops.every((s) => s.lat != null && s.lon != null);
    if (!hasCoords) {
      final h = max(minSegmentHeight, canvasH / (n - 1));
      return List.filled(n - 1, h);
    }
    final rawDists = List.generate(n - 1, (i) {
      return _haversine(
        stops[i].lat!,
        stops[i].lon!,
        stops[i + 1].lat!,
        stops[i + 1].lon!,
      );
    });
    final total = rawDists.fold<double>(0, (a, b) => a + b);
    if (total == 0) return List.filled(n - 1, minSegmentHeight);
    return rawDists
        .map((d) => max(minSegmentHeight, d / total * canvasH))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (stops.isEmpty) {
      return Center(
        child: Text(
          '無站點資料',
          style: AppTextStyles.bodyRegular.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasH = max(
          constraints.maxHeight,
          (stops.length - 1) * minSegmentHeight,
        );
        final heights = _segmentHeights(canvasH);
        final cumH = <double>[0];
        for (final h in heights) {
          cumH.add(cumH.last + h);
        }
        final totalH = cumH.last + 40.0;

        return SingleChildScrollView(
          controller: scrollController,
          child: SizedBox(
            height: totalH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = 0; i < stops.length - 1; i++)
                  Positioned(
                    left: 146,
                    top: cumH[i],
                    width: 20,
                    height: heights[i],
                    child: Container(
                      decoration: BoxDecoration(
                        color: stops[i].active
                            ? cs.primary
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                for (int i = 0; i < stops.length; i++)
                  Positioned(
                    left: 150,
                    top: cumH[i] - 6,
                    width: 12,
                    height: 12,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.primary, width: 1.5),
                      ),
                    ),
                  ),
                for (int i = 0; i < stops.length; i++)
                  Positioned(
                    top: cumH[i] - 10,
                    left: 0,
                    right: 0,
                    child: _StopRow(stop: stops[i]),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.stop});
  final TimelineStop stop;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 146,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              stop.name,
              style: AppTextStyles.bodyRegular,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _EtaLabel(stop: stop),
          ),
        ),
      ],
    );
  }
}

class _EtaLabel extends StatelessWidget {
  const _EtaLabel({required this.stop});
  final TimelineStop stop;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (stop.state == TimelineStopState.arriving) {
      return Text(
        '進站中',
        style: AppTextStyles.bodyRegular.copyWith(color: cs.error),
        textAlign: TextAlign.right,
      );
    }
    if (stop.state == TimelineStopState.approaching) {
      return Text(
        '即將進站',
        style: AppTextStyles.bodyRegular.copyWith(color: cs.primary),
        textAlign: TextAlign.right,
      );
    }
    if (stop.primaryTime != null && stop.primaryLabel != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${stop.primaryLabel} ${stop.primaryTime}',
            style: AppTextStyles.bodyRegular.copyWith(
              fontFeatures: AppTextStyles.tabularFigures,
            ),
            textAlign: TextAlign.right,
          ),
          if (stop.secondaryTime != null && stop.secondaryLabel != null)
            Text(
              '${stop.secondaryLabel} ${stop.secondaryTime}',
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
                fontFeatures: AppTextStyles.tabularFigures,
              ),
              textAlign: TextAlign.right,
            ),
        ],
      );
    }
    if (stop.primaryTime != null) {
      return Text(
        stop.primaryTime!,
        style: AppTextStyles.bodyRegular.copyWith(
          fontFeatures: AppTextStyles.tabularFigures,
        ),
        textAlign: TextAlign.right,
      );
    }
    return Text(
      '—',
      style: AppTextStyles.bodyRegular.copyWith(color: cs.onSurfaceVariant),
      textAlign: TextAlign.right,
    );
  }
}
