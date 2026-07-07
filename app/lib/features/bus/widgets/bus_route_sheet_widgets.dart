part of '../view/bus_route_screen.dart';

class _RouteSheet extends StatelessWidget {
  const _RouteSheet({
    required this.tabController,
    required this.sheetController,
    required this.scrollController,
    required this.stops,
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
  });

  final TabController tabController;
  final SheetController sheetController;
  final ScrollController scrollController;
  final List<TimelineStop> stops;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final timeline = _HorizontalRouteTimeline(
      stops: stops,
      vehicles: vehicles,
      direction: direction,
    );

    final tabsContent = Column(
      children: [
        RouteTabBar(
          controller: tabController,
          tabs: const ['站牌列表', '詳細資訊'],
          backgroundColor: cs.surfaceContainerLow,
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
                _StopListTab(
                  stops: stops,
                  scrollController: scrollController,
                  reminders: reminders,
                  onReminderToggled: onReminderToggled,
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
        initialOffset: const SheetOffset.proportionalToViewport(0.30),
        snapGrid: const SheetSnapGrid(
          snaps: [
            SheetOffset.proportionalToViewport(0.30),
            SheetOffset.proportionalToViewport(1),
          ],
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
              child: AppSlidingSegment<int>(
                options: {
                  0: dirNames[0],
                  1: dirNames[1],
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
