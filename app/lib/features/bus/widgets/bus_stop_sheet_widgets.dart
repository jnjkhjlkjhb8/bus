part of '../view/bus_stop_screen.dart';

class _Arrival {
  const _Arrival({
    required this.stationId,
    required this.routeNo,
    required this.destination,
    required this.status,
    required this.rank,
    required this.progress,
    this.trackColor,
  });
  final String stationId;
  final String routeNo;
  final String destination;
  final EtaStatus status;
  final int rank;
  final double? progress;
  final Color? trackColor;
}

_Arrival _toArrival(BusStopArrival a) {
  switch (a.state) {
    case BusArrivalState.arriving:
      return _Arrival(
        stationId: a.stationId,
        routeNo: a.routeName,
        destination: a.destination,
        status: EtaStatus.arriving(),
        rank: 0,
        progress: 0.92,
        trackColor: AppTheme.statusArriving,
      );
    case BusArrivalState.scheduled:
      final m = a.minutes;
      if (m == null) {
        return _Arrival(
          stationId: a.stationId,
          routeNo: a.routeName,
          destination: a.destination,
          status: EtaStatus.unknown(),
          rank: 9999,
          progress: null,
        );
      }
      return _Arrival(
        stationId: a.stationId,
        routeNo: a.routeName,
        destination: a.destination,
        status: EtaStatus.minutes(m),
        rank: m + 2,
        progress: (1 - m / 20).clamp(0.05, 0.7),
      );
    case BusArrivalState.unknown:
      return _Arrival(
        stationId: a.stationId,
        routeNo: a.routeName,
        destination: a.destination,
        status: EtaStatus.unknown(),
        rank: 9999,
        progress: null,
      );
  }
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
        return [
          if (state.members.isNotEmpty)
            _StationMemberList(members: state.members),
          for (final (memberIndex, member) in state.members.indexed) ...[
            _StationSectionHeader(member: member),
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
          if (state.members.isEmpty)
            for (final (i, a) in arrivals.indexed)
              StaggerItem(
                index: i,
                child: _EtaChevronTile(
                  arrival: a,
                  highlighted: i == 0 && a.rank <= 3,
                  colorScheme: cs,
                ),
              ),
          if (state.members.isNotEmpty && arrivals.isEmpty)
            const _StopMessage(
              icon: Icons.directions_bus_outlined,
              title: '目前沒有 ETA',
              hint: '已顯示此組站位底下的 StationID',
            ),
        ];
    }
  }
}

class _StationMemberList extends StatelessWidget {
  const _StationMemberList({required this.members});
  final List<BusStationMember> members;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '所屬 StationID',
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final m in members)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${m.stationId} · ${m.stationName} · '
                '${m.lat.toStringAsFixed(5)}, '
                '${m.lon.toStringAsFixed(5)}',
                style: AppTextStyles.bodySmall.copyWith(color: cs.onSurface),
              ),
            ),
        ],
      ),
    );
  }
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
        '${member.stationId} ${member.stationName}',
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
