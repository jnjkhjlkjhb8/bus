part of '../view/go_screen.dart';

/// Destination label for the sheet header: the last section carrying a place
/// name (the trailing walk often ends on an unnamed coordinate), else a
/// generic fallback so the header always has both ends of the arrow.
String _lastNamedArrival(List<PlanSection> sections) {
  for (final section in sections.reversed) {
    if (section.arrival.name.isNotEmpty) return section.arrival.name;
  }
  return '目的地';
}

class _NavHeader extends StatelessWidget {
  const _NavHeader({required this.route, required this.activeLeg});

  final PlanRoute route;
  final int activeLeg;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final section = route.sections[activeLeg];
    final instruction = isWalk(section)
        ? '步行前往${section.arrival.name}'
        : '搭乘${sectionLabel(section)}';
    final remaining = section.intermediateStops.length;
    final headsign = section.transport.headsign.isEmpty
        ? section.arrival.name
        : section.transport.headsign;
    final sub = isWalk(section)
        ? '約 ${sectionMinutes(section)} 分'
        : '往$headsign · 剩 $remaining 站';
    final arrival = formatClock(route.endTime);
    return Container(
      decoration: BoxDecoration(
        color: cs.brightness == Brightness.light
            ? Colors.white
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        boxShadow: AppShadows.floating,
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(sectionIcon(section), color: cs.onSurface, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  instruction,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (arrival.isNotEmpty) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  arrival,
                  style: AppTextStyles.heading2.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    fontFeatures: AppTextStyles.tabularFigures,
                  ),
                ),
                Text(
                  '預計抵達',
                  style: AppTextStyles.bodyVerySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NavSheet extends StatelessWidget {
  const _NavSheet({
    required this.controller,
    required this.route,
    required this.activeLeg,
    required this.onAdvance,
    required this.onEnd,
  });

  final SheetController controller;
  final PlanRoute route;
  final int activeLeg;
  final VoidCallback onAdvance;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sections = route.sections;
    final progress = sections.isEmpty
        ? 0.0
        : ((activeLeg + 1) / sections.length).clamp(0.0, 1.0);
    // The leading walk departs the user's live location (no place name) and the
    // final walk ends on a bare destination coordinate (no place name either);
    // fall back so the header never renders a lone arrow.
    final origin = sections.isEmpty || sections.first.departure.name.isEmpty
        ? '目前位置'
        : sections.first.departure.name;
    final dest = _lastNamedArrival(sections);
    final isLast = activeLeg >= sections.length - 1;
    return SheetViewport(
      child: SheetExitGestureDetector(
        onExit: onEnd,
        child: Sheet(
          controller: controller,
          initialOffset: const SheetOffset.proportionalToViewport(0.45),
          snapGrid: const SheetSnapGrid(
            snaps: [
              SheetOffset.proportionalToViewport(0.28),
              SheetOffset.proportionalToViewport(0.45),
              SheetOffset.proportionalToViewport(1),
            ],
          ),
          scrollConfiguration: const SheetScrollConfiguration(),
          decoration: MaterialSheetDecoration(
            size: SheetSize.stretch,
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusBottomSheet),
            ),
            clipBehavior: Clip.antiAlias,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetDragHandle(),
              _NavSheetHeader(
                origin: origin,
                dest: dest,
                progress: progress,
                activeLeg: activeLeg,
                total: sections.length,
                arrival: formatClock(route.endTime),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                  children: [
                    for (final (i, s) in sections.indexed)
                      _StepRow(
                        section: s,
                        isFirst: i == 0,
                        isLast: i == sections.length - 1,
                        status: i < activeLeg
                            ? _StepStatus.done
                            : i == activeLeg
                            ? _StepStatus.active
                            : _StepStatus.upcoming,
                      ),
                  ],
                ),
              ),
              _NavFooter(onAdvance: onAdvance, onEnd: onEnd, isLast: isLast),
            ],
          ),
        ),
      ),
    );
  }
}

