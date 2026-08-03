part of '../view/go_screen.dart';

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
