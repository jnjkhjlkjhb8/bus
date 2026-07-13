part of '../view/bus_route_screen.dart';

class _StopListTab extends StatelessWidget {
  const _StopListTab({
    required this.stops,
    required this.scrollController,
    required this.flashStopUid,
    required this.reminders,
    required this.onReminderToggled,
    required this.trackedStopUid,
    required this.onTrackToggled,
  });

  final List<TimelineStop> stops;
  final ScrollController scrollController;
  final String? flashStopUid;
  final Map<String, String> reminders;
  final void Function(String) onReminderToggled;
  final String? trackedStopUid;
  final void Function(TimelineStop) onTrackToggled;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<BusRouteBloc>().add(const BusRouteStarted());
      },
      child: ListView.builder(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: stops.length,
        itemBuilder: (_, i) {
          final stop = stops[i];
          return _StopListItem(
            stop: stop,
            index: i,
            totalStops: stops.length,
            isFlashed: stop.uid == flashStopUid,
            isReminderActive: reminders.containsKey(stop.uid),
            onReminderToggled: () => onReminderToggled(stop.uid),
            isTracking: trackedStopUid == stop.uid,
            onTrackToggled: () => onTrackToggled(stop),
          );
        },
      ),
    );
  }
}

class _StopListItem extends StatelessWidget {
  const _StopListItem({
    required this.stop,
    required this.index,
    required this.totalStops,
    required this.isFlashed,
    required this.isReminderActive,
    required this.onReminderToggled,
    required this.isTracking,
    required this.onTrackToggled,
  });

  final TimelineStop stop;
  final int index;
  final int totalStops;
  /// True for the few seconds after this stop's map marker was tapped.
  final bool isFlashed;
  final bool isReminderActive;
  final VoidCallback onReminderToggled;
  final bool isTracking;
  final VoidCallback onTrackToggled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A marker-tap flash reuses the live/approaching row treatment (bold +
    // tint) so a tapped stop reads the same as the active one.
    final isHighlighted = stop.active || isFlashed;

    final nameColor = cs.onSurface;
    Widget nameWidget = Text(
      stop.name,
      style: TextStyle(
        fontSize: 14,
        fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w400,
        color: nameColor,
        height: 1.3,
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
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      );
    } else if (stop.secondaryLabel == 'TERMINUS') {
      nameWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          nameWidget,
          const SizedBox(width: 6),
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              '終點',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    Widget etaWidget = const SizedBox.shrink();
    if (stop.primaryTime != null) {
      etaWidget = Text(
        stop.primaryTime!,
        style: AppTextStyles.memo.copyWith(
          fontSize: isHighlighted ? 15 : 14,
          fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w400,
          color: cs.onSurface,
        ),
      );
    }

    var bellBg = cs.brightness == Brightness.light
        ? cs.surface
        : cs.surfaceContainerHigh;
    var bellColor = cs.brightness == Brightness.light
        ? cs.outline
        : cs.onSurfaceVariant;

    if (isHighlighted) {
      bellBg = cs.brightness == Brightness.light
          ? cs.onSurface.withValues(alpha: 0.06)
          : cs.surfaceContainerHigh;
      bellColor = cs.onSurface;
    }

    final trackBtn = Pressable(
      onTap: onTrackToggled,
      semanticLabel: isTracking ? '停止追蹤' : '追蹤到站',
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: isTracking ? cs.onSurface : bellBg,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: Icon(
            Icons.radar_rounded,
            size: 16,
            color: isTracking ? cs.surface : bellColor,
          ),
        ),
      ),
    );

    final bellBtn = Pressable(
      onTap: onReminderToggled,
      semanticLabel: isReminderActive ? '取消提醒' : '設定提醒',
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: bellBg,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: Icon(
            isReminderActive
                ? Icons.notifications_rounded
                : Icons.notifications_none_rounded,
            size: 16,
            color: isReminderActive ? cs.primary : bellColor,
          ),
        ),
      ),
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: BoxDecoration(
        color: isHighlighted
            ? (cs.brightness == Brightness.light
                  ? cs.onSurface.withValues(alpha: 0.06)
                  : cs.surfaceContainerHigh)
            : Colors.transparent,
      ),
      child: Row(
        children: [
          Expanded(child: nameWidget),
          const SizedBox(width: 12),
          etaWidget,
          const SizedBox(width: 12),
          trackBtn,
          const SizedBox(width: 8),
          bellBtn,
        ],
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
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shimmerColor = cs.surfaceContainerHigh.withValues(alpha: 0.6);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations && _animController.isAnimating) {
      _animController.stop();
    } else if (!disableAnimations && !_animController.isAnimating) {
      unawaited(_animController.repeat(reverse: true));
    }

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