/// Board / alight controls driven by the [JourneySessionBloc], shown inside the
/// active-navigation sheet. Waiting → 我上車了 (+ static 車來了 banner when the
/// bus is due); riding → 我下車了 with a remaining-stops caption. Rendered as a
/// standalone widget (not a private helper) so it can be pumped in isolation.
///
/// Two state machines advance independently by design: PlanBloc's step list
/// (完成此段 → activeLegIndex over all sections) and JourneySessionBloc
/// (我上車了/我下車了 over transit legs). They reconcile only at journey end
/// (done-listener / last-leg advance); mid-journey drift between them is
/// expected, not a bug.
class JourneyControls extends StatelessWidget {
  const JourneyControls({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocListener<JourneySessionBloc, JourneySessionState>(
      // One medium tap on the false→true edge of suggestBoarding; the banner
      // itself is static (no animation) per the design invariants.
      listenWhen: (p, c) => !p.suggestBoarding && c.suggestBoarding,
      listener: (context, _) => HapticFeedback.mediumImpact(),
      child: BlocBuilder<JourneySessionBloc, JourneySessionState>(
        builder: (context, state) {
          switch (state.phase) {
            case JourneyPhase.waiting:
              return _waiting(context, cs, state);
            case JourneyPhase.riding:
              return _riding(context, cs, state);
            case JourneyPhase.idle:
            case JourneyPhase.done:
              return const SizedBox.shrink();
          }
        },
      ),
    );
  }

  Widget _waiting(
    BuildContext context,
    ColorScheme cs,
    JourneySessionState state,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.suggestBoarding) ...[
          const _DueCue(),
          const SizedBox(height: 10),
        ],
        _SheetButton(
          label: '我上車了',
          onTap: () =>
              context.read<JourneySessionBloc>().add(const BoardConfirmed()),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _riding(
    BuildContext context,
    ColorScheme cs,
    JourneySessionState state,
  ) {
    final leg = state.currentLeg;
    final remaining = leg == null
        ? 0
        : (leg.stopLocations.length - state.nextStopIndex).clamp(
            0,
            leg.stopLocations.length,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (leg != null) ...[
          Text(
            '於 ${leg.alightStop} 下車・剩 $remaining 站',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SheetButton(
          label: '我下車了',
          onTap: () =>
              context.read<JourneySessionBloc>().add(const AlightConfirmed()),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Sheet action button. [filled] → ink primary; otherwise a hairline-outlined
/// secondary. Both share the sheet's button radius and 50 px height so the
/// primary / secondary pair reads as one control stack.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    this.filled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: double.infinity,
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? cs.onSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          border: filled
              ? null
              : Border.all(color: cs.outlineVariant, width: 1.5),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyRegular.copyWith(
            fontWeight: FontWeight.w700,
            color: filled ? cs.surface : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Static "the bus is here" cue. A quiet surface-highlight pill with a solid
/// ink dot — deliberately *not* a filled slab and *not* pulsing, per the
/// calm-confidence and no-pulse design invariants.
class _DueCue extends StatelessWidget {
  const _DueCue();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.brightness == Brightness.light
            ? AppTheme.surfaceHighlightLight
            : AppTheme.surfaceHighlightDark,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: cs.onSurface,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '車來了——上車了嗎？',
            style: AppTextStyles.bodyRegular.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

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
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              duration: reduce ? Duration.zero : AppMotion.medium,
              curve: AppMotion.easeOut,
              tween: Tween<double>(end: progress),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: cs.outlineVariant,
                valueColor: AlwaysStoppedAnimation<Color>(cs.onSurface),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '第 ${activeLeg + 1} / $total 段',
                style: AppTextStyles.bodyVerySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (arrival.isNotEmpty)
                Text(
                  '抵達 $arrival',
                  style: AppTextStyles.bodyVerySmall.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontFeatures: AppTextStyles.tabularFigures,
                  ),
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
class _NavFooter extends StatelessWidget {
  const _NavFooter({
    required this.onAdvance,
    required this.onEnd,
    required this.isLast,
  });

  final VoidCallback onAdvance;
  final VoidCallback onEnd;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 12 + bottomInset),
      child: BlocBuilder<JourneySessionBloc, JourneySessionState>(
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
                label: isLast ? '完成行程' : '完成此段，前往下一段',
                onTap: onAdvance,
                filled: !hasPhaseAction,
              ),
              const SizedBox(height: 4),
              Pressable(
                onTap: onEnd,
                semanticLabel: '結束導航',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '結束導航',
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
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
  });

  final PlanSection section;
  final _StepStatus status;
  final bool isFirst;
  final bool isLast;

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
              ? (isLast ? '抵達目的地' : '步行')
              : '步行至 ${section.arrival.name}')
        : '${sectionLabel(section)} → ${section.arrival.name}';
    // Walk rows carry no boarding line; the right-hand minutes already state
    // the duration, so a "約 N 分" subtitle would only repeat it.
    final stops = section.intermediateStops.length;
    final subtitle = walk ? null : '${section.departure.name} 上車 · $stops 站';
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
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: EdgeInsets.only(top: topPad),
            child: Text(
              '${sectionMinutes(section)} 分',
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
