part of '../view/rail_station_detail_view.dart';

/// The board's four outcomes. Two of them look like "nothing to show" and mean
/// very different things: a landed day whose trains have all gone is an answer,
/// a day that was never landed is a gap in the data.
class _BoardBody extends StatelessWidget {
  const _BoardBody({required this.system});

  final RailSystem system;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<RailStationBoardBloc, RailStationBoardState>(
        builder: (context, state) => switch (state) {
          RailStationBoardLoading() => const _BoardSkeleton(),
          RailStationBoardLoaded(:final departures) when departures.isEmpty =>
            _DayOverView(system: system, direction: state.direction),
          RailStationBoardLoaded(:final departures, :final delays) =>
            _BoardList(
              system: system,
              departures: departures,
              delays: delays,
            ),
          RailStationBoardFailure(error: NotFoundError()) => _NotLandedView(
            system: system,
          ),
          RailStationBoardFailure(:final error) => ErrorStateView(
            error: error,
            onRetry: () => context.read<RailStationBoardBloc>().add(
              RailStationBoardRequested(state.direction),
            ),
          ),
        },
      );
}

class _BoardList extends StatelessWidget {
  const _BoardList({
    required this.system,
    required this.departures,
    required this.delays,
  });

  final RailSystem system;
  final List<RailStationDeparture> departures;
  final Map<String, int> delays;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // The board is topped up from the next service date when the requested one
    // runs out, so the first row's date is the one everything above the break
    // belongs to.
    final today = departures.first.serviceDate;
    final firstTomorrow = departures.indexWhere((d) => d.serviceDate != today);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: departures.length,
      itemBuilder: (context, index) {
        final departure = departures[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A hairline between plain rows, so the list reads as one table
            // rather than a stack of floating blocks. Skipped around the
            // highlighted first row, whose tinted card already separates it,
            // and where the next-day break already draws a rule.
            if (index > 1 && index != firstTomorrow)
              Divider(
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            if (index == firstTomorrow) const _NextDayBreak(),
            _DepartureRow(
              system: system,
              departure: departure,
              delayMinutes: delays[departure.trainNo] ?? 0,
              // Only the soonest train carries a countdown. Giving every row
              // one turns the column into arithmetic the rider has to read
              // instead of scan, and buries the only number that decides
              // whether they run.
              highlighted: index == 0,
            ),
          ],
        );
      },
    );
  }
}

/// Marks where the board crosses midnight into the next service date.
class _NextDayBreak extends StatelessWidget {
  const _NextDayBreak();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Row(
        children: [
          Text(
            AppI18n.of(context).railBoardNextDay,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: cs.outlineVariant)),
        ],
      ),
    );
  }
}

/// One departure: the time to scan, where the train goes, and what it is.
class _DepartureRow extends StatelessWidget {
  const _DepartureRow({
    required this.system,
    required this.departure,
    required this.delayMinutes,
    required this.highlighted,
  });

  final RailSystem system;
  final RailStationDeparture departure;
  final int delayMinutes;
  final bool highlighted;

  /// `HH:mm:ss` on the wire; the board shows `HH:mm`, because a departure
  /// board that quotes seconds is quoting precision the timetable doesn't have.
  static String _hhmm(String time) =>
      time.length >= 5 ? time.substring(0, 5) : time;

