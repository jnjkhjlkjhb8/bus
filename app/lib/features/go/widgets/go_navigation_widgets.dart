part of '../view/go_screen.dart';

/// Destination label for the sheet header: the last section carrying a place
/// name (the trailing walk often ends on an unnamed coordinate), else a
/// generic fallback so the header always has both ends of the arrow.
String _lastNamedArrival(AppI18n i18n, List<PlanSection> sections) {
  for (final section in sections.reversed) {
    if (section.arrival.name.isNotEmpty) return section.arrival.name;
  }
  return i18n.goDestinationFallback;
}

/// A bus leg carries the notification identity's `bus` route type (mode is a
/// fallback for pre-identity data).
bool _isBusLeg(PlanSection s) =>
    s.identity.routeType == 'bus' || s.transport.mode.toLowerCase() == 'bus';

/// A rail leg is TRA or THSR (identity route type first, transport mode as the
/// fallback for legs the planner could not resolve an identity for).
bool _isRailLeg(PlanSection s) {
  if (s.identity.routeType == 'tra' || s.identity.routeType == 'thsr') {
    return true;
  }
  return const {'tra', 'thsr', 'rail', 'train', 'highspeedtrain'}.contains(
    s.transport.mode.toLowerCase(),
  );
}

/// Material maneuver glyph for a walk step, mapped from the OSRM
/// maneuverType/modifier. Arrival shows a finish flag; an unresolved turn falls
/// back to a straight arrow so the leading slot is never empty.
IconData _maneuverIcon(PlanWalkStep step) {
  if (step.maneuverType == 'arrive') return Icons.sports_score_rounded;
  return switch (step.modifier.toLowerCase()) {
    'left' => Icons.turn_left_rounded,
    'right' => Icons.turn_right_rounded,
    'slight left' => Icons.turn_slight_left_rounded,
    'slight right' => Icons.turn_slight_right_rounded,
    'sharp left' => Icons.turn_sharp_left_rounded,
    'sharp right' => Icons.turn_sharp_right_rounded,
    'uturn' => Icons.u_turn_left_rounded,
    // depart / straight / continue / unknown.
    _ => Icons.straight_rounded,
  };
}

/// Remaining distance for a walk step, split into value + unit so the unit can
/// render smaller. ≥1km switches to 公里.
(String, String) _stepDistanceParts(AppI18n i18n, double meters) =>
    meters >= 1000
    ? ((meters / 1000).toStringAsFixed(1), i18n.goKilometres)
    : ('${meters.round()}', i18n.goMetres);

class _NavHeader extends StatelessWidget {
  const _NavHeader({
    required this.route,
    required this.activeLeg,
    required this.walkStepIndex,
  });

  final PlanRoute route;
  final int activeLeg;
  final int walkStepIndex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final section = route.sections[activeLeg];
    final walk = isWalk(section);
    // Turn-by-turn takes over whenever OSRM resolved steps for this walk;
    // otherwise fall back to the coarse 「步行前往X」 title layout.
    final steps = section.walkSteps;
    final hasSteps = walk && steps.isNotEmpty;
    final index = hasSteps ? walkStepIndex.clamp(0, steps.length - 1) : 0;
    final step = hasSteps ? steps[index] : null;
    // OSRM banner convention: while traversing step i the header announces
    // step i+1's maneuver, and the distance to it is step i's own length (a
    // maneuver sits at the START of its step). The final (arrive) step
    // announces itself; `arrived` then drops the distance for 即將抵達.
    final announced = hasSteps
        ? steps[(index + 1).clamp(0, steps.length - 1)]
        : null;
    final arrived = hasSteps && index == steps.length - 1;
    final nextStep = hasSteps && index + 2 < steps.length
        ? steps[index + 2]
        : null;

