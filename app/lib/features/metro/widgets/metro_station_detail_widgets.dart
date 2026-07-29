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
          'scrollMin=${pos != null ? pos.minScrollExtent.toStringAsFixed(1) : "n/a"} '
          'scrollMax=${pos != null ? pos.maxScrollExtent.toStringAsFixed(1) : "n/a"}',
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
                      head: car == 5,
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
/// direction, rightmost) with a rounded nose, each car tinted by its crowding
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
              for (final (i, color) in cars.indexed) ...[
                if (i > 0) const SizedBox(width: 3),
                _CongestionCar(color: color, head: i == cars.length - 1),
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

/// The 下車提醒 bell: outline = idle, filled (ink) = a session is active for
/// this train. Tapping an idle bell opens the setup sheet; tapping an active
/// one cancels the session (reversible — the rider can rebind). 40px circle in
/// a 44px touch target.
class _MetroAlightBell extends StatelessWidget {
  const _MetroAlightBell({required this.arrival});

  final MetroArrival arrival;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<MrtTrackBloc, MrtTrackBlocState>(
      buildWhen: (p, n) => p.tracks(arrival) != n.tracks(arrival),
      builder: (context, state) {
        final active = state.tracks(arrival);
        return Pressable(
          semanticLabel: active
              ? AppI18n.of(context).metroAlightReminderCancel
              : AppI18n.of(context).metroAlightReminderSet,
          onTap: () {
            unawaited(HapticService.instance.mediumTap());
            if (active) {
              context.read<MrtTrackBloc>().add(const MrtTrackCancelled());
            } else {
              unawaited(MrtAlightSetupSheet.show(context, arrival));
            }
          },
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? cs.onSurface : cs.surface,
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Icon(
                  active
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  size: 18,
                  color: active ? cs.surface : cs.onSurface,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The station's first/last-train times, as a two-column table.
///
/// 「首班」/「末班」 are column headers rather than a marker repeated on every
/// value: written once, they stop competing with the times, and the two mono
/// columns line up into something readable straight down. 首班 is the quieter
/// of the two — the question that brings a rider to this section after dark is
/// whether they can still get out, not when the day started.
///
/// Line grouping appears only at interchange stations. Everywhere else the
/// sheet header already names the line, and repeating it per row would be
/// noise.
class MetroScheduleSection extends StatelessWidget {
  const MetroScheduleSection({
    required this.schedule,
    this.loading = false,
    super.key,
  });

  final List<MetroSchedule> schedule;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = Text(
      AppI18n.of(context).metroFirstLastTrain,
      style: AppTextStyles.bodyLarge.copyWith(
        fontWeight: FontWeight.w600,
        color: cs.onSurfaceVariant,
      ),
    );

    // Both times sit in fixed columns so a value never shifts against the one
    // above it. The width follows the user's text scale, so large-text mode
    // widens the column instead of clipping the value.
    final columnWidth = MediaQuery.textScalerOf(context).scale(56);
    final hairline = cs.outlineVariant.withValues(alpha: 0.5);

    // The column headings are static text, so the loading state can show the
    // real header rather than a bone — the table is already legible before its
    // values arrive, and the header doesn't move when they do.
    final header = Row(
      // Baseline, not bottom: the labels are half the title's size, so
      // aligning boxes would leave them floating off its baseline.
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: title),
        _ScheduleColumnLabel(
          label: AppI18n.of(context).metroFirstTrain,
          width: columnWidth,
        ),
        _ScheduleColumnLabel(
          label: AppI18n.of(context).metroLastTrain,
          width: columnWidth,
        ),
      ],
    );

    if (loading && schedule.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          const SizedBox(height: 6),
          Divider(height: 1, thickness: 1, color: hairline),
          SkeletonFade(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 2; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: hairline),
                  _ScheduleSkeletonRow(columnWidth: columnWidth),
                ],
              ],
            ),
          ),
        ],
      );
    }
    if (schedule.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          const SizedBox(height: 8),
          Text(
            AppI18n.of(context).metroFirstLastUnavailable,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final grouped = schedule.map((s) => s.line).toSet().length > 1;

    final rows = <Widget>[];
    String? currentLine;
    for (final (i, entry) in schedule.indexed) {
      if (grouped && entry.line != currentLine) {
        currentLine = entry.line;
        rows.add(_ScheduleLineHeader(line: entry.line, first: i == 0));
      } else if (i > 0) {
        rows.add(Divider(height: 1, thickness: 1, color: hairline));
      }
      rows.add(_ScheduleRow(schedule: entry, columnWidth: columnWidth));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        const SizedBox(height: 6),
        Divider(height: 1, thickness: 1, color: hairline),
        ...rows,
      ],
    );
  }
}

/// One loading row of the first/last-train table, on [_ScheduleRow]'s exact
/// geometry: same vertical padding, same two fixed time columns.
///
/// The bones are laid over a real but invisible [_ScheduleRow]. A row of mono
/// times baseline-aligned against sans destination text is markedly taller
/// than either of its parts, and a height derived by hand would drift the
/// first time one of those styles moves; the row underneath keeps the skeleton
/// exactly as tall as the thing it stands in for, at any text scale.
class _ScheduleSkeletonRow extends StatelessWidget {
  const _ScheduleSkeletonRow({required this.columnWidth});

  final double columnWidth;

