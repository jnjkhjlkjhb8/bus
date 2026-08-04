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

    // TEMP DIAGNOSTIC (bottom-sheet drag-down bug) — remove after capture.
    return NotificationListener<SheetNotification>(
      onNotification: (n) {
        final m = n.metrics;
        final sc = PrimaryScrollController.maybeOf(context);
        final hasPos = sc != null && sc.positions.isNotEmpty;
        final pos = hasPos ? sc.positions.first : null;
        debugPrint(
          'WTC-SHEETDIAG ${n.runtimeType} '
          'off=${m.offset.toStringAsFixed(1)} '
          'min=${m.minOffset.toStringAsFixed(1)} '
          'max=${m.maxOffset.toStringAsFixed(1)} '
          'scrollPx=${pos != null ? pos.pixels.toStringAsFixed(1) : "n/a"} '
          'scrollMin='
          '${pos != null ? pos.minScrollExtent.toStringAsFixed(1) : "n/a"} '
          'scrollMax='
          '${pos != null ? pos.maxScrollExtent.toStringAsFixed(1) : "n/a"}',
        );
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async {
          context.read<MetroEtaBloc>().add(LoadMetroEta(system, station.id));
        },
        child: ListView(
          // Sizes to the rows it has (capped at the viewport, where it starts
          // scrolling), so the sheet's snap grid can stop at the end of the
          // card instead of dragging blank surface up behind a short one.
          shrinkWrap: true,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 56),
          children: [
            Row(
              children: [
                if (onClose == null)
                  Pressable(
                    onTap: () => Navigator.of(context).maybePop(),
                    semanticLabel: AppI18n.of(context).commonBack,
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
                        child: Text(
                          station.name,
                          style: AppTextStyles.heading1,
                        ),
                      ),
                      Text(
                        _stationLineLabel(AppI18n.of(context), station.id),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FavoriteToggleButton(
                  favorite: _metroFavorite(AppI18n.of(context), station),
                ),
                if (onClose != null)
                  Pressable(
                    onTap: onClose,
                    semanticLabel: AppI18n.of(context).commonClose,
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: cs.onSurface,
                      ),
                    ),
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
                  return const _MetroArrivalsSkeleton();
                }
                // The feed keeps showing the last-known list even after its
                // ResilientSubscription gives up (state.error set) — that list
                // can go stale, so the banner is what tells the difference from
                // a genuinely current one instead of presenting it silently
                // (F28).
                final staleBanner = state.error != null
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _MetroLiveErrorNotice(error: state.error!),
                      )
                    : null;
                if (arrivals.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ?staleBanner,
                      MetroArrivalsEmpty(
                        schedule: state.schedule,
                        onRetry: () => context.read<MetroEtaBloc>().add(
                          LoadMetroEta(system, station.id),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?staleBanner,
                    for (final a in arrivals) ...[
                      MetroArrivalTile(
                        key: ValueKey('${a.line}:${a.destination}'),
                        arrival: a,
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
            BlocBuilder<MetroEtaBloc, MetroEtaState>(
              // First/last-train data is loaded once and never changes per arrival
              // frame; rebuild only when the schedule itself (or its shimmer
              // condition) changes, not on every live ETA push.
              buildWhen: (p, n) =>
                  p.schedule != n.schedule ||
                  (p.loading && p.schedule.isEmpty) !=
                      (n.loading && n.schedule.isEmpty),
              builder: (context, state) => MetroScheduleSection(
                schedule: state.schedule,
                loading: state.loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Favorite _metroFavorite(AppI18n i18n, MetroMapStation s) => Favorite(
  type: FavoriteType.metroStation,
  refId: s.id,
  title: s.name,
  subtitle: _lineName(i18n, s.id),
);

/// A single metro arrival row, rendered through the shared [EtaListTile] in its
/// bare, roundel-lead configuration: line roundel leading, 往-destination in
/// heading2, and the status through the shared time column. Metro keeps its own
/// list chrome (divider-separated rows, no coming-soon highlight or tap
/// target), so it uses the tile's `bare` variant.
///
/// Below the row sits the per-car congestion strip, and — for high-capacity
/// TRTC arrivals only — the 下車提醒 bell (ADR-0015).
class MetroArrivalTile extends StatelessWidget {
  const MetroArrivalTile({required this.arrival, super.key});

  final MetroArrival arrival;

  @override
  Widget build(BuildContext context) {
    // No local countdown: metro shows the server estimate as-is, re-synced on
    // each ~15s frame. ≤0 reads as 進站中 via ArrivalDisplay.fromMetro.
    final display = ArrivalDisplay.fromMetro(
      line: arrival.line,
      destination: arrival.destination,
      estimateSeconds: arrival.estimateSeconds,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EtaListTile.fromDisplay(
          display,
          leading: TransportIcon(type: _getTransportType(arrival.line)),
          destinationStyle: AppTextStyles.heading2,
          bare: true,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _MetroCongestionStrip(levels: arrival.congestion)),
            if (arrival.supportsAlightReminder)
              _MetroAlightBell(arrival: arrival),
          ],
        ),
      ],
    );
  }
}

/// Loading stand-in for the arrivals list.
///
/// The bones sit on [MetroArrivalTile]'s own geometry — roundel lead, the
/// destination line, the time column, and the congestion strip under them,
/// divider and all — so the rows the feed delivers land where the skeleton
/// already drew them instead of shoving the schedule section down the sheet.
class _MetroArrivalsSkeleton extends StatelessWidget {
  const _MetroArrivalsSkeleton();

  /// The tile's tallest element is the mono time value: heading1's size on
  /// memo's line box. Deriving it from the same tokens keeps the skeleton
  /// honest if either token moves.
  static final double _tileRowHeight =
      AppTextStyles.heading1.fontSize! * AppTextStyles.memo.height!;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    return SkeletonFade(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            SizedBox(
              height: scaler.scale(_tileRowHeight),
              child: Row(
                children: [
                  // TransportIcon's box, at its default size.
                  const SkeletonBone(width: 24, height: 24, radius: 6),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: 0.55,
                        child: SkeletonBone(
                          height: scaler.scale(
                            AppTextStyles.heading2.fontSize!,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SkeletonBone(
                    width: scaler.scale(52),
                    height: scaler.scale(22),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              // The congestion label's line box, which is what sets the
              // strip's height in a loaded row.
              height: scaler.scale(
                AppTextStyles.bodyVerySmall.fontSize! *
                    AppTextStyles.bodyVerySmall.height!,
              ),
              child: Row(
                children: [
                  for (var car = 0; car < 6; car++) ...[
                    if (car > 0) const SizedBox(width: 3),
                    _CongestionCar(
                      color: cs.surfaceContainerHighest,
                      head: car == 0,
                    ),
                  ],
                  const SizedBox(width: 8),
                  SkeletonBone(
                    width: scaler.scale(40),
                    height: scaler.scale(10),
                  ),
                ],
              ),
            ),
            Divider(
              height: 20,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// Per-car congestion silhouette: a train of rounded cars, head car (travel
/// direction, leftmost) with a rounded nose, each car tinted by its crowding
/// level through the existing semantic status tokens. No reading — the levels
/// are a felt glance. Absent data renders muted cars with a 暫無資料 label.
class _MetroCongestionStrip extends StatelessWidget {
  const _MetroCongestionStrip({required this.levels});

  /// Per-car level (1..3) in car order; empty means the arrival carries no
  /// congestion reading.
  final List<int> levels;

  static Color _levelColor(int level) => switch (level) {
    1 => AppTheme.statusArriving,
    2 => AppTheme.statusApproach,
    3 => AppTheme.etaArriving,
    _ => AppTheme.statusArriving,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasData = levels.isNotEmpty;
    // Absent: a neutral 6-car silhouette so the row still reads as a train.
    final cars = hasData
        ? [for (final level in levels) _levelColor(level)]
        : List<Color>.filled(6, cs.surfaceContainerHighest);
    return Row(
      children: [
        Semantics(
          label: hasData
              ? AppI18n.of(context).metroCrowding
              : AppI18n.of(context).metroCrowdingUnavailable,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, color) in cars.reversed.indexed) ...[
                if (i > 0) const SizedBox(width: 3),
                _CongestionCar(color: color, head: i == 0),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          hasData
              ? AppI18n.of(context).metroCrowding
              : AppI18n.of(context).metroCrowdingUnavailableShort,
          style: AppTextStyles.bodyVerySmall.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CongestionCar extends StatelessWidget {
  const _CongestionCar({required this.color, required this.head});

  final Color color;
  final bool head;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: head
            ? const BorderRadius.horizontal(
                left: Radius.circular(3),
                right: Radius.circular(7),
              )
            : BorderRadius.circular(3),
      ),
    );
  }
}

/// The 下車提醒 bell for this train (ADR-0015).
///
/// Idle opens pick-mode and puts the rider on the line map, because that is
/// where a 下車站 is chosen — on the map screen the sheet simply steps aside,
/// and from search or the home card this navigates there first, so there is
/// only ever one way to pick a metro station.
///
/// Armed opens the manage card in place rather than cancelling on the tap: a
/// session takes several taps to build and then rides in a pocket.
class _MetroAlightBell extends StatefulWidget {
  const _MetroAlightBell({required this.arrival});

  final MetroArrival arrival;

  @override
  State<_MetroAlightBell> createState() => _MetroAlightBellState();
}

class _MetroAlightBellState extends State<_MetroAlightBell> {
  bool _managing = false;

  void _startPick() {
    context.read<MrtTrackBloc>().add(MrtAlightPickStarted(widget.arrival));
    // Already on the map: the pick state alone is enough, and navigating would
    // throw away the rider's current pan and zoom.
    if (context.findAncestorWidgetOfExactType<MetroScreen>() != null) return;
    context.go(AppRoutes.metro, extra: widget.arrival.stationId);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MrtTrackBloc, MrtTrackBlocState>(
      buildWhen: (p, n) =>
          p.tracks(widget.arrival) != n.tracks(widget.arrival) ||
          p.session != n.session,
      builder: (context, state) {
        final active = state.tracks(widget.arrival);
        final session = state.session;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AlightTrackBell(
              active: active,
              semanticLabel: active
                  ? AppI18n.of(context).alightReminderArmed
                  : AppI18n.of(context).alightReminderSet,
              onTap: () {
                if (active) {
                  setState(() => _managing = !_managing);
                } else {
                  _startPick();
                }
              },
            ),
            if (active && _managing && session != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AlightManageBar(
                  targetName: session.targetStationName,
                  lead: session.leadStops,
                  onClose: () => setState(() => _managing = false),
                  onCancel: () {
                    context.read<MrtTrackBloc>().add(const MrtTrackCancelled());
                    setState(() => _managing = false);
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