    return Container(
      // Clip so the tinted 「接著」 strip honours the card's bottom corners.
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.brightness == Brightness.light
            ? Colors.white
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        boxShadow: AppShadows.floating,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _leading(context, section, announced, reduce),
                const SizedBox(width: 12),
                Expanded(
                  child: step != null
                      ? _stepPrimary(
                          context,
                          announced!,
                          arrived ? null : step.distanceMeters,
                          index,
                          reduce,
                        )
                      : _titlePrimary(context, section, walk),
                ),
                // The right column reacts to the transit-only session phase, so
                // it watches JourneySessionBloc (phase + boarding ETA) rather
                // than PlanBloc. It always shows the time value.
                BlocBuilder<JourneySessionBloc, JourneySessionState>(
                  buildWhen: (p, c) => p.phase != c.phase || p.eta != c.eta,
                  builder: (context, js) =>
                      _headerTrailing(context, section, js, reduce),
                ),
              ],
            ),
          ),
          // 「接著」 preview: the next maneuver, so continuous short-alley turns
          // are known before the junction. Hidden when there is no next step.
          if (nextStep != null)
            _NextStrip(
              step: nextStep,
              // Distance to reach that maneuver = the announced step's length.
              distanceMeters: steps[index + 1].distanceMeters,
              reduce: reduce,
            ),
        ],
      ),
    );
  }

  Widget _leading(
    BuildContext context,
    PlanSection section,
    PlanWalkStep? step,
    bool reduce,
  ) {
    final cs = Theme.of(context).colorScheme;
    if (step == null) {
      return Icon(sectionIcon(section), color: cs.onSurface, size: 28);
    }
    final icon = _maneuverIcon(step);
    return SizedBox(
      width: 44,
      height: 44,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : AppMotion.short,
        switchInCurve: AppMotion.easeOut,
        child: Icon(
          icon,
          key: ValueKey(icon.codePoint),
          color: cs.onSurface,
          size: 36,
        ),
      ),
    );
  }

  // Walk turn-by-turn primary: distance to the announced maneuver over its
  // street sentence; a null distance means the destination is reached and only
  // 即將抵達 shows. Keyed by step index so the block fades up as one on advance.
  Widget _stepPrimary(
    BuildContext context,
    PlanWalkStep announced,
    double? metersToManeuver,
    int index,
    bool reduce,
  ) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : AppMotion.short,
      switchInCurve: AppMotion.easeOut,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: AnimatedBuilder(
          animation: anim,
          builder: (context, c) => Transform.translate(
            offset: Offset(0, (1 - anim.value) * 8),
            child: c,
          ),
          child: child,
        ),
      ),
      child: Column(
        key: ValueKey(index),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepDistanceLine(context, metersToManeuver),
          if (metersToManeuver != null) ...[
            const SizedBox(height: 2),
            Text(
              announced.instruction,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyLarge.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepDistanceLine(BuildContext context, double? metersToManeuver) {
    final cs = Theme.of(context).colorScheme;
    if (metersToManeuver == null) {
      return Text(
        AppI18n.of(context).goArrivingSoon,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.bodyLarge.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: cs.onSurface,
        ),
      );
    }
    final (value, unit) = _stepDistanceParts(
      AppI18n.of(context),
      metersToManeuver,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: value),
          TextSpan(
            text: ' $unit',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      style: AppTextStyles.timeValue(
        size: 26,
        weight: FontWeight.w700,
        height: 1.15,
        color: cs.onSurface,
      ),
    );
  }

  // Transit legs and step-less walk fallbacks share a title + subtitle layout.
  Widget _titlePrimary(BuildContext context, PlanSection section, bool walk) {
    final cs = Theme.of(context).colorScheme;
    final i18n = AppI18n.of(context);
    final headsign = section.transport.headsign.isEmpty
        ? section.arrival.name
        : section.transport.headsign;
    final String title;
    final String sub;
    if (walk) {
      title = i18n.walkToward(section.arrival.name);
      sub = i18n.aboutMinutes(sectionMinutes(section));
    } else {
      title = i18n.rideVehicle(sectionLabel(i18n, section));
      sub = i18n.towardsAndRemaining(
        headsign,
        section.intermediateStops.length,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyLarge.copyWith(
            fontSize: 17,
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
            fontSize: 13,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _headerTrailing(
    BuildContext context,
    PlanSection section,
    JourneySessionState js,
    bool reduce,
  ) {
    final cs = Theme.of(context).colorScheme;
    final waiting = js.phase == JourneyPhase.waiting;
    String value;
    String label;
    // Only the live bus countdown claims the biggest weight; clocks stay 24px.
    var big = false;
    if (waiting &&
        _isBusLeg(section) &&
        section.identity.supported &&
        js.eta != null) {
      // Ceil seconds to minutes (project rule); a due bus reads 進站中.
      final secs = js.eta!.inSeconds;
      value = secs <= 0
          ? AppI18n.of(context).etaArriving
          : AppI18n.of(context).minutesValue((secs / 60).ceil());
      label = AppI18n.of(context).goBusArriving;
      big = true;
    } else if (waiting && _isRailLeg(section)) {
      value = formatClock(section.departure.time);
      label = AppI18n.of(context).busDeparture;
    } else {
      // The active section's own arrival time; legs missing a time (e.g. a
      // trailing walk TDX left blank) fall back to the whole-route arrival.
      final sectionArrival = formatClock(section.arrival.time);
      value = sectionArrival.isNotEmpty
          ? sectionArrival
          : formatClock(route.endTime);
      label = AppI18n.of(context).goExpectedArrival;
    }
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : AppMotion.micro,
        child: Column(
          key: ValueKey('$value|$label'),
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: AppTextStyles.timeValue(
                size: big ? 28 : 24,
                weight: FontWeight.w700,
                height: 1.1,
                color: cs.onSurface,
              ),
            ),
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「接著」 preview strip under the header's main row: the next walk maneuver as
/// a small glyph + the street sentence + remaining distance. A surface-tinted
/// band with a hairline top border; content crossfades as the step advances.
class _NextStrip extends StatelessWidget {
  const _NextStrip({
    required this.step,
    required this.distanceMeters,
    required this.reduce,
  });

  final PlanWalkStep step;
  // Distance to reach [step]'s maneuver (the preceding step's length), not
  // step.distanceMeters — same banner pairing as the primary line.
  final double distanceMeters;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (dist, unit) = _stepDistanceParts(
      AppI18n.of(context),
      distanceMeters,
    );
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : AppMotion.micro,
      child: Container(
        key: ValueKey('${step.instruction}|$distanceMeters'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(
          children: [
            Text(
              AppI18n.of(context).goNext,
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Icon(_maneuverIcon(step), size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: step.instruction,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    TextSpan(text: '  $dist $unit'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 12.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavSheet extends StatelessWidget {
  const _NavSheet({
    required this.controller,
    required this.initialOffset,
    required this.route,
    required this.activeLeg,
    required this.onAdvance,
    required this.onEnd,
    required this.showManualControls,
  });

  final SheetController controller;
  final SheetOffset initialOffset;
  final PlanRoute route;
  final int activeLeg;
  final VoidCallback onAdvance;
  final VoidCallback onEnd;
  final bool showManualControls;

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
        ? AppI18n.of(context).goCurrentLocation
        : sections.first.departure.name;
    final dest = _lastNamedArrival(AppI18n.of(context), sections);
    final isLast = activeLeg >= sections.length - 1;
    return AppSheet(
      controller: controller,
      initialOffset: initialOffset,
      color: cs.surface,
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
          const DividerLine(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              children: [
                for (final (i, s) in sections.indexed)
                  _StepRow(
                    section: s,
                    waitMinutes: waitMinutesBefore(sections, i),
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
          _NavFooter(
            onAdvance: onAdvance,
            onEnd: onEnd,
            isLast: isLast,
            showManualControls: showManualControls,
          ),
        ],
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
        // The controls never render eta, so the 30 s ETA tick must not rebuild
        // them; rebuild only on the fields this subtree actually shows.
        buildWhen: (p, c) =>
            p.phase != c.phase ||
            p.suggestBoarding != c.suggestBoarding ||
            p.legIndex != c.legIndex ||
            p.nextStopIndex != c.nextStopIndex ||
            !identical(p.legs, c.legs),
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
          label: AppI18n.of(context).goBoarded,
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
            AppI18n.of(
              context,
            ).alightAtRemaining(leg.alightStop, remaining),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],
        _SheetButton(
          label: AppI18n.of(context).goAlighted,
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
        color: AppTheme.surfaceHighlight(cs.brightness),
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
            AppI18n.of(context).goVehicleArrived,
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