  /// Never read — it exists to be measured, so every cell carries a glyph in
  /// the style whose line box it contributes.
  static const _metrics = MetroSchedule(
    line: '',
    destination: '站',
    firstTime: '00:00',
    lastTime: '00:00',
  );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    Widget timeBone() => SizedBox(
      width: columnWidth,
      child: Align(
        alignment: Alignment.centerRight,
        child: SkeletonBone(
          width: scaler.scale(38),
          height: scaler.scale(AppTextStyles.memo.fontSize!),
        ),
      ),
    );
    return ExcludeSemantics(
      child: Stack(
        children: [
          Opacity(
            opacity: 0,
            child: _ScheduleRow(schedule: _metrics, columnWidth: columnWidth),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: 0.45,
                        child: SkeletonBone(
                          height: scaler.scale(
                            AppTextStyles.bodyRegular.fontSize!,
                          ),
                        ),
                      ),
                    ),
                  ),
                  timeBone(),
                  timeBone(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleColumnLabel extends StatelessWidget {
  const _ScheduleColumnLabel({required this.label, required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Excluded from semantics: each row announces its own 首班/末班 values, so
    // a screen reader that also read the headers would hear them twice with
    // no positional cue tying them to a value.
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        child: Text(
          label,
          textAlign: TextAlign.right,
          style: AppTextStyles.bodyVerySmall.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Line divider inside the table at interchange stations: the line's roundel
/// and full name over the destinations it runs to.
class _ScheduleLineHeader extends StatelessWidget {
  const _ScheduleLineHeader({required this.line, required this.first});

  final String line;

  /// Whether this is the first group; it sits tighter under the column
  /// headers than the groups that follow a preceding block of rows.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: first ? 12 : 18, bottom: 4),
      child: Row(
        children: [
          LineBadge(
            label: line,
            color: _metroLineColor(line),
            svgAsset: LineBadge.trtcAsset(line),
            size: 18,
          ),
          const SizedBox(width: 7),
          Text(
            _kLineNames(AppI18n.of(context))[line] ?? line,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.schedule, required this.columnWidth});

  final MetroSchedule schedule;
  final double columnWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: AppI18n.of(context).metroFirstLastSemanticsFull(
        schedule.destination,
        schedule.firstTime,
        schedule.lastTime,
      ),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: AppI18n.of(context).towardsPrefix,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    TextSpan(text: schedule.destination),
                  ],
                ),
                style: AppTextStyles.bodyRegular.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
            _ScheduleTime(
              time: schedule.firstTime,
              width: columnWidth,
              color: cs.onSurfaceVariant,
            ),
            _ScheduleTime(
              time: schedule.lastTime,
              width: columnWidth,
              color: cs.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleTime extends StatelessWidget {
  const _ScheduleTime({
    required this.time,
    required this.width,
    required this.color,
  });

  final String time;
  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        time,
        textAlign: TextAlign.right,
        style: AppTextStyles.memo.copyWith(
          color: color,
          fontFeatures: AppTextStyles.tabularFigures,
        ),
      ),
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
          // Glyph-like line badges: the 30x30 box is fixed by the map's
          // visual language, so these opt out of the user's text-scale
          // setting rather than overflow (and lose the number) at large
          // font sizes.
          Text(
            letters,
            textScaler: TextScaler.noScaling,
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
              textScaler: TextScaler.noScaling,
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
  const MetroArrivalsEmpty({
    required this.schedule,
    this.now,
    this.onRetry,
    super.key,
  });

  final List<MetroSchedule> schedule;

  /// Injectable clock for tests; defaults to [DateTime.now].
  final DateTime? now;

  /// Re-issues the load event; shown as a text action only when non-null.
  /// Only wired for the `running` branch — the `ended`/`beforeFirst` cards
  /// are a factual read of the schedule, not a live-feed failure, so they
  /// have nothing to retry.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = schedule.isEmpty
        ? const MetroServiceStatus(state: MetroServiceState.running)
        : metroServiceStatus(schedule, now ?? DateTime.now());

    if (status.state == MetroServiceState.running) {
      // Service is running per the schedule, yet the feed pushed nothing —
      // that's a live-data gap, not an absence of trains (B1). Say so
      // explicitly instead of the old blanket "no trains" line, which lied
      // whenever the feed was merely silent.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppI18n.of(context).metroEtaUnavailable,
              style: AppTextStyles.bodyRegular.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              AppI18n.of(context).metroEtaUnavailableBody,
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              // A recovery hint, not the primary action on the screen — plain
              // text per the design system's Text/Tertiary style, not a
              // filled button.
              Pressable(
                onTap: onRetry,
                semanticLabel: AppI18n.of(context).commonReload,
                child: Text(
                  AppI18n.of(context).commonReload,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final i18n = AppI18n.of(context);
    final ended = status.state == MetroServiceState.ended;
    final title = ended
        ? AppI18n.of(context).metroServiceEnded
        : AppI18n.of(context).metroServiceNotStarted;
    final subtitle = ended && status.lastTrain != null
        ? i18n.metroLastTrainDeparted(status.lastTrain!)
        : null;
    final nextPrefix = ended
        ? i18n.metroFirstTrainTomorrow
        : i18n.metroFirstTrainToday;
    final nextLabel = status.firstDestination != null
        ? i18n.metroFirstTrainTowards(nextPrefix, status.firstDestination!)
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
  const _MetroLiveErrorNotice({required this.error});

  final AppError error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.cloud_off_rounded, size: 16, color: cs.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            error.titleOf(AppI18n.of(context)),
            style: AppTextStyles.bodySmall.copyWith(color: cs.error),
          ),
        ),
      ],
    );
  }
}
