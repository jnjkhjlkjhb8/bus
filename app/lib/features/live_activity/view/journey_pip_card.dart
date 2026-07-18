import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_state.dart';

/// Compact card rendered as the whole UI while Android PiP is active.
class JourneyPipCard extends StatelessWidget {
  const JourneyPipCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<JourneySessionBloc>().state;
    final leg = s.currentLeg;
    // done keeps legs populated, so currentLeg alone can't detect a finished
    // journey — without the phase guard the card would show stale riding data.
    if (leg == null || s.phase == JourneyPhase.done) {
      return const SizedBox.shrink();
    }
    final waiting = s.phase == JourneyPhase.waiting;
    final names = [...leg.stopNames, leg.alightStop];
    final nextName = !waiting && s.nextStopIndex < names.length
        ? names[s.nextStopIndex]
        : leg.boardStop;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              waiting ? '下一班 ${leg.routeLabel}' : leg.routeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    waiting ? '於 $nextName 上車' : '下一站 $nextName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (waiting && s.eta != null)
                  Text(
                    '${s.eta!.inMinutes}分',
                    style: AppTextStyles.memo.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontFeatures: AppTextStyles.tabularFigures,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
