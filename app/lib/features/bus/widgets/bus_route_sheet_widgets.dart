part of '../view/bus_route_screen.dart';

/// Static stand-in for [AppSlidingSegment] on single-direction (loop) routes:
/// same 44px footprint and groove styling, but no thumb and no interaction —
/// just the one headsign behind a loop glyph.
class _SingleDirectionPill extends StatelessWidget {
  const _SingleDirectionPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    return Semantics(
      label: '單向路線 $label',
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.repeat_rounded, size: 15, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    required this.reminders,
    required this.onReminderToggled,
    required this.pickingStop,
    required this.pinnedNextStopIndex,
    required this.targetStopUid,
    required this.leadStops,
    required this.onPickStop,
    required this.onLeadChanged,
    required this.onConfirmPick,
    required this.onSkipPick,
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
  final Map<String, String> reminders;
  final void Function(String) onReminderToggled;

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
            routeLabel: headsign.isEmpty
                ? routeName
                : '$routeName 往$headsign',
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

    // Only the timeline observes live ETA churn; the sheet skeleton around it
    // stays put across frames.
    final timeline =
        BlocSelector<BusRouteBloc, BusRouteState, List<TimelineStop>>(
          selector: _stopsFor,
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
          tabs: const ['站牌列表', '詳細資訊'],
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
                  selector: _stopsFor,
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
                          reminders: reminders,
                          onReminderToggled: onReminderToggled,
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

    return SheetExitGestureDetector(
      onExit: () => context.pop(),
      child: Sheet(
        controller: sheetController,
        initialOffset: AppSheetSnap.peek,
        // Two detents by design: a route list is either a glance or a full
        // read, nothing between.
        // While picking an alight stop, a taller detent holds the pick bar
        // above the timeline (peek is too short and would clip it); peek stays
        // in the grid so the rider can still drag back down.
        snapGrid: SheetSnapGrid(
          snaps: pickingStop
              ? const [AppSheetSnap.peek, _kPickSheetOffset, AppSheetSnap.full]
              : const [AppSheetSnap.peek, AppSheetSnap.full],
        ),
        scrollConfiguration: const SheetScrollConfiguration(),
        decoration: MaterialSheetDecoration(
          size: SheetSize.stretch,
          color: cs.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusBottomSheet),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        child: Column(
          children: [
            const SheetDragHandle(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // A loop/one-way route has no return stop list; a two-slot
              // slider with a blank half would render, so a static pill
              // carries the single headsign instead.
              child: routeState.route != null &&
                      routeState.route!.stopsReturn.isEmpty
                  ? _SingleDirectionPill(
                      label: dirNames[0].isNotEmpty ? dirNames[0] : routeName,
                    )
                  : AppSlidingSegment<int>(
                      options: {
                        0: dirNames[0].isNotEmpty ? dirNames[0] : '去程',
                        1: dirNames[1].isNotEmpty ? dirNames[1] : '返程',
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
                          height: 120,
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
  });

  final bool hasTarget;
  final int leadStops;
  final ValueChanged<int> onLeadChanged;
  final VoidCallback onConfirm;
  final VoidCallback onSkip;

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
                  hasTarget ? '設定提前提醒' : '選你要下車的站',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Pressable(
                onTap: onSkip,
                semanticLabel: '略過',
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '略過',
                        style: TextStyle(
                          fontSize: 13,
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
                  '提前',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
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
                    '$leadStops 站',
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
                  semanticLabel: '完成',
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
                      '完成',
                      style: TextStyle(
                        fontSize: 14,
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
      semanticLabel: icon == Icons.add_rounded ? '增加' : '減少',
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
