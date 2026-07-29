part of '../view/bus_route_screen.dart';

class _RouteSheet extends StatelessWidget {
  const _RouteSheet({
    required this.tabController,
    required this.sheetController,
    required this.scrollController,
    required this.timelineController,
    required this.flashStopUid,
    required this.vehicles,
    required this.direction,
    required this.isLoading,
    required this.onDirectionChanged,
    required this.sheetAnimation,
    required this.routeName,
    required this.dirNames,
    required this.routeState,
    required this.pickingStop,
    required this.pinnedNextStopIndex,
    required this.targetStopUid,
    required this.leadStops,
    required this.onPickStop,
    required this.onLeadChanged,
    required this.onConfirmPick,
    required this.onSkipPick,
    this.onCancelPick,
  });

  final TabController tabController;
  final SheetController sheetController;
  final ScrollController scrollController;
  final ScrollController timelineController;
  final String? flashStopUid;
  final List<_BusVehicle> vehicles;
  final int direction;
  final bool isLoading;
  final ValueChanged<int> onDirectionChanged;
  final Animation<double> sheetAnimation;
  final String routeName;
  final List<String> dirNames;
  final BusRouteState routeState;

  /// Pick-mode: a bus is pinned and the rider is choosing an alight stop.
  final bool pickingStop;

  /// Index of the pinned bus's next stop; stops before it are dimmed as passed.
  final int? pinnedNextStopIndex;

  /// The chosen alight stop, or null before one is tapped.
  final String? targetStopUid;

  /// 提前站數 lead (min 1).
  final int leadStops;
  final void Function(String uid) onPickStop;
  final ValueChanged<int> onLeadChanged;
  final VoidCallback onConfirmPick;
  final VoidCallback onSkipPick;

  /// Fully aborts pick-mode with no tracking session started. Optional and
  /// unwired today — the caller (BusRouteScreen) would need to mirror the
  /// unpin branch of its own _togglePin (session cancel + state reset) to
  /// supply this. See finding 6, docs/audit-2026-07-18.md.
  final VoidCallback? onCancelPick;

  /// The stop this route is live-tracking (追蹤), or null. Only a trackOnly
  /// waiting session on this very subroute counts — navigation sessions and
  /// other routes' sessions leave the toggles idle.
  String? _trackedStopUidFor(JourneySessionState s) {
    final leg = s.currentLeg;
    if (!s.trackOnly ||
        s.phase != JourneyPhase.waiting ||
        leg == null ||
        leg.kind != JourneyLegKind.bus ||
        leg.identity.routeKey != routeState.route?.subRouteUid) {
      return null;
    }
    return leg.identity.departureStopKey;
  }

