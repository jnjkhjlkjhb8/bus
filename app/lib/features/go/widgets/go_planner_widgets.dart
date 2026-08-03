part of '../view/go_screen.dart';

/// How the origin resolved. The field says which of the three it is instead of
/// showing the same grey AppI18n.of(context).goChooseOrigin while GPS is still working — that reads as
/// "you must pick this" when in fact nothing is required yet.
enum OriginStatus { resolving, resolved, unavailable }

/// The origin → destination pair, drawn as one block. Two hosts, two
/// elevations: [floating] over the map (where a shadow describes a real layer
/// relationship), a hairline-bordered inset card on the flat entry surface
/// (where a shadow would float over nothing).
class _ODFields extends StatelessWidget {
  const _ODFields({
    required this.origin,
    required this.onEditOrigin,
    required this.onSwap,
    required this.destination,
    this.originStatus = OriginStatus.resolved,
    this.floating = false,
    this.onEnableLocation,
  });

  final PlannedPlace? origin;
  final OriginStatus originStatus;
  final VoidCallback onEditOrigin;
  final VoidCallback onSwap;

  /// The destination row's content: a tappable summary on the map, the live
  /// search field on the entry surface.
  final Widget destination;

  final bool floating;

  /// Offered next to the origin hint when location is off, so the fix is one
  /// tap from the thing it broke.
  final VoidCallback? onEnableLocation;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final card = cs.brightness == Brightness.light
        ? Colors.white
        : cs.surfaceContainerHigh;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: floating ? card : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        boxShadow: floating ? AppShadows.floating : null,
        border: floating ? null : Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
        child: Row(
          children: [
            const _ODRail(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _OriginRow(
                    place: origin,
                    status: originStatus,
                    onTap: onEditOrigin,
                    onEnableLocation: onEnableLocation,
                  ),
                  const DividerLine(),
                  SizedBox(height: _kODRowHeight, child: destination),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Pressable(
              onTap: onSwap,
              semanticLabel: AppI18n.of(context).goSwapEndpoints,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.swap_vert_rounded,
                  size: 20,
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

const double _kODRowHeight = 48;

/// The line between the two ends — the same "living line" the rest of the app
/// draws a route with, at field scale. Each glyph centres on its own row.
class _ODRail extends StatelessWidget {
  const _ODRail();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 14,
      height: _kODRowHeight * 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: 1.5, height: 24, color: cs.outlineVariant),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: _kODRowHeight / 2 - 6),
              child: Icon(
                Icons.radio_button_checked_rounded,
                size: 13,
                color: cs.outline,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: _kODRowHeight / 2 - 8),
              child: Icon(
                Icons.location_on_rounded,
                size: 16,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginRow extends StatelessWidget {
  const _OriginRow({
    required this.place,
    required this.status,
    required this.onTap,
    this.onEnableLocation,
  });

  final PlannedPlace? place;
  final OriginStatus status;
  final VoidCallback onTap;
  final VoidCallback? onEnableLocation;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filled = place != null;
    final label = switch ((filled, status)) {
      (true, _) => place!.name,
      (false, OriginStatus.resolving) => AppI18n.of(context).goLocating,
      _ => AppI18n.of(context).goChooseOrigin,
    };
    final denied = !filled && status == OriginStatus.unavailable;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        height: _kODRowHeight,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: filled ? cs.onSurface : cs.onSurfaceVariant,
                      fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (denied && onEnableLocation != null)
                    _LocationOffHint(onTap: onEnableLocation!),
                ],
              ),
            ),
            if (filled && place!.isCurrentLocation)
              Icon(
                Icons.my_location_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

class _LocationOffHint extends StatelessWidget {
  const _LocationOffHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppI18n.of(context).goNoLocation,
          style: AppTextStyles.bodyVerySmall.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        Pressable(
          onTap: onTap,
          semanticLabel: AppI18n.of(context).goEnableLocation,
          child: Text(
            AppI18n.of(context).goEnableLocation,
            style: AppTextStyles.bodyVerySmall.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// The map phase's origin/destination card: both ends are summaries that open
/// the pushed search page, and the whole thing floats over the map.
class _PlannerHeader extends StatelessWidget {
  const _PlannerHeader({
    required this.origin,
    required this.dest,
    required this.onEditOrigin,
    required this.onEditDest,
    required this.onSwap,
  });

  final PlannedPlace? origin;
  final PlannedPlace? dest;
  final VoidCallback onEditOrigin;
  final VoidCallback onEditDest;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filled = dest != null;
    return _ODFields(
      origin: origin,
      onEditOrigin: onEditOrigin,
      onSwap: onSwap,
      floating: true,
      destination: Pressable(
        onTap: onEditDest,
        semanticLabel: filled
            ? dest!.name
            : AppI18n.of(context).goChooseDestination,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            filled ? dest!.name : AppI18n.of(context).goChooseDestination,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyLarge.copyWith(
              color: filled ? cs.onSurface : cs.onSurfaceVariant,
              fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlannerSheet extends StatelessWidget {
  const _PlannerSheet({
    required this.controller,
    required this.initialOffset,
    required this.state,
    required this.hasDestination,
    required this.timeMode,
    required this.timeAt,
    required this.routeCount,
    required this.lastRoute,
    required this.straightLineMeters,
    required this.onSelect,
    required this.onRetry,
    required this.onCancel,
    required this.onAdjustOptions,
    required this.onAdjustTime,
    required this.onToggleSave,
    super.key,
  });

  final SheetController controller;
  final SheetOffset initialOffset;
  final PlanState state;
  final bool hasDestination;
  final _TimeMode timeMode;
  final DateTime timeAt;
  final int routeCount;
  final PlanRoute? lastRoute;
  final double? straightLineMeters;
  final void Function(PlanRoute) onSelect;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onAdjustOptions;
  final VoidCallback onAdjustTime;
  final void Function(PlanRoute) onToggleSave;

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      controller: controller,
      initialOffset: initialOffset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetDragHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Row(
              children: [
                Expanded(child: _SheetTitle(state: state)),
                // The depart/arrive time chip only makes sense once a
                // destination has been queried; the saved-routes box has no
                // time context.
                if (hasDestination) ...[
                  _TimeChip(
                    mode: timeMode,
                    at: timeAt,
                    onTap: onAdjustTime,
                  ),
                  const SizedBox(width: 8),
                ],
                _OptionsButton(onTap: onAdjustOptions),
              ],
            ),
          ),
          const DividerLine(),
          Expanded(
            child: _PlannerBody(
              state: state,
              routeCount: routeCount,
              lastRoute: lastRoute,
              straightLineMeters: straightLineMeters,
              onSelect: onSelect,
              onRetry: onRetry,
              onCancel: onCancel,
              onToggleSave: onToggleSave,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.state});

  final PlanState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = state.result?.routes.length ?? 0;
    // The departure time now lives in the header time chip, so the subtitle
    // just reports the result count.
    final sub = state.status == PlanStatus.success && count > 0
        ? AppI18n.of(context).suggestionCount(count)
        : AppI18n.of(context).goPlanning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppI18n.of(context).goSuggestedRoutes,
          style: AppTextStyles.heading2.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 3),
        Text(
          sub,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _PlannerBody extends StatelessWidget {
  const _PlannerBody({
    required this.state,
    required this.routeCount,
    required this.lastRoute,
    required this.straightLineMeters,
    required this.onSelect,
    required this.onRetry,
    required this.onCancel,
    required this.onToggleSave,
  });

  final PlanState state;

  /// How many routes were asked for, so the skeleton is the shape of the answer
  /// and the real cards land without a reflow.
  final int routeCount;

  /// A saved route between the same two points, shown while waiting. Null when
  /// this trip is not one the rider has kept.
  final PlanRoute? lastRoute;

  /// Straight-line distance between the two ends, stated while waiting.
  final double? straightLineMeters;

  final void Function(PlanRoute) onSelect;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final void Function(PlanRoute) onToggleSave;

  @override
  Widget build(BuildContext context) {
    // The empty/saved-routes state now lives on the plan-entry page; this body
    // is only built once a destination exists, so it starts at the query state.
    switch (state.status) {
      case PlanStatus.initial:
      case PlanStatus.loading:
        return PlanWaitingPanel(
          routeCount: routeCount,
          lastRoute: lastRoute,
          straightLineMeters: straightLineMeters,
          onCancel: onCancel,
          onOpenLast: lastRoute == null ? null : () => onSelect(lastRoute!),
        );
      case PlanStatus.failure:
        final (title, hint) = switch (state.failure) {
          PlanFailureKind.timeout => (
            AppI18n.of(context).goPlannerSlowTitle,
            AppI18n.of(context).goPlannerSlowBody,
          ),
          PlanFailureKind.noRoute => (
            AppI18n.of(context).goNoRouteTitle,
            AppI18n.of(context).goNoRouteBody,
          ),
          PlanFailureKind.unavailable => (
            AppI18n.of(context).goUnavailableTitle,
            AppI18n.of(context).goUnavailableBody,
          ),
          _ => (
            AppI18n.of(context).goPlanFailedTitle,
            AppI18n.of(context).goPlanFailedBody,
          ),
        };
        return _GoMessage(
          icon: state.failure == PlanFailureKind.noRoute
              ? Icons.alt_route_rounded
              : Icons.cloud_off_rounded,
          title: title,
          hint: hint,
          actionLabel: AppI18n.of(context).commonRetryShort,
          onAction: onRetry,
        );
      case PlanStatus.success:
        final routes = state.result?.routes ?? const <PlanRoute>[];
        if (routes.isEmpty) {
          return _GoMessage(
            icon: Icons.alt_route_rounded,
            title: AppI18n.of(context).goNoRouteTitle,
            hint: AppI18n.of(context).goNoRouteHint,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: routes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => RouteOptionCard(
            route: routes[i],
            highlighted: i == 0,
            badge: i == 0 ? AppI18n.of(context).goBadgeFastest : null,
            isSaved: state.savedKeys.contains(routes[i].savedKey),
            onTap: () => onSelect(routes[i]),
            onToggleSave: () => onToggleSave(routes[i]),
          ),
        );
    }
  }
}

/// What the sheet shows while the router works. Three honest things: what the
/// system is doing (and roughly how long it has been at it), the route this
/// rider took last time between the same two points, and the shape of the
/// answer that is coming.
///
/// Deliberately absent: a progress bar and a stopwatch. The router reports no
/// stages, so a percentage would be invented; a counting clock only makes the
/// wait feel longer.
class PlanWaitingPanel extends StatefulWidget {
  const PlanWaitingPanel({
    required this.routeCount,
    required this.lastRoute,
    required this.onCancel,
    this.straightLineMeters,
    this.onOpenLast,
    super.key,
  });

  final int routeCount;
  final PlanRoute? lastRoute;
  final VoidCallback onCancel;

  /// As the crow flies between the two ends. The one number that is already
  /// true before the router answers, so it costs nothing to state.
  final double? straightLineMeters;

  final VoidCallback? onOpenLast;

  @override
  State<PlanWaitingPanel> createState() => _PlanWaitingState();
}

class _PlanWaitingState extends State<PlanWaitingPanel> {
  // Two one-shot timers rather than a ticking clock: the copy changes twice,
  // and nothing on screen counts seconds.
  static const _settleIn = Duration(seconds: 3);
  static const _longEnoughToOffer = Duration(seconds: 8);

  Timer? _settled;
  Timer? _long;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _settled = Timer(_settleIn, () {
      if (mounted) setState(() => _elapsed = _settleIn);
    });
    _long = Timer(_longEnoughToOffer, () {
      if (mounted) setState(() => _elapsed = _longEnoughToOffer);
    });
  }

  @override
  void dispose() {
    _settled?.cancel();
    _long?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final label = switch (_elapsed) {
      >= _longEnoughToOffer => AppI18n.of(context).goWaitingUpstream,
      >= _settleIn => AppI18n.of(context).goComparingTransfers,
      _ => AppI18n.of(context).goPlanningRoute,
    };
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: reduce ? Duration.zero : AppMotion.micro,
                  switchInCurve: AppMotion.easeOut,
                  switchOutCurve: AppMotion.easeOut,
                  child: Text(
                    label,
                    key: ValueKey(label),
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (widget.straightLineMeters != null &&
                  _elapsed < _longEnoughToOffer)
                _StraightLineReadout(meters: widget.straightLineMeters!),
              // Only offered once waiting has actually become unreasonable —
              // an escape hatch on screen from the first frame reads as a
              // warning that this is going to be slow.
              if (_elapsed >= _longEnoughToOffer)
                Pressable(
                  onTap: widget.onCancel,
                  semanticLabel: AppI18n.of(context).goCancelPlanning,
                  minTapSize: 44,
                  child: Text(
                    AppI18n.of(context).commonCancel,
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (widget.lastRoute != null)
          _LastRouteCard(
            route: widget.lastRoute!,
            onTap: widget.onOpenLast,
          ),
        _RouteSkeleton(count: widget.routeCount),
      ],
    );
  }
}

/// The distance the dotted line on the map covers, in words. It lives here
/// rather than on the map because a text pill pinned to a coordinate shakes
/// while the map pans — anything anchored to the map has to be a bitmap marker,
/// and a label is not worth that machinery.
class _StraightLineReadout extends StatelessWidget {
  const _StraightLineReadout({required this.meters});

  final double meters;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final km = meters / 1000;
    final value = km >= 10 ? km.round().toString() : km.toStringAsFixed(1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppI18n.of(context).goStraightLine,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
        Text(
          value,
          style: AppTextStyles.timeValue(
            size: AppTextStyles.bodySmall.fontSize,
            color: cs.onSurfaceVariant,
          ),
        ),
        Text(
          AppI18n.of(context).goKilometresSuffix,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The saved route between these same two points, offered while the fresh one
/// is still being computed. Framed as a memory, not a result: dashed outline,
/// its own caption, and outside the results list, because its times are from
/// whenever it was saved.
class _LastRouteCard extends StatelessWidget {
  const _LastRouteCard({required this.route, this.onTap});

  final PlanRoute route;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Pressable(
        onTap: onTap,
        semanticLabel: AppI18n.of(context).goLastRouteSemantics,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppI18n.of(context).goLastRouteTitle,
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: LegStrip(
                      sections: route.sections,
                      detailed: false,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppI18n.of(context).aboutMinutes(routeMinutes(route)),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteSkeleton extends StatelessWidget {
  const _RouteSkeleton({this.count = 3});

  /// Matched to the route-count option so the placeholder occupies the space
  /// the answer will.
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A fraction of the card's own width rather than a fixed pixel count —
    // see the identical fix on genui's `_AnswerSkeleton`.
    Widget bar(double widthFactor, double h) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        // Stretched to match RouteOptionCard's width in the results
        // ListView.separated — otherwise these shrink-wrap to their bar
        // width and the real card snaps wider the moment routes land.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < count; i++)
            _ShimmerFade(
              key: ValueKey('plan-skeleton-$i'),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(0.24, 22),
                    const SizedBox(height: 12),
                    bar(0.64, 16),
                    const SizedBox(height: 10),
                    bar(0.38, 12),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The card-scale counterpart of `ShimmerRow`: same loop, same reduce-motion
/// behaviour, wrapped around a placeholder that has real structure.
class _ShimmerFade extends StatefulWidget {
  const _ShimmerFade({required this.child, super.key});

  final Widget child;

  @override
  State<_ShimmerFade> createState() => _ShimmerFadeState();
}

class _ShimmerFadeState extends State<_ShimmerFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AppMotion.shimmerLoop,
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.45,
    end: 0.85,
  ).animate(CurvedAnimation(parent: _ctrl, curve: AppMotion.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce && _ctrl.isAnimating) {
      _ctrl.stop();
    } else if (!reduce && !_ctrl.isAnimating) {
      unawaited(_ctrl.repeat(reverse: true));
    }
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, child) =>
          Opacity(opacity: reduce ? 0.6 : _opacity.value, child: child),
      child: widget.child,
    );
  }
}

/// Trailing control in the sheet header. Opens the routing-options sheet.
class _OptionsButton extends StatelessWidget {
  const _OptionsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: AppI18n.of(context).goRouteOptions,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 18, color: cs.onSurface),
            const SizedBox(width: 6),
            Text(
              AppI18n.of(context).goOptions,
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Names the stance the cost/time weight currently expresses. The weight is a
/// solver input with no meaning to a rider, so the readout reports the choice
/// the slider's end labels promise instead of the raw number.
String _gcLabel(AppI18n i18n, double gc) => switch (gc) {
  <= 0.1 => i18n.goPrefCheapest,
  < 0.4 => i18n.goPrefCheaperLeaning,
  <= 0.6 => i18n.goPrefBalanced,
  < 0.9 => i18n.goPrefFasterLeaning,
  _ => i18n.goPrefFastest,
};

// TDX transit-mode ids the planner exposes (excludes 20:航空). Built per call
// rather than held in a const map: the names follow the rider's language.
Map<int, String> _kTransitModes(AppI18n i18n) => {
  3: i18n.modeThsr,
  4: i18n.modeTra,
  5: i18n.modeBus,
  6: i18n.modeMetro,
  7: i18n.modeLightRail,
  8: i18n.modeFerry,
  9: i18n.modeCableCar,
};
// TDX first/last-mile mode ids.
Map<int, String> _kMileModes(AppI18n i18n) => {
  0: i18n.modeWalking,
  1: i18n.modeBicycle,
  2: i18n.modeCar,
  3: i18n.modeSharedBike,
};

/// Options sheet for all TDX MaaS routing parameters. Returns the edited
/// [PlanOptions] on 套用, or null on dismiss.
Future<PlanOptions?> showOptionsSheet(
  BuildContext context, {
  required PlanOptions current,
}) {
  return showModalBottomSheet<PlanOptions>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OptionsSheet(initial: current),
  );
}

class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({required this.initial});

  final PlanOptions initial;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late PlanOptions _o = widget.initial;

  void _toggleMode(int id) {
    final modes = _o.transitModes.toList();
    if (modes.contains(id)) {
      if (modes.length == 1) return; // keep at least one mode selected
      modes.remove(id);
    } else {
      modes.add(id);
    }
    modes.sort();
    setState(() => _o = _o.copyWith(transitModes: modes));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusBottomSheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  AppI18n.of(context).goRouteOptions,
                  style: AppTextStyles.heading2.copyWith(color: cs.onSurface),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                children: [
                  _sectionRow(
                    AppI18n.of(context).goPrefRow,
                    _gcLabel(AppI18n.of(context), _o.gc),
                    cs,
                  ),
                  AppSlider(
                    value: _o.gc,
                    divisions: 10,
                    onChanged: (v) => setState(() => _o = _o.copyWith(gc: v)),
                  ),
                  _endLabels(
                    AppI18n.of(context).goPrefCheapest,
                    AppI18n.of(context).goPrefFastest,
                    cs,
                  ),
                  const SizedBox(height: 12),
                  _rowControl(
                    AppI18n.of(context).goRouteCount,
                    AppQuantitySelector(
                      value: _o.top,
                      min: 1,
                      max: 10,
                      onChanged: (v) =>
                          setState(() => _o = _o.copyWith(top: v)),
                    ),
                    cs,
                  ),
                  const SizedBox(height: 12),
                  _sectionRow(AppI18n.of(context).goModes, '', cs),
                  const SizedBox(height: 8),
                  FilterChipGroup<int>(
                    options: _kTransitModes(AppI18n.of(context)),
                    selected: _o.transitModes.toSet(),
                    onToggle: _toggleMode,
                  ),
                  const SizedBox(height: 16),
                  _sectionRow(
                    AppI18n.of(context).goTransferTime,
                    AppI18n.of(
                      context,
                    ).minutesRange(_o.transferMin, _o.transferMax),
                    cs,
                  ),
                  AppRangeSlider(
                    values: RangeValues(
                      _o.transferMin.toDouble(),
                      _o.transferMax.toDouble(),
                    ),
                    max: 60,
                    divisions: 12,
                    onChanged: (v) => setState(
                      () => _o = _o.copyWith(
                        transferMin: v.start.round(),
                        transferMax: v.end.round(),
                      ),
                    ),
                  ),
                  _endLabels(
                    AppI18n.of(context).goZeroMinutes,
                    AppI18n.of(context).goSixtyMinutes,
                    cs,
                  ),
                  const SizedBox(height: 12),
                  _mileSection(
                    AppI18n.of(context).goFirstMile,
                    _o.firstMileMode,
                    _o.firstMileTime,
                    (m) => setState(() => _o = _o.copyWith(firstMileMode: m)),
                    (t) => setState(() => _o = _o.copyWith(firstMileTime: t)),
                    cs,
                  ),
                  const SizedBox(height: 12),
                  _mileSection(
                    AppI18n.of(context).goLastMile,
                    _o.lastMileMode,
                    _o.lastMileTime,
                    (m) => setState(() => _o = _o.copyWith(lastMileMode: m)),
                    (t) => setState(() => _o = _o.copyWith(lastMileTime: t)),
                    cs,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: AppI18n.of(context).commonApply,
                  onPressed: () => Navigator.of(context).pop(_o),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionRow(String title, String value, ColorScheme cs) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: AppTextStyles.bodyLarge.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (value.isNotEmpty)
        Text(
          value,
          style: AppTextStyles.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
            fontFeatures: AppTextStyles.tabularFigures,
          ),
        ),
    ],
  );

  Widget _rowControl(String title, Widget control, ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.bodyLarge.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        control,
      ],
    ),
  );

  Widget _endLabels(String left, String right, ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          left,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
        Text(
          right,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    ),
  );

  Widget _mileSection(
    String title,
    int mode,
    int time,
    ValueChanged<int> onMode,
    ValueChanged<int> onTime,
    ColorScheme cs,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _rowControl(
        title,
        AppQuantitySelector(
          value: time,
          min: 1,
          max: 60,
          onChanged: onTime,
        ),
        cs,
      ),
      const SizedBox(height: 8),
      FilterChipGroup<int>(
        options: _kMileModes(AppI18n.of(context)),
        selected: {mode},
        onToggle: onMode,
      ),
    ],
  );
}

class _GoMessage extends StatelessWidget {
  const _GoMessage({
    required this.icon,
    required this.title,
    required this.hint,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              Pressable(
                onTap: onAction,
                semanticLabel: actionLabel,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  ),
                  child: Text(
                    actionLabel!,
                    style: AppTextStyles.bodyRegular.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Plan-entry phase: the map-less landing surface, and the search itself. The
/// destination row *is* the search field and takes focus on arrival, so a rider
/// who opened the planner to type somewhere can type immediately instead of
/// tapping through to a second, near-identical screen.
///
/// The list below answers with the most complete thing first: a saved route is
/// a whole trip in one tap, a saved place is half of one, a recent search is
/// the weakest of the three.
class _PlannerEntry extends StatelessWidget {
  const _PlannerEntry({
    required this.origin,
    required this.originStatus,
    required this.savedRoutes,
    required this.onEditOrigin,
    required this.onSwap,
    required this.onPickDestination,
    required this.onOpenSaved,
    required this.onToggleSave,
    required this.onBack,
    required this.onEnableLocation,
    super.key,
  });

  final PlannedPlace? origin;
  final OriginStatus originStatus;
  final List<PlanRoute> savedRoutes;
  final VoidCallback onEditOrigin;
  final VoidCallback onSwap;
  final ValueChanged<PlannedPlace> onPickDestination;
  final void Function(PlanRoute) onOpenSaved;
  final void Function(PlanRoute) onToggleSave;
  final VoidCallback onBack;
  final VoidCallback onEnableLocation;

  // 路線箱: the saved-route cards. Kept out of PlaceSearchView (which only knows
  // places) by passing it in as the list header.
  Widget? _savedRoutesHeader(BuildContext context) {
    if (savedRoutes.isEmpty) return null;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Text(
            AppI18n.of(context).goRouteBox,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Column(
            children: [
              for (final route in savedRoutes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RouteOptionCard(
                    route: route,
                    highlighted: false,
                    isSaved: true,
                    onTap: () => onOpenSaved(route),
                    onToggleSave: () => onToggleSave(route),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: SafeArea(
        bottom: false,
        child: PlaceSearchView(
          fieldLabel: AppI18n.of(context).goSearchDestination,
          // Picking here sets the *destination*, and "current location" is not
          // somewhere anyone travels to.
          allowCurrentLocation: false,
          emptyHint: AppI18n.of(context).goSearchDestinationHint,
          header: _savedRoutesHeader(context),
          onPicked: onPickDestination,
          headerBuilder: (context, input) => Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Pressable(
                      onTap: onBack,
                      semanticLabel: AppI18n.of(context).commonBack,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 22,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      AppI18n.of(context).goPlanRoute,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                  child: _ODFields(
                    origin: origin,
                    originStatus: originStatus,
                    onEditOrigin: onEditOrigin,
                    onSwap: onSwap,
                    onEnableLocation: onEnableLocation,
                    destination: Align(
                      alignment: Alignment.centerLeft,
                      child: input,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Results-header chip that reads out the current departure/arrival stance and
/// opens the time selector.
class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.mode, required this.at, required this.onTap});

  final _TimeMode mode;
  final DateTime at;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${two(at.month)}/${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
    final suffix = switch (mode) {
      _TimeMode.leaveNow => null,
      _TimeMode.departAt => AppI18n.of(context).goDepartSuffix,
      _TimeMode.arriveBy => AppI18n.of(context).goArriveSuffix,
    };
    final sansStyle = AppTextStyles.bodySmall.copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w600,
    );
    return Pressable(
      onTap: onTap,
      semanticLabel: AppI18n.of(context).goChooseDepartTime,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 16, color: cs.onSurface),
            const SizedBox(width: 6),
            if (suffix == null)
              Text(AppI18n.of(context).goLeaveNow, style: sansStyle)
            else ...[
              Text(
                stamp,
                style: AppTextStyles.timeValue(
                  size: sansStyle.fontSize,
                  weight: sansStyle.fontWeight,
                  color: sansStyle.color,
                ),
              ),
              Text(suffix, style: sansStyle),
            ],
          ],
        ),
      ),
    );
  }
}

// Built per call rather than held in a const map: the names follow the
// rider's language.
Map<int, String> _weekdayLabels(AppI18n i18n) => {
  DateTime.monday: i18n.weekdayMon,
  DateTime.tuesday: i18n.weekdayTue,
  DateTime.wednesday: i18n.weekdayWed,
  DateTime.thursday: i18n.weekdayThu,
  DateTime.friday: i18n.weekdayFri,
  DateTime.saturday: i18n.weekdaySat,
  DateTime.sunday: i18n.weekdaySun,
};

/// Departure/arrival time selector, mirroring the rail query's
/// date + time + stance idiom. Returns the chosen `(mode, at)` on 套用, or null
/// on dismiss.
Future<({_TimeMode mode, DateTime at})?> _showTimeModeSheet(
  BuildContext context, {
  required _TimeMode mode,
  required DateTime at,
}) {
  return showModalBottomSheet<({_TimeMode mode, DateTime at})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TimeModeSheet(mode: mode, at: at),
  );
}

class _TimeModeSheet extends StatefulWidget {
  const _TimeModeSheet({required this.mode, required this.at});

  final _TimeMode mode;
  final DateTime at;

  @override
  State<_TimeModeSheet> createState() => _TimeModeSheetState();
}

class _TimeModeSheetState extends State<_TimeModeSheet> {
  late _TimeMode _mode = widget.mode;
  late DateTime _at = widget.at;

  Future<void> _pickDate() async {
    final cs = Theme.of(context).colorScheme;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusBottomSheet),
        ),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetDragHandle(),
              const SizedBox(height: 8),
              AppDatePicker(
                selectedDay: _at,
                onDaySelected: (date) => Navigator.pop(context, date),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      // Preserve the chosen time-of-day when only the date changes.
      setState(() {
        _at = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _at.hour,
          _at.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await AppTimePicker.show(
      context,
      TimeOfDay(hour: _at.hour, minute: _at.minute),
    );
    if (picked != null && mounted) {
      setState(() {
        _at = DateTime(
          _at.year,
          _at.month,
          _at.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String two(int v) => v.toString().padLeft(2, '0');
    final timed = _mode != _TimeMode.leaveNow;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusBottomSheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                AppI18n.of(context).goDepartAt,
                style: AppTextStyles.heading2.copyWith(color: cs.onSurface),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppSlidingSegment<_TimeMode>(
                options: {
                  _TimeMode.leaveNow: AppI18n.of(context).goLeaveNow,
                  _TimeMode.departAt: AppI18n.of(context).goDepartAt,
                  _TimeMode.arriveBy: AppI18n.of(context).goArriveBy,
                },
                value: _mode,
                onChanged: (v) => setState(() => _mode = v),
              ),
            ),
            if (timed) ...[
              const SizedBox(height: 8),
              _TimeRow(
                icon: Icons.event_rounded,
                label: AppI18n.of(context).commonDate,
                value:
                    '${two(_at.month)}/${two(_at.day)}'
                    '（${_weekdayLabels(AppI18n.of(context))[_at.weekday]}）',
                onTap: _pickDate,
              ),
              _TimeRow(
                icon: Icons.schedule_rounded,
                label: AppI18n.of(context).commonTime,
                value: '${two(_at.hour)}:${two(_at.minute)}',
                onTap: _pickTime,
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: AppI18n.of(context).commonApply,
                  onPressed: () =>
                      Navigator.of(context).pop((mode: _mode, at: _at)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: '$label $value',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTextStyles.bodyLarge.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              ),
              child: Text(
                value,
                style: AppTextStyles.memo.copyWith(color: cs.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
