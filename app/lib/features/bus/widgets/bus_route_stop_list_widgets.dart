part of '../view/bus_route_screen.dart';

/// A stop's service is over for today when its raw status was one of the two
/// terminal codes (stopStatus 3 / 4; see eta_format.dart). The flag is
/// computed where the stop is built, so this no longer has to match on the
/// rendered label — which is localized and would stop matching in any other
/// locale.
bool _slServiceEnded(TimelineStop stop) => stop.serviceEnded;

/// Single collapsed notice replacing 40 identical per-row "末班已過" labels
/// when every stop in the direction has ended for the day (PRODUCT.md:
/// "glanceable over informative").
Widget _slServiceEndedBanner(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    color: cs.surfaceContainerHighest,
    child: Text(
      AppI18n.of(context).busServiceEndedToday,
      style: AppTextStyles.bodyRegular.copyWith(
        fontWeight: FontWeight.w600,
        color: cs.onSurfaceVariant,
      ),
    ),
  );
}

/// Dispatches the reload and waits for the bloc to actually leave its loading
/// state, so RefreshIndicator's spinner reflects real progress instead of
/// closing the instant the gesture completes. Bounded so a stuck bloc can
/// never hang the pull-to-refresh gesture forever.
Future<void> _slAwaitRouteReload(BuildContext context) async {
  final bloc = context.read<BusRouteBloc>()..add(const BusRouteStarted());
  await bloc.stream
      .firstWhere((state) => !state.loading)
      .timeout(const Duration(seconds: 8), onTimeout: () => bloc.state);
}

class _StopListTab extends StatelessWidget {
  const _StopListTab({
    required this.stops,
    required this.scrollController,
    required this.flashStopUid,
    required this.trackedStopUid,
    required this.onTrackToggled,
  });

  final List<TimelineStop> stops;
  final ScrollController scrollController;
  final String? flashStopUid;
  final String? trackedStopUid;
  final void Function(TimelineStop) onTrackToggled;

