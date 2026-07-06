part of '../view/go_screen.dart';

class _NavHeader extends StatelessWidget {
  const _NavHeader({required this.route, required this.activeLeg});

  final PlanRoute route;
  final int activeLeg;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final section = route.sections[activeLeg];
    final color = isWalk(section)
        ? cs.onSurfaceVariant
        : transitColor(section.transport, cs);
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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            ),
            child: Icon(
              transitIcon(section.transport.mode),
              color: Colors.white,
              size: 22,
            ),
          ),
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
    final origin = sections.isNotEmpty ? sections.first.departure.name : '';
    final dest = sections.isNotEmpty ? sections.last.arrival.name : '';
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            dest,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: AppTextStyles.bodyRegular.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: cs.outlineVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(cs.onSurface),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '第 ${activeLeg + 1} / ${sections.length} 段',
                        style: AppTextStyles.bodyVerySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    for (final (i, s) in sections.indexed)
                      _StepRow(
                        section: s,
                        status: i < activeLeg
                            ? _StepStatus.done
                            : i == activeLeg
                            ? _StepStatus.active
                            : _StepStatus.upcoming,
                      ),
                    const SizedBox(height: 16),
                    const JourneyControls(),
                    Pressable(
                      onTap: onAdvance,
                      semanticLabel: isLast ? '完成行程' : '完成此段',
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: cs.onSurface,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusButton,
                          ),
                        ),
                        child: Text(
                          isLast ? '完成行程' : '完成此段，前往下一段',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyRegular.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.surface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Pressable(
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
                    ),
                  ],
                ),
              ),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.inkLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusButton),
            ),
            child: Text(
              '車來了——上車了嗎？',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyRegular.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        _PrimaryAction(
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
        _PrimaryAction(
          label: '我下車了',
          onTap: () =>
              context.read<JourneySessionBloc>().add(const AlightConfirmed()),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Filled ink action button matching the sheet's 完成此段 control.
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: cs.onSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyRegular.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.surface,
          ),
        ),
      ),
    );
  }
}

enum _StepStatus { done, active, upcoming }

class _StepRow extends StatelessWidget {
  const _StepRow({required this.section, required this.status});

  final PlanSection section;
  final _StepStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = status == _StepStatus.active;
    final done = status == _StepStatus.done;
    final color = isWalk(section)
        ? cs.onSurfaceVariant
        : transitColor(section.transport, cs);
    final title = isWalk(section)
        ? '步行至 ${section.arrival.name}'
        : '${sectionLabel(section)} → ${section.arrival.name}';
    final stops = section.intermediateStops.length;
    final sub = isWalk(section)
        ? '約 ${sectionMinutes(section)} 分'
        : '${section.departure.name} 上車 · $stops 站';
    return Opacity(
      opacity: done ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: active ? color : cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                done
                    ? Icons.check_rounded
                    : transitIcon(section.transport.mode),
                size: 16,
                color: active ? Colors.white : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: cs.onSurface,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${sectionMinutes(section)} 分',
              style: AppTextStyles.bodyRegular.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                fontFeatures: AppTextStyles.tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