  void _open(BuildContext context) {
    unawaited(
      // `/rail/train/...` sits outside the shell, so the train screen lands on
      // the root navigator as a full page rather than inside the sheet's box.
      context.push(
        AppRoutes.railTrain(
          departure.trainNo,
          system: system,
          date: DateTime.tryParse(departure.serviceDate),
        ),
        extra: RailTrainExtra(
          delayMinutes: delayMinutes,
          remark: departure.remark,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final suspended = departure.isSuspended;

    return Pressable(
      onTap: suspended ? null : () => _open(context),
      semanticLabel: i18n.towards(departure.destination),
      child: Container(
        // Margin + padding sum to 16 either side highlighted or not, so the
        // tint insets without shifting the row off the content column — the
        // same arithmetic EtaListTile's coming-soon highlight uses.
        margin: highlighted
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
            : EdgeInsets.zero,
        decoration: highlighted
            ? BoxDecoration(
                color: AppTheme.surfaceHighlight(cs.brightness),
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              )
            : null,
        padding: EdgeInsets.symmetric(
          horizontal: highlighted ? 8 : 16,
          vertical: 10,
        ),
        constraints: BoxConstraints(minHeight: scaler.scale(56)),
        child: Row(
          children: [
            SizedBox(
              width: scaler.scale(62),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hhmm(departure.departureTime),
                    style: AppTextStyles.timeValue(
                      size: 19,
                      weight: highlighted ? FontWeight.w600 : FontWeight.w400,
                      color: suspended ? cs.outline : cs.onSurface,
                      decoration: suspended ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (highlighted && !suspended)
                    _Countdown(departure: departure),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    i18n.towards(departure.destination),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyRegular.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: suspended ? cs.outline : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (departure.trainType.isNotEmpty) ...[
                        TrainTypeChip(type: departure.trainType, compact: true),
                        const SizedBox(width: 7),
                      ],
                      Flexible(
                        child: Text(
                          departure.trainNo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.timeValue(
                            size: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (suspended)
              Text(
                i18n.railSuspendedShort,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppTheme.trainDelay,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (delayMinutes > 0)
              Text(
                i18n.railDelayMinutes(delayMinutes),
                style: AppTextStyles.timeValue(
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: AppTheme.trainDelay,
                ),
              ),
            if (!suspended) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: cs.outline,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Minutes until the soonest train leaves, re-derived on a slow tick.
///
/// A timetable carries no live countdown, so this one is computed from the
/// device clock — which means it has to keep being recomputed. A board left
/// open on screen for five minutes that still claims "3 分後" is worse than no
/// countdown at all.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.departure});

  final RailStationDeparture departure;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  /// Half a minute: fine enough that the displayed minute is never more than
  /// 30s stale, coarse enough to cost nothing.
  static const _tick = Duration(seconds: 30);

  /// Beyond this the countdown says less than the departure time already does.
  static const _horizon = Duration(hours: 2);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final departure = widget.departure;
    final at = DateTime.tryParse(
      '${departure.serviceDate} ${departure.departureTime}',
    );
    if (at == null) return const SizedBox.shrink();
    final left = at.difference(DateTime.now());
    if (left.isNegative || left > _horizon) return const SizedBox.shrink();
    return Text(
      AppI18n.of(context).railInMinutes(left.inMinutes),
      style: AppTextStyles.timeValue(
        size: 11,
        weight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

/// The board's loading state, on the loaded row's geometry so nothing jumps
/// when the departures land.
class _BoardSkeleton extends StatelessWidget {
  const _BoardSkeleton();

  static const _rowCount = 6;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return SkeletonFade(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _rowCount,
        itemBuilder: (context, index) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          constraints: BoxConstraints(minHeight: scaler.scale(56)),
          child: Row(
            children: [
              SkeletonBone(
                width: scaler.scale(48),
                height: scaler.scale(19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SkeletonBone(
                      width: scaler.scale(96),
                      height: scaler.scale(15),
                    ),
                    const SizedBox(height: 6),
                    SkeletonBone(
                      width: scaler.scale(70),
                      height: scaler.scale(12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The requested day is landed and its trains have all gone.
class _DayOverView extends StatelessWidget {
  const _DayOverView({required this.system, required this.direction});

  final RailSystem system;
  final RailBoardDirection direction;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final label = system == RailSystem.tra
        ? (direction == RailBoardDirection.forward
              ? i18n.railDirectionForward
              : i18n.railDirectionReverse)
        : (direction == RailBoardDirection.forward
              ? i18n.railDirectionSouthbound
              : i18n.railDirectionNorthbound);
    return _BoardNotice(
      title: i18n.railBoardDayOver(label),
      body: i18n.railBoardDayOverHint,
    );
  }
}

/// The requested day was never landed — a gap in the data, not the end of it.
class _NotLandedView extends StatelessWidget {
  const _NotLandedView({required this.system});

  final RailSystem system;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    return _BoardNotice(
      title: i18n.railBoardNotLanded,
      body: i18n.railBoardNotLandedHint(
        system == RailSystem.tra ? i18n.modeTra : i18n.modeThsr,
      ),
    );
  }
}

/// A headline and one line of explanation, centred in whatever height the
/// sheet detent left. No illustration: the system is type-led and achromatic,
/// and a glyph here would be the only picture on the screen.
class _BoardNotice extends StatelessWidget {
  const _BoardNotice({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Centred in whatever height the detent left, and scrollable when the text
    // scale exceeds it — the same shape ErrorStateView uses, so the sheet's two
    // "nothing to show" screens sit in the same place.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 0.0,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The origin/destination query, demoted to a secondary action under the
/// board. It cannot be dropped: fares, arrival times and any date other than
/// today only exist on that path.
class _QueryFooter extends StatelessWidget {
  const _QueryFooter({
    required this.system,
    required this.stationId,
    required this.name,
  });

  final RailSystem system;
  final String stationId;
  final String name;

  void _openQuery(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        PagedSheetRoute<void>(
          scrollConfiguration: const SheetScrollConfiguration(),
          initialOffset: AppSheetSnap.tall,
          // Stops at tall rather than carrying on to full: the query form is
          // shorter than either detent, so the last 15% of travel adds blank
          // space and not content. Two stops that land within a hair of each
          // other also cost the grid the thing it exists for — a rider who
          // lets go can no longer tell which one they arrived at.
          snapGrid: const SheetSnapGrid(
            snaps: [AppSheetSnap.peek, AppSheetSnap.tall],
            minFlingSpeed: AppSheetSnap.flingSpeed,
          ),
          builder: (_) => HomeRailQuerySheet(
            preset: RailQueryPreset(
              system: system,
              originName: name,
              originId: stationId,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
    child: AppButton.outlined(
      label: AppI18n.of(context).railBoardQueryOd,
      onPressed: () => _openQuery(context),
    ),
  );
}
