part of '../view/go_screen.dart';

/// Sheet header: origin → destination, an animated progress bar that tracks the
/// spine, and a segment counter paired with the arrival clock so the sheet
/// reads on its own without the map card.
class _NavSheetHeader extends StatelessWidget {
  const _NavSheetHeader({
    required this.origin,
    required this.dest,
    required this.progress,
    required this.activeLeg,
    required this.total,
    required this.arrival,
  });

  final String origin;
  final String dest;
  final double progress;
  final int activeLeg;
  final int total;
  final String arrival;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  origin,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyRegular.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              ),
              Flexible(
                child: Text(
                  dest,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyRegular.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            duration: reduce ? Duration.zero : AppMotion.medium,
            curve: AppMotion.easeOut,
            tween: Tween<double>(end: progress),
            builder: (context, value, _) => AppProgressBar(
              value: value,
              borderRadius: 3,
              color: cs.onSurface,
              backgroundColor: cs.outlineVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppI18n.of(context).legProgress(activeLeg + 1, total),
                style: AppTextStyles.bodyVerySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (arrival.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppI18n.of(context).goArriveLabel,
                      style: AppTextStyles.bodyVerySmall.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      arrival,
                      style: AppTextStyles.timeValue(
                        size: AppTextStyles.bodyVerySmall.fontSize,
                        color: cs.onSurface,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pinned action zone at the sheet foot (always thumb-reachable). The board /
/// alight control owns the filled primary during a transit leg; on walk legs
/// (no phase action) 完成此段 becomes the primary instead of a muted secondary.
///
/// When the autopilot has a live GPS fix ([showManualControls] false) it
/// drives progression on its own, so only the always-present 結束導航 abort
/// shows — the board/alight and advance controls would be redundant (and
/// tempting to mis-tap) while GPS is already doing the work. They reappear
/// the moment GPS drops (no permission / location services off).
class _NavFooter extends StatelessWidget {
  const _NavFooter({
    required this.onAdvance,
    required this.onEnd,
    required this.isLast,
    required this.showManualControls,
  });

  final VoidCallback onAdvance;
  final VoidCallback onEnd;
  final bool isLast;
  final bool showManualControls;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final endButton = Pressable(
      onTap: onEnd,
      semanticLabel: AppI18n.of(context).goEndNavigation,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          AppI18n.of(context).goEndNavigation,
          style: AppTextStyles.bodyRegular.copyWith(
            color: cs.error,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 12 + bottomInset),
      child: !showManualControls
          ? Column(mainAxisSize: MainAxisSize.min, children: [endButton])
          : BlocBuilder<JourneySessionBloc, JourneySessionState>(
              buildWhen: (p, c) => p.phase != c.phase,
              builder: (context, state) {
                final hasPhaseAction =
                    state.phase == JourneyPhase.waiting ||
                    state.phase == JourneyPhase.riding;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const JourneyControls(),
                    _SheetButton(
                      label: isLast
                          ? AppI18n.of(context).goFinishJourney
                          : AppI18n.of(context).goFinishLeg,
                      onTap: onAdvance,
                      filled: !hasPhaseAction,
                    ),
                    const SizedBox(height: 4),
                    endButton,
                  ],
                );
              },
            ),
    );
  }
}

enum _StepStatus { done, active, upcoming }

/// One segment on the Living Line. The spine to the left threads every segment
/// into a single route: solid ink behind the legs already travelled, the active
/// leg's own line colour ahead of it, a hairline for what's upcoming, dashed
/// for walks (echoing the map's dotted-walk polylines). The active segment is
/// the hero — a larger, line-coloured node and heavier text.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.section,
    required this.status,
    required this.isFirst,
    required this.isLast,
    this.waitMinutes = 0,
  });

  final PlanSection section;
  final _StepStatus status;
  final bool isFirst;
  final bool isLast;

  /// Scheduled wait before this leg departs; 0 hides the line.
  final int waitMinutes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = status == _StepStatus.active;
    final done = status == _StepStatus.done;
    final walk = isWalk(section);
    // Transit identity colour for the active node (bus resolves to ink); the
    // line below the active node inherits it as the you-are-here → next trace.
    final accent = transitColor(section.transport, cs);
    final lineColor = done
        ? cs.onSurface
        : active
        ? accent
        : cs.outlineVariant;

    // The final walk lands on an unnamed destination coordinate; without a name
    // "步行至 " trails off, so label it as the arrival instead.
    final title = walk
        ? (section.arrival.name.isEmpty
              ? (isLast
                    ? AppI18n.of(context).goArriveDestination
                    : AppI18n.of(context).goWalk)
              : AppI18n.of(context).walkTo(section.arrival.name))
        : '${sectionLabel(AppI18n.of(context), section)} → '
              '${section.arrival.name}';
    // Walk rows carry no boarding line; the right-hand minutes already state
    // the duration, so a "約 N 分" subtitle would only repeat it.
    final stops = section.intermediateStops.length;
    final subtitle = walk
        ? null
        : AppI18n.of(context).boardAt(section.departure.name, stops);
    final titleColor = done
        ? cs.onSurface.withValues(alpha: 0.5)
        : cs.onSurface;
    final subColor = done
        ? cs.onSurfaceVariant.withValues(alpha: 0.5)
        : cs.onSurfaceVariant;
    final topPad = active ? 5.0 : 3.0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Spine(
            status: status,
            walk: walk,
            isLast: isLast,
            icon: done ? Icons.check_rounded : sectionIcon(section),
            accent: accent,
            lineColor: lineColor,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: topPad, bottom: active ? 22 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (active
                                ? AppTextStyles.bodyLarge
                                : AppTextStyles.bodyRegular)
                            .copyWith(
                              color: titleColor,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(color: subColor),
                    ),
                  ],
                  // Waiting is stated on the leg it delays, not folded into the
                  // walk that got the rider here; it takes the row's own done
                  // dimming so a finished transfer recedes with its leg.
                  if (waitMinutes > 0) ...[
                    const SizedBox(height: 2),
                    _WaitLine(minutes: waitMinutes, color: subColor),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: EdgeInsets.only(top: topPad),
            child: Text(
              AppI18n.of(context).minutesValue(sectionMinutes(section)),
              style: AppTextStyles.bodyRegular.copyWith(
                fontWeight: FontWeight.w700,
                color: active
                    ? cs.onSurface
                    : done
                    ? cs.onSurfaceVariant.withValues(alpha: 0.5)
                    : cs.onSurfaceVariant,
                fontFeatures: AppTextStyles.tabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The node + connecting line for one [_StepRow]. Node sits flush at the row
/// top so consecutive rows' lines meet with no gap; the line fills the rest of
/// the (IntrinsicHeight) row down to the next node.
class _Spine extends StatelessWidget {
  const _Spine({
    required this.status,
    required this.walk,
    required this.isLast,
    required this.icon,
    required this.accent,
    required this.lineColor,
  });

  final _StepStatus status;
  final bool walk;
  final bool isLast;
  final IconData icon;
  final Color accent;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = status == _StepStatus.active;
    final done = status == _StepStatus.done;
    final size = active ? 34.0 : 26.0;

    final Color nodeColor;
    final Color iconColor;
    Border? border;
    if (done) {
      nodeColor = cs.onSurface;
      iconColor = cs.surface;
    } else if (active) {
      nodeColor = accent;
      iconColor = accent.computeLuminance() > 0.5 ? cs.onSurface : Colors.white;
    } else {
      nodeColor = cs.surface;
      iconColor = cs.onSurfaceVariant;
      border = Border.all(color: cs.outlineVariant, width: 1.5);
    }

    return SizedBox(
      width: 34,
      child: Column(
        children: [
          AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AppMotion.medium,
            curve: AppMotion.easeOut,
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: nodeColor,
              shape: BoxShape.circle,
              border: border,
              boxShadow: active ? AppShadows.floating : null,
            ),
            child: Icon(icon, size: active ? 18 : 14, color: iconColor),
          ),
          if (!isLast)
            Expanded(
              child: CustomPaint(
                size: const Size(34, double.infinity),
                painter: _ConnectorPainter(color: lineColor, dashed: walk),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vertical spine line, centered in its box. Dashed for walk segments to match
/// the map's dotted-walk polylines.
class _ConnectorPainter extends CustomPainter {
  const _ConnectorPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    if (!dashed) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      return;
    }
    const dash = 3.0;
    const gap = 5.0;
    for (var y = 0.0; y < size.height; y += dash + gap) {
      final end = (y + dash).clamp(0.0, size.height);
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
    }
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) =>
      old.color != color || old.dashed != dashed;
}
