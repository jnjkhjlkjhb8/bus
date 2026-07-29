import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';

/// In-between-stop progress card.
/// Shows:  [prevStation → nextStation] header
///         horizontal track with black notch at [progress 0..1]
///         vehicle ID below notch
class ProgressCard extends StatelessWidget {
  const ProgressCard({
    required this.fromStation,
    required this.toStation,
    required this.progress,
    required this.vehicleId,
    super.key,
  });

  final String fromStation;
  final String toStation;
  final double progress;
  final String vehicleId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                fromStation,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 12,
                color: cs.onSurfaceVariant,
              ),
              Text(
                toStation,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ProgressTrack(progress: progress, vehicleId: vehicleId),
        ],
      ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.progress, required this.vehicleId});

  final double progress;
  final String vehicleId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final notchX = (trackWidth * progress.clamp(0.0, 1.0)).clamp(
          0.0,
          trackWidth - 4,
        );
        return SizedBox(
          height: 32,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Container(height: 2, color: cs.outlineVariant),
              ),
              Positioned(
                top: 4,
                left: notchX - 2,
                child: Column(
                  children: [
                    Container(
                      width: 4,
                      height: 10,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicleId,
                      style: TextStyle(
                        fontSize: 9,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