  @override
  Widget build(BuildContext context) {
    // All-ended collapses the per-row 末班已過 repetition into one banner;
    // a partial end still needs the per-row label — it's real signal there.
    final allStopsEnded = stops.isNotEmpty && stops.every(_slServiceEnded);

    // Vehicle positions are derived once for the whole direction rather than
    // per row: the signal is a comparison between neighbours, which a row
    // cannot see on its own.
    final markers = busVehicleMarkerIndices(stops);

    final children = <Widget>[];
    for (var i = 0; i < stops.length; i++) {
      final stop = stops[i];
      if (markers.contains(i)) {
        children.add(
          TimelineVehicleMarker(
            semanticLabel: AppI18n.of(context).busVehicleHere,
            // The marker stands for the bus this stop is counting down to, so
            // its plate is the one to print. Empty when the feed sent none.
            label: stop.plate.isEmpty ? null : stop.plate,
          ),
        );
      }
      // 兩段票 boundary. It changes what the ride costs, so it earns a line of
      // its own; the section data was already derived and then never shown.
      if (i > 0 &&
          stop.fareSection == 2 &&
          stops[i - 1].fareSection == 1 &&
          !stop.isBuffer) {
        children.add(_FareSectionDivider(stopName: stop.name));
      }
      children.add(
        _StopListItem(
          stop: stop,
          isFirst: i == 0,
          isLast: i == stops.length - 1,
          // The spine reads as "a bus is actually on its way to these stops":
          // solid where the ETA is a live countdown, hollow where it is only a
          // scheduled departure that has not happened yet.
          liveAbove: i > 0 && stops[i - 1].isLiveEta && stop.isLiveEta,
          liveBelow:
              i < stops.length - 1 && stop.isLiveEta && stops[i + 1].isLiveEta,
          isFlashed: stop.uid == flashStopUid,
          isTracking: trackedStopUid == stop.uid,
          onTrackToggled: () => onTrackToggled(stop),
          suppressEtaLabel: allStopsEnded,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _slAwaitRouteReload(context),
      child: Column(
        children: [
          if (allStopsEnded) _slServiceEndedBanner(context),
          Expanded(
            child: ListView(
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// The 兩段票 boundary: fares change from here on.
class _FareSectionDivider extends StatelessWidget {
  const _FareSectionDivider({required this.stopName});

  final String stopName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(kTimelineGutter, 6, 16, 6),
      child: Row(
        children: [
          Text(
            AppI18n.of(context).busSecondSectionFrom(stopName),
            style: AppTextStyles.bodyVerySmall.copyWith(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: cs.outlineVariant)),
        ],
      ),
    );
  }
}

class _StopListItem extends StatelessWidget {
  const _StopListItem({
    required this.stop,
    required this.isFirst,
    required this.isLast,
    required this.liveAbove,
    required this.liveBelow,
    required this.isFlashed,
    required this.isTracking,
    required this.onTrackToggled,
    this.suppressEtaLabel = false,
  });

  final TimelineStop stop;
  final bool isFirst;
  final bool isLast;

  /// Whether the spine segment above / below this stop is on a live run.
  final bool liveAbove;
  final bool liveBelow;

  /// True for the few seconds after this stop's map marker was tapped.
  final bool isFlashed;
  final bool isTracking;
  final VoidCallback onTrackToggled;

  /// True when every stop in the direction has ended, so the list-level
  /// banner already states it once and the per-row ETA text is redundant.
  final bool suppressEtaLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A marker-tap flash reuses the live/approaching row treatment (bold +
    // tint) so a tapped stop reads the same as the active one.
    final isHighlighted = stop.active || isFlashed;
    final highlightFill = cs.brightness == Brightness.light
        ? cs.onSurface.withValues(alpha: 0.06)
        : cs.surfaceContainerHigh;

    Widget nameWidget = Text(
      stop.name,
      style: AppTextStyles.bodyRegular.copyWith(
        fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w400,
        color: cs.onSurface,
      ),
      overflow: TextOverflow.ellipsis,
    );

    if (stop.secondaryLabel != null && stop.secondaryLabel != 'TERMINUS') {
      nameWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          nameWidget,
          const SizedBox(height: 2),
          Text(
            stop.secondaryLabel!,
            style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      );
    } else if (stop.secondaryLabel == 'TERMINUS') {
      nameWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: nameWidget),
          const SizedBox(width: 6),
          TimelineStopTag(AppI18n.of(context).busTerminus, solid: false),
        ],
      );
    }

    return Pressable(
      // Setting an arrival reminder is a once-per-trip act, so the whole row
      // carries it. It used to need a 28px button on every row: forty identical
      // grey chips down the list, louder than the arrival times they sat beside
      // and repeating an affordance the rider uses once.
      onTap: onTrackToggled,
      semanticLabel: _semanticLabel(AppI18n.of(context)),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        color: isHighlighted ? highlightFill : null,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TimelineSpine(
                kind: isFirst || isLast
                    ? TimelineNodeKind.terminus
                    : TimelineNodeKind.intermediate,
                lineAbove: !isFirst,
                lineBelow: !isLast,
                travelledAbove: liveAbove,
                travelledBelow: liveBelow,
                dimmed: suppressEtaLabel,
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(0, 10, 16, 10),
                  child: Row(
                    children: [
                      Expanded(child: nameWidget),
                      const SizedBox(width: 12),
                      if (!suppressEtaLabel) _buildEta(AppI18n.of(context), cs),
                      // The radar mark is now a *state*, not a control: it
                      // appears only on the row that actually has a reminder
                      // armed, which is at most one at a time.
                      if (isTracking) ...[
                        const SizedBox(width: 10),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: cs.onSurface,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusChip,
                            ),
                          ),
                          child: Icon(
                            Icons.radar_rounded,
                            size: 14,
                            color: cs.surface,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _semanticLabel(AppI18n i18n) {
    final eta = stop.primaryTime;
    final parts = <String>[
      stop.name,
      if (eta != null && !suppressEtaLabel)
        stop.isLiveEta ? eta : i18n.busScheduledDeparture(eta),
      if (isTracking) i18n.busReminderOnHint else i18n.busReminderOffHint,
    ];
    return parts.join('，');
  }

  /// A live countdown and a scheduled departure clock are two different facts,
  /// and the list used to print them in one voice: '20:40' and '2分' in the
  /// same column, same size, same colour, with only the format hinting that
  /// one means "no bus has left the terminal yet" and the other "a bus is two
  /// minutes away". The countdown keeps the emphasis; a schedule drops to
  /// secondary weight and says what it is.
  Widget _buildEta(AppI18n i18n, ColorScheme cs) {
    final label = stop.primaryTime;
    if (label == null) return const SizedBox.shrink();

    if (!stop.isLiveEta) {
      // A clock is a departure time and is prefixed as such; a service-state
      // word ('末班已過') already reads as one and takes no prefix.
      final isClock = label.contains(':');
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isClock)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Text(
                i18n.busDeparture,
                style: AppTextStyles.bodyVerySmall.copyWith(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          Text(
            label,
            style: (isClock ? AppTextStyles.memo : AppTextStyles.bodySmall)
                .copyWith(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                  fontFeatures: isClock ? AppTextStyles.tabularFigures : null,
                ),
          ),
        ],
      );
    }

    final arriving = stop.state == TimelineStopState.arriving;
    return Text(
      label,
      style: AppTextStyles.memo.copyWith(
        fontSize: 15,
        fontWeight: arriving ? FontWeight.w700 : FontWeight.w600,
        color: arriving ? AppTheme.statusArrivingText : cs.onSurface,
        fontFeatures: AppTextStyles.tabularFigures,
      ),
    );
  }
}

class _ShimmerStopList extends StatefulWidget {
  const _ShimmerStopList();

  @override
  State<_ShimmerStopList> createState() => _ShimmerStopListState();
}

class _ShimmerStopListState extends State<_ShimmerStopList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce-motion can flip at runtime (OS setting), and this is the
    // correct lifecycle hook for reacting to an inherited-widget change —
    // build() must stay free of side effects.
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations) {
      if (_animController.isAnimating) _animController.stop();
    } else if (!_animController.isAnimating) {
      unawaited(_animController.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shimmerColor = cs.surfaceContainerHigh.withValues(alpha: 0.6);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) => Opacity(
        opacity: disableAnimations
            ? 0.6
            : lerpDouble(0.4, 0.9, _animController.value)!,
        child: child,
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: 6,
        itemBuilder: (_, i) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 120,
                  height: 18,
                  decoration: BoxDecoration(
                    color: shimmerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Spacer(),

                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: shimmerColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),

                Container(
                  width: 48,
                  height: 18,
                  decoration: BoxDecoration(
                    color: shimmerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
