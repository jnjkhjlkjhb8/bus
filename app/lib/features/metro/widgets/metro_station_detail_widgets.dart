part of '../view/metro_station_detail_view.dart';

class _StationDetailSheet extends StatelessWidget {
  const _StationDetailSheet({
    required this.system,
    required this.station,
    this.onClose,
  });

  final String system;
  final MetroMapStation station;

  /// 關閉鈕的回呼；省略時不顯示關閉鈕（第二層 sheet 的關閉由 PagedSheet
  /// 返回手勢處理）。`/metro` 地圖內的站點面板仍會傳入此參數以顯示關閉鈕。
  final VoidCallback? onClose;

  List<String> _lines() =>
      station.id.split('_').map((p) => p.replaceAll(_digits, '')).toList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = _lines();

    return RefreshIndicator(
      onRefresh: () async {
        context.read<MetroEtaBloc>().add(LoadMetroEta(system, station.id));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 56),
        children: [
          Row(
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TransportIcon(
                    type: _getTransportType(line),
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(station.name, style: AppTextStyles.heading1),
                ),
              ),
              _MetroFavButton(station: station),
              if (onClose != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),
          BlocBuilder<MetroEtaBloc, MetroEtaState>(
            builder: (context, state) {
              final arrivals = state.arrivals
                  .where((a) => lines.contains(a.line))
                  .toList();
              if (state.loading && arrivals.isEmpty) {
                return const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [ShimmerRow(), ShimmerRow(), ShimmerRow()],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, a) in arrivals.indexed) ...[
                    StaggerItem(
                      index: i,
                      child: _ArrivalRow(arrival: a),
                    ),
                    Divider(
                      height: 20,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '首末班車資訊',
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          BlocBuilder<MetroEtaBloc, MetroEtaState>(
            builder: (context, state) {
              if (state.loading && state.schedule.isEmpty) {
                return const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [ShimmerRow(), ShimmerRow()],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final s in state.schedule) ...[
                    _MetroScheduleItem(schedule: s),
                    Divider(
                      height: 20,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

Favorite _metroFavorite(MetroMapStation s) => Favorite(
  type: FavoriteType.metroStation,
  refId: s.id,
  title: s.name,
  subtitle: _lineName(s.id),
);

class _MetroFavButton extends StatelessWidget {
  const _MetroFavButton({required this.station});

  final MetroMapStation station;

  void _toggle(BuildContext context) {
    unawaited(HapticService.instance.lightTap());
    context.read<FavoritesBloc>().add(FavoriteToggled(_metroFavorite(station)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final favorite = _metroFavorite(station);
    return BlocBuilder<FavoritesBloc, FavoritesState>(
      buildWhen: (prev, next) =>
          prev.contains(favorite.id) != next.contains(favorite.id),
      builder: (context, state) {
        final saved = state.contains(favorite.id);
        return Semantics(
          button: true,
          label: saved ? '取消收藏' : '加入收藏',
          child: IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: cs.onSurface,
            ),
            onPressed: () => _toggle(context),
          ),
        );
      },
    );
  }
}

class _ArrivalRow extends StatelessWidget {
  const _ArrivalRow({required this.arrival});

  final MetroArrival arrival;

  @override
  Widget build(BuildContext context) {
    final status = arrival.approaching
        ? EtaStatus.approaching()
        : EtaStatus.minutes(arrival.estimateMinutes);
    return Row(
      children: [
        TransportIcon(type: _getTransportType(arrival.line)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '往 ${arrival.destination}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.heading2,
          ),
        ),
        const SizedBox(width: 12),
        EtaValue(status: status),
      ],
    );
  }
}

class _MetroScheduleItem extends StatelessWidget {
  const _MetroScheduleItem({required this.schedule});
  final MetroSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          schedule.destination,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
        Row(
          spacing: 10,
          children: [
            Text(schedule.firstTime, style: AppTextStyles.memo),
            Text(schedule.lastTime, style: AppTextStyles.memo),
          ],
        ),
      ],
    );
  }
}
