part of '../home_screen.dart';

enum NearbyFilter {
  all,
  mrt,
  bus,
  youbike;

  String get label {
    switch (this) {
      case NearbyFilter.all:
        return '全部';
      case NearbyFilter.mrt:
        return '捷運';
      case NearbyFilter.bus:
        return '公車';
      case NearbyFilter.youbike:
        return 'YouBike';
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        spacing: 8,
        children: NearbyFilter.values.map((filter) {
          final isSelected = filter == selectedFilter;
          return Expanded(
            child: Pressable(
              onTap: () {
                unawaited(HapticService.instance.lightTap());
                onFilterChanged(filter);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeInOut,
                height: 36,
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  filter.label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                    color: isSelected ? cs.onPrimary : cs.onSurface,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NearbyStationsTab extends StatefulWidget {
  const _NearbyStationsTab();

  @override
  State<_NearbyStationsTab> createState() => _NearbyStationsTabState();
}

class _NearbyStationsTabState extends State<_NearbyStationsTab> {
  NearbyFilter _selectedFilter = NearbyFilter.all;

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
                return ListView(
                  padding: const EdgeInsets.only(top: 8),
                  children: const [
                    ShimmerRow(height: 62),
                    ShimmerRow(height: 62),
                    ShimmerRow(height: 62),
                    ShimmerRow(height: 62),
                  ],
                );
              }
              if (state.error != null) {
                return ErrorStateView(
                  error: state.error!,
                  onRetry: () => context.read<NearbyBloc>().add(
                    const NearbyRequested(radius: _kFallbackRadiusMeters),
                  ),
                );
              }
              final items = state.stations.where(_matches).toList();
              if (items.isEmpty) {
                return const _NearbyEmpty();
              }
              return ListView(
                padding: EdgeInsets.zero,
                children: items
                    .map((s) => _NearbyStationRow(station: s))
                    .toList(),
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

class _NearbyStationRow extends StatelessWidget {
  const _NearbyStationRow({
    required this.station,
  });

  final NearStationViewModel station;

  void _onTap(BuildContext context) {
    unawaited(HapticService.instance.lightTap());
    switch (station.type) {
      case NearStationType.bus:
        unawaited(
          context.push(
            '/bus/stop',
            extra: {
              'stopName': station.stationName,
              'stopId': station.stationId,
            },
          ),
        );
      case NearStationType.bike:
        unawaited(
          context.push(
            '/bike/station',
            extra: {'stationUid': station.stationId},
          ),
        );
      case NearStationType.mrt:
        unawaited(context.push('/metro'));
      case NearStationType.tra:
      case NearStationType.thsr:
        unawaited(context.push('/rail'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final details =
        '步行 ${station.walkingMinutes} 分 · ${station.distanceMeters}m';
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
