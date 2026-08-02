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
    required this.onBellTapped,
    this.onCancelPick,
  });

  /// Opens the 下車提醒 flow from the sheet header — the entry that does not
  /// require spotting a moving pin on the map first.
  final VoidCallback onBellTapped;

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
  String? _trackedStopUidFor(JourneySessionState s) =>
      trackedBusStopUid(s, routeState.route?.subRouteUid);

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
    session.add(
      JourneyStarted(
        trackOnly: true,
        legs: [
          busTrackingLeg(
            route: route,
            stops: stops,
            boardIndex: idx,
            direction: direction,
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
                          // While a 下車站 is being chosen the rows pick
                          // instead of arming an arrival reminder: one list,
                          // one meaning at a time.
                          picking: pickingStop,
                          firstPickableIndex: firstAlightIndex(
                            pinnedNextStopIndex,
                          ),
                          targetStopUid: targetStopUid,
                          onPickStop: onPickStop,
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
                            AlightTrackBell(
                              active: false,
                              semanticLabel: AppI18n.of(
                                context,
                              ).alightReminderSet,
                              onTap: onBellTapped,
                            ),
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

/// The candidate buses a reminder can bind to, as one row of plate chips.
///
/// A route can have several buses out at once and the reminder follows one
/// plate, so this is the rider's choice to make. Each chip carries where that
/// bus is right now, because a plate on its own is not something anyone can
/// recognise from inside the vehicle.
class _PlateChooser extends StatelessWidget {
  const _PlateChooser({
    required this.candidates,
    required this.selected,
    required this.onChoose,
  });

  final List<({String plate, String afterStopName, int index})> candidates;
  final String? selected;
  final void Function(String plate, int nextStopIndex) onChoose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i18n = AppI18n.of(context);
    if (candidates.isEmpty) {
      // The reminder binds to a plate, so with nothing running there is
      // nothing to bind — said here, where the choice would have been, rather
      // than left as a CTA that refuses without explaining itself.
      return Text(
        i18n.alightNoVehicles,
        style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          i18n.alightPickVehicle,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in candidates) ...[
                Pressable(
                  onTap: () => onChoose(c.plate, c.index),
                  semanticLabel: c.plate,
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selected == c.plate
                          ? cs.surfaceContainerHighest
                          : null,
                      border: Border.all(
                        color: selected == c.plate
                            ? cs.onSurface
                            : cs.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusButton,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.plate,
                          style: AppTextStyles.memo.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          i18n.alightVehiclePassed(c.afterStopName),
                          style: AppTextStyles.bodyVerySmall.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