  void _toggleStopTracking(BuildContext context, TimelineStop stop) {
    final session = context.read<JourneySessionBloc>();
    unawaited(HapticService.instance.mediumTap());
    if (_trackedStopUidFor(session.state) == stop.uid) {
      session.add(const JourneyCancelled());
      return;
    }
    final route = routeState.route;
    if (route == null) return;
    final stops = direction == 0 ? route.stopsGo : route.stopsReturn;
    final idx = stops.indexWhere((s) => s.stopUid == stop.uid);
    if (idx < 0) return;
    final headsign = direction == 0 ? route.headsignGo : route.headsignReturn;
    session.add(
      JourneyStarted(
        trackOnly: true,
        legs: [
          JourneyLeg(
            kind: JourneyLegKind.bus,
            routeLabel: headsign.isEmpty ? routeName : '$routeName 往$headsign',
            boardStop: stops[idx].stopName,
            alightStop: stops.last.stopName,
            // trackOnly never rides, so the riding-progress stop lists stay
            // empty on purpose.
            stopNames: const [],
            identity: PlanIdentity(
              routeType: 'bus',
              routeKey: route.subRouteUid,
              direction: '$direction',
              departureStopKey: stop.uid,
              arrivalStopKey: '',
              supported: false,
            ),
            leadingWalkMinutes: 0,
            scheduledDeparture: null,
            scheduledArrival: null,
            boardLocation: PlanPoint(
              lat: stops[idx].lat,
              lng: stops[idx].lon,
            ),
            stopLocations: const [],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Route identity strip (finding 5): the floating app bar this doubles for
    // is painted under the sheet, so it needs the current headsign too.
    final dirName = direction == 0 ? dirNames[0] : dirNames[1];

    // Only the timeline observes live ETA churn; the sheet skeleton around it
    // stays put across frames.
    final timeline =
        BlocSelector<BusRouteBloc, BusRouteState, List<TimelineStop>>(
          selector: (s) => _stopsFor(AppI18n.of(context), s),
          builder: (context, stops) => _HorizontalRouteTimeline(
            stops: stops,
            vehicles: vehicles,
            direction: direction,
            controller: timelineController,
            flashStopUid: flashStopUid,
            picking: pickingStop,
            pinnedNextStopIndex: pinnedNextStopIndex,
            targetUid: targetStopUid,
            onPickStop: onPickStop,
          ),
        );

    final tabsContent = Column(
      children: [
        RouteTabBar(
          controller: tabController,
          tabs: [
            AppI18n.of(context).busStopList,
            AppI18n.of(context).busRouteDetails,
          ],
          raised: true,
        ),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: [
              if (isLoading)
                const _ShimmerStopList()
              else if (routeState.error != null)
                ErrorStateView(
                  error: routeState.error!,
                  onRetry: () =>
                      context.read<BusRouteBloc>().add(const BusRouteStarted()),
                )
              else
                // Scoped to etaMap so a live frame repaints the stop rows only,
                // not the tab bar or detail tab.
                BlocSelector<BusRouteBloc, BusRouteState, List<TimelineStop>>(
                  selector: (s) => _stopsFor(AppI18n.of(context), s),
                  builder: (context, stops) =>
                      BlocSelector<
                        JourneySessionBloc,
                        JourneySessionState,
                        String?
                      >(
                        selector: _trackedStopUidFor,
                        builder: (context, trackedStopUid) => _StopListTab(
                          stops: stops,
                          scrollController: scrollController,
                          flashStopUid: flashStopUid,
                          trackedStopUid: trackedStopUid,
                          onTrackToggled: (stop) =>
                              _toggleStopTracking(context, stop),
                        ),
                      ),
                ),
              _RouteDetailTab(state: routeState),
            ],
          ),
        ),
      ],
    );

    return AppSheet(
      controller: sheetController,
      // Holding past the top edge returns the sheet to peek rather than
      // leaving the page — the same answer the home sheet gives. The floating
      // app bar's back button is the way out (see AppSheet.onExit). While
      // picking an alight stop peek is out of the grid, so the hold lands on
      // the pick detent instead.
      onExit: () => sheetController.animateTo(
        pickingStop ? _kPickSheetOffset : AppSheetSnap.peek,
      ),
      initialOffset: AppSheetSnap.peek,
      // While picking an alight stop the grid collapses: the pick bar inserts
      // above the timeline and peek has no room for both (dragging down to
      // peek used to clip the timeline's ETA labels away). The rider exits
      // pick-mode via 完成/略過/取消 in the pick bar.
      snapGrid: pickingStop
          ? const SheetSnapGrid(
              snaps: [_kPickSheetOffset, AppSheetSnap.full],
              minFlingSpeed: AppSheetSnap.flingSpeed,
            )
          : _kRouteSnapGrid,
      child: Column(
        children: [
          // Scoped to just the handle + identity strip so a drag frame
          // doesn't also rebuild the (static, per-frame-unchanging) segment
          // and pick bar below — same rationale as `timeline`'s own
          // BlocSelector further down. The status-bar clearance the handle
          // needs at the full detent comes from AppSheet's own padding.
          AnimatedBuilder(
            animation: sheetAnimation,
            builder: (context, _) {
              final progress = sheetAnimation.value;
              // Route identity fades in as the sheet approaches full — by the
              // time it's readable, the app bar behind the sheet is gone.
              final identityOpacity = ((progress - 0.6) / 0.4).clamp(
                0.0,
                1.0,
              );
              return Column(
                children: [
                  const SheetDragHandle(),
                  if (identityOpacity > 0)
                    Opacity(
                      opacity: identityOpacity,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Row(
                          children: [
                            Text(
                              routeName,
                              style: AppTextStyles.bodyRegular.copyWith(
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                            if (dirName.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  dirName,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // A loop/one-way route has no return stop list; a two-slot
            // slider with a blank half would render, so a static pill
            // carries the single headsign instead.
            child:
                routeState.route != null &&
                    routeState.route!.stopsReturn.isEmpty
                ? AppStaticSegment(
                    label: dirNames[0].isNotEmpty ? dirNames[0] : routeName,
                    leading: Icons.repeat_rounded,
                    semanticLabel: AppI18n.of(context).busOneWayRoute(
                      dirNames[0].isNotEmpty ? dirNames[0] : routeName,
                    ),
                  )
                : AppSlidingSegment<int>(
                    options: {
                      0: dirNames[0].isNotEmpty
                          ? dirNames[0]
                          : AppI18n.of(context).busDirectionOutbound,
                      1: dirNames[1].isNotEmpty
                          ? dirNames[1]
                          : AppI18n.of(context).busDirectionInbound,
                    },
                    value: direction,
                    onChanged: onDirectionChanged,
                  ),
          ),
          const SizedBox(height: 12),
          if (pickingStop)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _PickBar(
                hasTarget: targetStopUid != null,
                leadStops: leadStops,
                onLeadChanged: onLeadChanged,
                onConfirm: onConfirmPick,
                onSkip: onSkipPick,
                onCancelPick: onCancelPick,
              ),
            ),
          Expanded(
            child: AnimatedBuilder(
              animation: sheetAnimation,
              builder: (context, _) {
                final progress = sheetAnimation.value;
                final showTimeline = progress < 0.75;
                final showTabs = progress > 0.25;

                final timelineOpacity = (1.0 - progress * 1.6).clamp(
                  0.0,
                  1.0,
                );
                final tabsOpacity = ((progress - 0.25) * 1.6).clamp(0.0, 1.0);

                return Stack(
                  children: [
                    if (showTimeline)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: _tlCellHeight,
                        child: Opacity(
                          opacity: timelineOpacity,
                          child: IgnorePointer(
                            ignoring: progress > 0.5,
                            child: timeline,
                          ),
                        ),
                      ),

                    if (showTabs)
                      Positioned.fill(
                        child: Opacity(
                          opacity: tabsOpacity,
                          child: IgnorePointer(
                            ignoring: progress < 0.5,
                            child: tabsContent,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Transient bar shown above the timeline while a bus is pinned. Prompts for an
/// alight stop and, once one is picked, reveals the 提前站數 stepper and 完成.
/// The 略過 control is always present to track the bus with no reminder.
class _PickBar extends StatelessWidget {
  const _PickBar({
    required this.hasTarget,
    required this.leadStops,
    required this.onLeadChanged,
    required this.onConfirm,
    required this.onSkip,
    this.onCancelPick,
  });

  final bool hasTarget;
  final int leadStops;
  final ValueChanged<int> onLeadChanged;
  final VoidCallback onConfirm;
  final VoidCallback onSkip;

  /// Fully aborts pick-mode with no tracking started at all — distinct from
  /// [onSkip], which still arms a no-reminder tracking session. Optional: the
  /// caller (_RouteSheet) only renders the control when this is wired, since
  /// today the only cancel path is re-tapping the pinned bus marker on the
  /// map (see finding 6, docs/audit-2026-07-18.md).
  final VoidCallback? onCancelPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLight = cs.brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isLight ? cs.surface : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppShadows.floating,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.touch_app_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasTarget
                      ? AppI18n.of(context).busSetLeadReminder
                      : AppI18n.of(context).busPickAlightStop,
                  style: AppTextStyles.bodyRegular.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              // Fully aborts pick-mode with no session started — ✕ reads
              // correctly here because this control actually cancels, unlike
              // 略過 below. Only rendered once the caller wires a real cancel
              // path (today: re-tapping the pinned marker on the map).
              if (onCancelPick != null) ...[
                Pressable(
                  onTap: onCancelPick,
                  semanticLabel: AppI18n.of(context).busCancelStopPick,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Pressable(
                onTap: onSkip,
                semanticLabel: AppI18n.of(context).commonSkip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 略過 is affirmative (start tracking with no reminder),
                      // not a dismissal — ✕ would misread as cancel.
                      Icon(
                        Icons.skip_next_rounded,
                        size: 15,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        AppI18n.of(context).commonSkip,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontWeight: FontWeight.w500,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (hasTarget) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  AppI18n.of(context).busLeadLabel,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                _StepButton(
                  icon: Icons.remove_rounded,
                  enabled: leadStops > 1,
                  onTap: () => onLeadChanged(leadStops - 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    AppI18n.of(context).stopsCount(leadStops),
                    style: AppTextStyles.memo.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                      fontFeatures: _tnum,
                    ),
                  ),
                ),
                _StepButton(
                  icon: Icons.add_rounded,
                  enabled: true,
                  onTap: () => onLeadChanged(leadStops + 1),
                ),
                const Spacer(),
                Pressable(
                  onTap: onConfirm,
                  semanticLabel: AppI18n.of(context).commonDone,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cs.onSurface,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      AppI18n.of(context).commonDone,
                      style: AppTextStyles.bodyRegular.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.surface,
                      ),
                    ),
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

/// A square − / + control for the 提前站數 stepper; dims when disabled.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      enabled: enabled,
      onTap: () {
        unawaited(HapticService.instance.lightTap());
        onTap();
      },
      semanticLabel: icon == Icons.add_rounded
          ? AppI18n.of(context).commonIncrease
          : AppI18n.of(context).commonDecrease,
      // Visual box stays 30px; minTapSize lifts the actual hit area to the
      // 44px floor without changing how the control reads.
      minTapSize: 44,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 17,
          color: enabled
              ? cs.onSurface
              : cs.onSurfaceVariant.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
