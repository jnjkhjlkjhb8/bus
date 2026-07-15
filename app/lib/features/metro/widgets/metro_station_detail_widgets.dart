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
              if (onClose == null)
                Pressable(
                  onTap: () {
                    unawaited(HapticService.instance.lightTap());
                    unawaited(Navigator.of(context).maybePop());
                  },
                  semanticLabel: '返回',
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              for (final code in station.id.split('_'))
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _MetroRoundel(code: code),
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(station.name, style: AppTextStyles.heading1),
                    ),
                    Text(
                      _stationLineLabel(station.id),
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
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
              // The feed keeps showing the last-known list even after its
              // ResilientSubscription gives up (state.error set) — that list
              // can go stale, so the banner is what tells the difference from
              // a genuinely current one instead of presenting it silently
              // (F28).
              final staleBanner = state.error != null
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MetroLiveErrorNotice(message: state.error!),
                    )
                  : null;
              if (arrivals.isEmpty) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?staleBanner,
                    MetroArrivalsEmpty(schedule: state.schedule),
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?staleBanner,
                  for (final (i, a) in arrivals.indexed) ...[
                    StaggerItem(
                      // Stable identity (feed upsert key) so a re-sort keeps
                      // each row paired with its own stagger delay.
                      key: ValueKey('${a.line}:${a.destination}'),
                      index: i,
                      child: MetroArrivalTile(arrival: a),
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
            // First/last-train data is loaded once and never changes per arrival
            // frame; rebuild only when the schedule itself (or its shimmer
            // condition) changes, not on every live ETA push.
            buildWhen: (p, n) =>
                p.schedule != n.schedule ||
                (p.loading && p.schedule.isEmpty) !=
                    (n.loading && n.schedule.isEmpty),
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
                    _MetroScheduleItem(
                      key: ValueKey('${s.destination}:${s.firstTime}'),
                      schedule: s,
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

/// A single metro arrival row, rendered through the shared [EtaListTile] in its
/// bare, roundel-lead configuration: line roundel leading, 往-destination in
/// heading2, and the status through the shared time column. Metro keeps its own
/// list chrome (divider-separated rows, no coming-soon highlight or tap
/// target), so it uses the tile's `bare` variant.
class MetroArrivalTile extends StatelessWidget {
  const MetroArrivalTile({required this.arrival, super.key});

  final MetroArrival arrival;

  @override
  Widget build(BuildContext context) {
    // Status mapping goes through the shared ArrivalDisplay contract so metro
    // stops re-implementing the approaching/minutes rule.
    final display = ArrivalDisplay.fromMetro(
      line: arrival.line,
      destination: arrival.destination,
      estimateMinutes: arrival.estimateMinutes,
      approaching: arrival.approaching,
    );
    return EtaListTile.fromDisplay(
      display,
      leading: TransportIcon(type: _getTransportType(arrival.line)),
      destinationStyle: AppTextStyles.heading2,
      bare: true,
    );
  }
}

class _MetroScheduleItem extends StatelessWidget {
  const _MetroScheduleItem({required this.schedule, super.key});
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
          spacing: 16,
          children: [
            _LabelledTime(label: '首', time: schedule.firstTime),
            _LabelledTime(label: '末', time: schedule.lastTime),
          ],
        ),
      ],
    );
  }
}

/// A first/last-train time preceded by its 「首」/「末」 marker.
class _LabelledTime extends StatelessWidget {
  const _LabelledTime({required this.label, required this.time});
  final String label;
  final String time;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 4),
        Text(time, style: AppTextStyles.memo),
      ],
    );
  }
}

/// Line roundel showing the line code above the station number (e.g. BR / 13),
/// filled in the line colour. Text switches to ink on light lines (e.g. Y) to
/// stay legible.
class _MetroRoundel extends StatelessWidget {
  const _MetroRoundel({required this.code});

  /// Single-line code with number, e.g. `BR14` or `G03A`.
  final String code;

  static final RegExp _split = RegExp(r'^([A-Za-z]+)(.*)$');

  @override
  Widget build(BuildContext context) {
    final match = _split.firstMatch(code);
    final letters = match?.group(1) ?? code;
    final number = match?.group(2) ?? '';
    final color = _metroLineColor(letters);
    final onColor = color.computeLuminance() > 0.5
        ? const Color(0xFF111111)
        : Colors.white;
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            letters,
            style: TextStyle(
              fontFamily: 'IBMPlexSans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1,
              color: onColor,
            ),
          ),
          if (number.isNotEmpty)
            Text(
              number,
              style: TextStyle(
                fontFamily: 'IBMPlexMono',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: onColor,
              ),
            ),
        ],
      ),
    );
  }
}

