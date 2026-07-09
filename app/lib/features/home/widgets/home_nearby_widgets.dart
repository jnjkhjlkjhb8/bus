part of '../home_screen.dart';

const _kShowReturnMapOffset = 72.0;

enum NearbyFilter {
  all,
  mrt,
  bus,
  youbike,
  tra,
  thsr;

  String get label {
    switch (this) {
      case NearbyFilter.all:
        return '全部';
      case NearbyFilter.mrt:
        return '捷運';
      case NearbyFilter.bus:
        return '公車';
      case NearbyFilter.youbike:
        return '公共自行車';
      case NearbyFilter.tra:
        return '台鐵';
      case NearbyFilter.thsr:
        return '高鐵';
    }
  }
}

class _FilterButtonGroup extends StatelessWidget {
  const _FilterButtonGroup({
    required this.selectedFilter,
    required this.onFilterChanged,
  });

  final NearbyFilter selectedFilter;
  final ValueChanged<NearbyFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const filters = NearbyFilter.values;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        spacing: 8,
        children: [
          for (final filter in filters)
            Pressable(
              onTap: () {
                unawaited(HapticService.instance.lightTap());
                onFilterChanged(filter);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: filter == selectedFilter
                      ? cs.primary
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  filter.label,
                  style: TextStyle(
                    fontWeight: filter == selectedFilter
                        ? FontWeight.w600
                        : FontWeight.w400,
                    fontSize: 13,
                    color: filter == selectedFilter
                        ? cs.onPrimary
                        : cs.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NearbyStationsTab extends StatefulWidget {
  const _NearbyStationsTab({
    required this.onStationTap,
    required this.sheetController,
  });

  final ValueChanged<NearStationViewModel> onStationTap;
  final SheetController sheetController;

  @override
  State<_NearbyStationsTab> createState() => _NearbyStationsTabState();
}

class _NearbyStationsTabState extends State<_NearbyStationsTab> {
  NearbyFilter _selectedFilter = NearbyFilter.all;
  bool _showReturnMap = false;
  // Driven off the list's scroll notifications rather than an owned controller:
  // attaching one to a ListView inside a smooth_sheets Sheet double-binds the
  // viewport (the sheet already drives it) and trips ScrollController's
  // single-position assertion.
  bool _onScrollNotification(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    // Only a real user drag snaps the sheet up — a programmatic scroll-to-top
    // (from "return to map") has no dragDetails and must not re-expand it.
    if (n is ScrollStartNotification && n.dragDetails != null) {
      // Defer out of the notification: animating the sheet re-entrantly here
      // disposes its in-flight drag activity while it's still in use.
      scheduleMicrotask(() {
        if (mounted) {
          unawaited(
            widget.sheetController.animateTo(
              const SheetOffset.proportionalToViewport(1),
            ),
          );
        }
      });
    }
    final show = n.metrics.pixels > _kShowReturnMapOffset;
    if (show != _showReturnMap) setState(() => _showReturnMap = show);
    return false;
  }

  // Collapse the sheet to reveal the map, and smoothly return the list to the
  // top at the same time (via the sheet's own PrimaryScrollController).
  void _returnToMap() {
    unawaited(HapticService.instance.lightTap());
    final scroll = PrimaryScrollController.maybeOf(context);
    if (scroll != null && scroll.hasClients) {
      unawaited(
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 400),
          curve: AppMotion.easeOut,
        ),
      );
    }
    unawaited(
      widget.sheetController.animateTo(
        const SheetOffset.proportionalToViewport(0.30),
      ),
    );
  }

  bool _matches(NearStationViewModel s) {
    switch (_selectedFilter) {
      case NearbyFilter.all:
        return true;
      case NearbyFilter.mrt:
        return s.type == NearStationType.mrt;
      case NearbyFilter.bus:
        return s.type == NearStationType.bus;
      case NearbyFilter.youbike:
        return s.type == NearStationType.bike;
      case NearbyFilter.tra:
        return s.type == NearStationType.tra;
      case NearbyFilter.thsr:
        return s.type == NearStationType.thsr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FilterButtonGroup(
          selectedFilter: _selectedFilter,
          onFilterChanged: (filter) {
            setState(() {
              _selectedFilter = filter;
            });
          },
        ),
        Expanded(
          child: BlocBuilder<NearbyBloc, NearbyState>(
            builder: (context, state) {
              if (state.loading && state.stations.isEmpty) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    // Each ShimmerRow is height + 8 (vertical margin); fill
                    // the viewport so the skeleton reads as a full list.
                    const rowExtent = 62 + 8.0;
                    final count = (constraints.maxHeight / rowExtent).ceil();
                    return ListView(
                      padding: const EdgeInsets.only(top: 4),
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (var i = 0; i < count; i++)
                          const ShimmerRow(height: 62),
                      ],
                    );
                  },
                );
              }
              if (state.error != null) {
                return ErrorStateView(
                  error: state.error!,
                  onRetry: () => context.read<NearbyBloc>().add(
                    const NearbyRequested(radius: _kNearbyRadiusMeters),
                  ),
                );
              }
              final items = state.stations.where(_matches).toList();
              if (items.isEmpty) {
                return const _NearbyEmpty();
              }
              return Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: _onScrollNotification,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      itemBuilder: (context, i) => _NearbyStationRow(
                        station: items[i],
                        onStationTap: widget.onStationTap,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 40,
                    child: Center(
                      child: _ReturnMapPill(
                        visible: _showReturnMap,
                        onTap: _returnToMap,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NearbyEmpty extends StatelessWidget {
  const _NearbyEmpty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        '附近沒有站點',
        style: AppTextStyles.bodyRegular.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ReturnMapPill extends StatefulWidget {
  const _ReturnMapPill({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  State<_ReturnMapPill> createState() => _ReturnMapPillState();
}

class _ReturnMapPillState extends State<_ReturnMapPill>
    with SingleTickerProviderStateMixin {
  static const _dotSize = 12.0;
  static const _pillHeight = 44.0;
  static const _label = '返回地圖';
  static const _iconSize = 20.0;
  static const _iconGap = 6.0;
  static const _paddingH = 12.0;
  static const _labelStyle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 13,
  );

  // Hug: the pill sizes to its content (icon + gap + label) plus side padding.
  double _pillWidth(BuildContext context) {
    final tp = TextPainter(
      text: const TextSpan(text: _label, style: _labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final textWidth = tp.width;
    tp.dispose();
    return _paddingH * 2 + _iconSize + _iconGap + textWidth;
  }

  late final AnimationController _ctrl;
  late final Animation<double> _appear;
  late final Animation<double> _morph;
  late final Animation<double> _content;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 160),
      value: widget.visible ? 1 : 0,
    );
    _appear = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0, 0.4, curve: AppMotion.easeOut),
    );
    _morph = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.3, 1, curve: AppMotion.easeOut),
    );
    _content = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.65, 1, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(covariant _ReturnMapPill old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      unawaited(widget.visible ? _ctrl.forward() : _ctrl.reverse());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final appear = reduce ? (widget.visible ? 1.0 : 0.0) : _appear.value;
        if (appear == 0) return const SizedBox.shrink();
        final morph = reduce ? 1.0 : _morph.value;
        final pillWidth = _pillWidth(context);
        final width = _dotSize + (pillWidth - _dotSize) * morph;
        final height = _dotSize + (_pillHeight - _dotSize) * morph;
        return SizedBox(
          width: pillWidth,
          height: _pillHeight,
          child: Center(
            child: Opacity(
              opacity: appear,
              child: Transform.scale(
                scale: 0.85 + 0.15 * appear,
                child: Pressable(
                  onTap: widget.onTap,
                  semanticLabel: '返回地圖',
                  child: Container(
                    width: width,
                    height: height,
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(height / 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    // Lay the label out at full pill width so the shrinking
                    // container clips it rather than reflowing it.
                    child: Opacity(
                      opacity: _content.value,
                      child: OverflowBox(
                        minWidth: pillWidth,
                        maxWidth: pillWidth,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.map_rounded,
                              size: _iconSize,
                              color: cs.onPrimary,
                            ),
                            const SizedBox(width: _iconGap),
                            Text(
                              _label,
                              style: _labelStyle.copyWith(color: cs.onPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NearbyStationRow extends StatelessWidget {
  const _NearbyStationRow({
    required this.station,
    required this.onStationTap,
  });

  final NearStationViewModel station;
  final ValueChanged<NearStationViewModel> onStationTap;

  void _onTap(BuildContext context) {
    unawaited(HapticService.instance.lightTap());
    onStationTap(station);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final distance = station.routed
        ? formatNearDistance(station.distanceMeters)
        : '約 ${formatNearDistance(station.distanceMeters)}';
    final details = '步行 ${station.walkingMinutes} 分 · $distance';
    return Pressable(
      onTap: () => _onTap(context),
      semanticLabel: '${station.stationName} $details',
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border(
            top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            TransportIcon(
              type: _nearbyIconType(station),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    station.stationName,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: cs.onSurface,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 11,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          details,
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
