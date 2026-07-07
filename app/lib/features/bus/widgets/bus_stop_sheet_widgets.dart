part of '../view/bus_stop_screen.dart';

class _Arrival {
  const _Arrival({
    required this.stationId,
    required this.subRouteUid,
    required this.routeNo,
    required this.destination,
    required this.status,
    required this.rank,
  });
  final String stationId;
  final String subRouteUid;
  final String routeNo;
  final String destination;
  final EtaStatus status;
  final int rank;
}

/// Maps a decoded arrival onto the tile's display status via the one shared
/// status mapping, so every service state (進站中 / 即將進站 / N分 / 尚未發車 /
/// 末班已過 / 交管不停靠 / 發車時刻) renders faithfully. The rank sorts soonest
/// first, service-state rows last.
_Arrival _toArrival(BusStopArrival a) {
  final (EtaStatus status, int rank) = switch (a.displayStatus) {
    BusStopDisplayStatus.arriving => (EtaStatus.arriving(), 0),
    BusStopDisplayStatus.departingSoon => (EtaStatus.approaching(), 1),
    BusStopDisplayStatus.minutes => (
      EtaStatus.minutes(a.minutes ?? 0),
      (a.minutes ?? 0) + 2,
    ),
    _ => (
      a.displayLabel != null
          ? EtaStatus.label(a.displayLabel!)
          : EtaStatus.unknown(),
      9999,
    ),
  };
  return _Arrival(
    stationId: a.stationId,
    subRouteUid: a.subRouteUid,
    routeNo: a.routeName,
    destination: a.destination,
    status: status,
    rank: rank,
  );
}

class _StopSheet extends StatelessWidget {
  const _StopSheet({required this.stopName});
  final String stopName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<BusStopBloc, BusStopState>(
      builder: (context, state) {
        return RefreshIndicator(
          onRefresh: () async {
            context.read<BusStopBloc>().add(const BusStopRetryRequested());
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 56),
            children: [
              const SheetDragHandle(),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _StopMeta(state: state),
              ),
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 4),
              ..._buildBody(context, state, cs),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildBody(
    BuildContext context,
    BusStopState state,
    ColorScheme cs,
  ) {
    switch (state.status) {
      case BusStopStatus.loading:
        return const [_StopSkeletonList()];
      case BusStopStatus.empty:
        return const [
          _StopMessage(
            icon: Icons.directions_bus_outlined,
            title: '此站目前無路線資訊',
            hint: '稍後再試，或確認站牌是否正確',
          ),
        ];
      case BusStopStatus.error:
        return [
          ErrorStateView(
            error: state.error ?? const OfflineError(),
            onRetry: () {
              unawaited(HapticService.instance.lightTap());
              context.read<BusStopBloc>().add(const BusStopRetryRequested());
            },
          ),
        ];
      case BusStopStatus.loaded:
        final arrivals = [for (final a in state.arrivals) _toArrival(a)]
          ..sort((a, b) => a.rank.compareTo(b.rank));
        final byStation = <String, List<_Arrival>>{};
        for (final a in arrivals) {
          byStation.putIfAbsent(a.stationId, () => []).add(a);
        }
        final members = state.members;
        final selected = state.selectedStationUid;
        final hasFilter = members.length > 1;
        final visibleMembers = selected == null
            ? members
            : members.where((m) => m.stationUid == selected).toList();
        // Section headers only earn their space when 全部 spans several stops;
        // a picked chip already names the stop.
        final showHeaders = hasFilter && selected == null;
        return [
          if (hasFilter)
            _StationFilterBar(members: members, selectedUid: selected),
          if (members.isEmpty)
            for (final (i, a) in arrivals.indexed)
              StaggerItem(
                index: i,
                child: _EtaChevronTile(
                  arrival: a,
                  highlighted: i == 0 && a.rank <= 3,
                  colorScheme: cs,
                ),
              )
          else
            for (final (memberIndex, member) in visibleMembers.indexed) ...[
              if (showHeaders) _StationSectionHeader(member: member),
              for (final (i, a)
                  in (byStation[member.stationUid] ?? const <_Arrival>[])
                      .indexed) ...[
                StaggerItem(
                  index: memberIndex * 10 + i,
                  child: _EtaChevronTile(
                    arrival: a,
                    highlighted: i == 0 && a.rank <= 3,
                    colorScheme: cs,
                  ),
                ),
                if (i < (byStation[member.stationUid]?.length ?? 0) - 1)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
              ],
            ],
          if (members.isNotEmpty && arrivals.isEmpty)
            const _StopMessage(
              icon: Icons.directions_bus_outlined,
              title: '目前沒有即時動態',
              hint: '稍後再試,或下拉重新整理',
            ),
        ];
    }
  }
}

/// Single-select filter chips, one per member stop plus 全部. Picking a chip
/// filters the list and pans the map to that stop (via [BusStopStationSelected]
/// on the bloc); labels use the stop name, never the raw StationID.
class _StationFilterBar extends StatelessWidget {
  const _StationFilterBar({required this.members, required this.selectedUid});
  final List<BusStationMember> members;
  final String? selectedUid;

  @override
  Widget build(BuildContext context) {
    final labels = _memberLabels(members);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        spacing: 8,
        children: [
          _StationChip(label: '全部', selected: selectedUid == null, uid: null),
          for (final m in members)
            _StationChip(
              label: labels[m.stationUid] ?? m.stationName,
              selected: selectedUid == m.stationUid,
              uid: m.stationUid,
            ),
        ],
      ),
    );
  }
}

class _StationChip extends StatelessWidget {
  const _StationChip({
    required this.label,
    required this.selected,
    required this.uid,
  });
  final String label;
  final bool selected;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () {
        unawaited(HapticService.instance.lightTap());
        context.read<BusStopBloc>().add(BusStopStationSelected(uid));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
            color: selected ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Chip labels from member stop names, suffixing an ordinal only where two
/// members share a name so every chip stays distinguishable without exposing
/// the raw StationID.
Map<String, String> _memberLabels(List<BusStationMember> members) {
  final counts = <String, int>{};
  for (final m in members) {
    counts[m.stationName] = (counts[m.stationName] ?? 0) + 1;
  }
  final seen = <String, int>{};
  final labels = <String, String>{};
  for (final m in members) {
    if ((counts[m.stationName] ?? 0) > 1) {
      final n = (seen[m.stationName] ?? 0) + 1;
      seen[m.stationName] = n;
      labels[m.stationUid] = '${m.stationName} $n';
    } else {
      labels[m.stationUid] = m.stationName;
    }
  }
  return labels;
}

class _StationSectionHeader extends StatelessWidget {
  const _StationSectionHeader({required this.member});
  final BusStationMember member;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        member.stationName,
        style: AppTextStyles.bodySmall.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StopMeta extends StatelessWidget {
  const _StopMeta({required this.state});
  final BusStopState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final updatedAt = state.updatedAt;
    final count = state.arrivals.length;
    final parts = <String>[
      if (state.status == BusStopStatus.loaded) '$count 條路線可搭',
      if (updatedAt != null) '更新於 ${_hhmm(updatedAt)}',
    ];
    final label = parts.isEmpty ? '即時動態' : parts.join(' · ');
    return Text(
      label,
      style: AppTextStyles.bodyRegular.copyWith(color: cs.onSurfaceVariant),
    );
  }

  static String _hhmm(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _StopMessage extends StatelessWidget {
  const _StopMessage({
    required this.icon,
    required this.title,
    required this.hint,
  });
  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
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
            style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