Color _metroLineColor(String lineCode) {
  switch (lineCode) {
    case 'BL':
      return AppTheme.mrtBL;
    case 'R':
      return AppTheme.mrtR;
    case 'G':
      return AppTheme.mrtG;
    case 'O':
      return AppTheme.mrtO;
    case 'BR':
      return AppTheme.mrtBR;
    case 'Y':
      return AppTheme.mrtY;
    default:
      return AppTheme.mrtBL;
  }
}

/// Whether metro service is currently running, has ended for the day, or has
/// not yet started (pre-dawn), derived from the first/last-train schedule.
enum MetroServiceState { running, ended, beforeFirst }

class MetroServiceStatus {
  const MetroServiceStatus({
    required this.state,
    this.lastTrain,
    this.firstTrain,
    this.firstDestination,
  });

  final MetroServiceState state;

  /// `HH:MM` of the latest last train across destinations (for the ended card).
  final String? lastTrain;

  /// `HH:MM` of the earliest next first train and its destination.
  final String? firstTrain;
  final String? firstDestination;
}

int? _parseHm(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Derives the service state at [now] from [schedule]. Times before 03:00 are
/// treated as belonging to the previous service day (+24h) so past-midnight
/// last trains (e.g. 00:40) compare correctly against an evening `now`.
MetroServiceStatus metroServiceStatus(
  List<MetroSchedule> schedule,
  DateTime now,
) {
  int adjust(int minutes) => minutes < 180 ? minutes + 1440 : minutes;

  int? earliestFirst;
  String? firstHm;
  String? firstDest;
  int? latestLast;
  String? lastHm;

  for (final s in schedule) {
    final f = _parseHm(s.firstTime);
    if (f != null && (earliestFirst == null || f < earliestFirst)) {
      earliestFirst = f;
      firstHm = s.firstTime;
      firstDest = s.destination;
    }
    final l = _parseHm(s.lastTime);
    if (l != null) {
      final la = adjust(l);
      if (latestLast == null || la > latestLast) {
        latestLast = la;
        lastHm = s.lastTime;
      }
    }
  }

  if (earliestFirst == null || latestLast == null) {
    return const MetroServiceStatus(state: MetroServiceState.running);
  }

  final nowAdj = adjust(now.hour * 60 + now.minute);
  final MetroServiceState state;
  if (nowAdj > latestLast) {
    state = MetroServiceState.ended;
  } else if (nowAdj < earliestFirst) {
    state = MetroServiceState.beforeFirst;
  } else {
    state = MetroServiceState.running;
  }

  return MetroServiceStatus(
    state: state,
    lastTrain: lastHm,
    firstTrain: firstHm,
    firstDestination: firstDest,
  );
}

/// Empty-arrivals content: a filled card that names why there are no trains
/// (service ended / not yet started) and the next first train, or a quiet line
/// when service is running but no live estimate is available.
class MetroArrivalsEmpty extends StatelessWidget {
  const MetroArrivalsEmpty({required this.schedule, this.now, super.key});

  final List<MetroSchedule> schedule;

  /// Injectable clock for tests; defaults to [DateTime.now].
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = schedule.isEmpty
        ? const MetroServiceStatus(state: MetroServiceState.running)
        : metroServiceStatus(schedule, now ?? DateTime.now());

    if (status.state == MetroServiceState.running) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '目前無列車資訊',
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    final ended = status.state == MetroServiceState.ended;
    final title = ended ? '今日已收班' : '尚未發車';
    final subtitle = ended && status.lastTrain != null
        ? '末班車已於 ${status.lastTrain} 發出'
        : null;
    final nextPrefix = ended ? '明日首班' : '今日首班';
    final nextLabel = status.firstDestination != null
        ? '$nextPrefix · 往 ${status.firstDestination}'
        : nextPrefix;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (status.firstTrain != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  status.firstTrain!,
                  style: AppTextStyles.memo.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  nextLabel,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
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

/// Compact inline notice shown above the arrivals list (or the empty state)
/// when the live ETA stream has failed — small on purpose, since whatever
/// arrivals are still displayed underneath it are last-known, not blanked.
class _MetroLiveErrorNotice extends StatelessWidget {
  const _MetroLiveErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.cloud_off_rounded, size: 16, color: cs.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: AppTextStyles.bodySmall.copyWith(color: cs.error),
          ),
        ),
      ],
    );
  }
}
