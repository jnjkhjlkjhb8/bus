import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/core/haptics/haptic_service.dart';
import 'package:wheres_the_bus/data/models/fare_type.dart';
import 'package:wheres_the_bus/data/models/plan_models.dart';
import 'package:wheres_the_bus/data/models/rail_fare_quote.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_bus/features/live_activity/model/journey_models.dart';
import 'package:wheres_the_bus/features/rail/bloc/rail_train_bloc.dart';
import 'package:wheres_the_bus/features/rail/bloc/rail_train_event.dart';
import 'package:wheres_the_bus/features/rail/bloc/rail_train_state.dart';
import 'package:wheres_the_bus/features/rail/booking_launch.dart';
import 'package:wheres_the_bus/features/rail/rail_timetable_derivation.dart';
import 'package:wheres_the_bus/features/rail/widgets/rail_booking_sheet.dart';
import 'package:wheres_the_bus/features/rail/widgets/rail_service_marks.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/widgets/alight_track/alight_track_bell.dart';
import 'package:wheres_the_bus/shared/widgets/alight_track/alight_track_sheet.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';
import 'package:wheres_the_bus/shared/widgets/app_bars.dart';
import 'package:wheres_the_bus/shared/widgets/app_card.dart';
import 'package:wheres_the_bus/shared/widgets/app_spinner.dart';
import 'package:wheres_the_bus/shared/widgets/bookmark_button.dart';
import 'package:wheres_the_bus/shared/widgets/error_state_view.dart';
import 'package:wheres_the_bus/shared/widgets/fare_preference.dart';
import 'package:wheres_the_bus/shared/widgets/route_tab_bar.dart';
import 'package:wheres_the_bus/shared/widgets/train_type_chip.dart';
import 'package:wheres_the_bus/shared/widgets/transit_timeline.dart';

/// Board→alight scheduled stops (inclusive) that ride on a rail track leg so
/// the live tracker can derive 還剩 N 站 / progress / ETA from the timetable
/// after this screen is gone (see `defaultRailTrackStream`). Empty when the
/// segment is degenerate or any stop time is unparseable — the session then
/// falls back to a plain scheduled countdown.
List<RailStopSchedule> railTrackSchedule(
  List<RailTrainStop> stops,
  String serviceDate, {
  required String board,
  required String alight,
}) {
  final b = stops.indexWhere((s) => sameStation(s.name, board));
  final a = stops.indexWhere((s) => sameStation(s.name, alight));
  if (b < 0 || a <= b) return const [];
  final out = <RailStopSchedule>[];
  for (var i = b; i <= a; i++) {
    final s = stops[i];
    final raw = s.arrive.isNotEmpty ? s.arrive : s.depart;
    final t = DateTime.tryParse('$serviceDate ${hhmm(raw)}');
    if (t == null) return const [];
    out.add(RailStopSchedule(name: s.name, scheduledArrival: t));
  }
  return out;
}

// Built per call rather than held in a const map: the names follow the
// rider's language.
Map<int, String> _weekdayLabels(AppI18n i18n) => {
  DateTime.monday: i18n.weekdayMon,
  DateTime.tuesday: i18n.weekdayTue,
  DateTime.wednesday: i18n.weekdayWed,
  DateTime.thursday: i18n.weekdayThu,
  DateTime.friday: i18n.weekdayFri,
  DateTime.saturday: i18n.weekdaySat,
  DateTime.sunday: i18n.weekdaySun,
};

/// Matches the results-list header format (`rail_screen.dart`'s
/// `_formatDateDisplay`) so the same date doesn't read as two different
/// formats across the two screens a user compares side by side. Reimplemented
/// locally rather than imported: that copy is private, behind a `part`
/// boundary this file isn't part of.
String _formatDateDisplay(AppI18n i18n, String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate.replaceAll('-', '/');
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  return '$mm/$dd (${_weekdayLabels(i18n)[date.weekday]})';
}

class RailTrainScreen extends StatefulWidget {
  const RailTrainScreen({
    required this.type,
    required this.trainNo,
    required this.date,
    this.userOrigin,
    this.userDest,
    this.delayMinutes = 0,
    this.marks = const [],
    this.remark = '',
    super.key,
  });

  final String type;
  final String trainNo;

  /// Service date in `yyyy-MM-dd`.
  final String date;

  /// The stations the user actually searched for, when this screen was opened
  /// from an O/D timetable result. The train's own run is usually longer, so
  /// the fare and the stop list must be scoped to this segment rather than to
  /// the full run — otherwise the two screens quote different prices for what
  /// the user reads as the same trip. Null when opened by train number alone.
  final String? userOrigin;
  final String? userDest;

  /// Live delay in minutes for this train, when the caller had it (the O/D
  /// result list subscribes to delays; this screen does not). Folded into the
  /// 追蹤 countdown so it reflects the actual 誤點 rather than the timetable.
  final int delayMinutes;

  /// Service marks and 備註 for this train, carried from the timetable list.
  /// Neither travels on the stop-times RPC this screen calls, so a screen
  /// opened by train number alone (the 車次查詢 path) simply shows neither
  /// rather than quoting a second, emptier set of facts about the same train.
  final List<RailServiceMark> marks;
  final String remark;

  @override
  State<RailTrainScreen> createState() => _RailTrainScreenState();
}

class _RailTrainScreenState extends State<RailTrainScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final RailTrainBloc _bloc;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _bloc = RailTrainBloc(
      type: widget.type,
      trainNo: widget.trainNo,
      date: widget.date,
      userOrigin: widget.userOrigin,
      userDest: widget.userDest,
    )..add(const RailTrainStarted());
  }

  @override
  void dispose() {
    _tabController.dispose();
    unawaited(_bloc.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trainLabel = TrainTypeChip.canonicalLabel(
      AppI18n.of(context),
      widget.type,
    );

    return BlocProvider.value(
      value: _bloc,
      child: Scaffold(
        appBar: DetailAppBar(
          title: '$trainLabel ${widget.trainNo}',
          subtitle: _formatDateDisplay(AppI18n.of(context), widget.date),
          actions: [
            // 追蹤 sits here rather than on the result card: the card header
            // could not hold chip, number, fare, 追蹤 and 訂購 on one line even
            // at the default text scale, and tracking is a deliberate act on a
            // chosen train, not something glanced at down a list.
            BlocBuilder<RailTrainBloc, RailTrainState>(
              builder: (context, state) => _TrackButton(
                trainLabel: trainLabel,
                trainNo: widget.trainNo,
                date: widget.date,
                isThsr: widget.type == '高鐵',
                delayMinutes: state.liveDelayMinutes ?? widget.delayMinutes,
                stops: state.stops,
                userOrigin: widget.userOrigin,
                userDest: widget.userDest,
              ),
            ),
            BookmarkButton(
              routeType: widget.type,
              routeKey: widget.trainNo,
              routeLabel: '${widget.type} ${widget.trainNo}',
            ),
          ],
        ),
        // 訂購 is this screen's primary commit action, so it sits pinned at
        // the bottom within thumb reach rather than as a third icon in an app
        // bar that already holds two toggles. It also puts the action and its
        // price in one line — "spend NT$ 99 on this train" is one sentence,
        // and splitting it across two places makes the user reassemble it.
        // Only shown once the stops load: before that there is no fare and no
        // confirmed train to book.
        bottomNavigationBar: BlocBuilder<RailTrainBloc, RailTrainState>(
          builder: (context, state) {
            if (state.status != RailTrainStatus.loaded) {
              return const SizedBox.shrink();
            }
            // Scoped to the user's own boarding stop when known, so a THSR
            // hand-off pre-fills the departure they searched rather than the
            // train's first stop hours up the line.
            final boarding = widget.userOrigin == null
                ? state.stops.firstOrNull
                : state.stops
                      .where((s) => sameStation(s.name, widget.userOrigin!))
                      .firstOrNull;
            return _BookingBar(
              isThsr: widget.type == '高鐵',
              trainNo: widget.trainNo,
              date: widget.date,
              origin: widget.userOrigin ?? state.stops.firstOrNull?.name ?? '',
              destination:
                  widget.userDest ?? state.stops.lastOrNull?.name ?? '',
              departTime: hhmm(
                (boarding?.depart.isNotEmpty ?? false)
                    ? boarding!.depart
                    : (boarding?.arrive ?? ''),
              ),
              // The user's own segment is what the timetable quoted, so it is
              // the number to repeat here; the full run is the fallback.
              fareQuote: state.userFare ?? state.fullFare,
              trainType: widget.type,
              // Carried from the timetable list; a screen opened by train
              // number alone has no marks, so 兩鐵 stays hidden rather than
              // being offered on a train that may not take bicycles.
              hasBikeService: widget.marks.contains(RailServiceMark.bike),
            );
          },
        ),
        body: BlocBuilder<RailTrainBloc, RailTrainState>(
          builder: (context, state) {
            switch (state.status) {
              case RailTrainStatus.loading:
                return const Center(child: AppSpinner());
              case RailTrainStatus.error:
                return ErrorStateView(
                  error: state.error ?? const UnknownError(),
                  onRetry: () => _bloc.add(const RailTrainStarted()),
                );
              case RailTrainStatus.empty:
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      // Name the train and date, and give the one next step
                      // that actually helps — a bare "not found" leaves the
                      // user unsure whether the number was wrong or the date
                      // was.
                      AppI18n.of(context).railTrainNotFound(
                        trainLabel,
                        widget.trainNo,
                        _formatDateDisplay(AppI18n.of(context), widget.date),
                      ),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyRegular.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              case RailTrainStatus.loaded:
                return Column(
                  children: [
                    RouteTabBar(
                      controller: _tabController,
                      tabs: [
                        AppI18n.of(context).railTabTimetable,
                        AppI18n.of(context).railTabDetails,
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _TimetableTab(
                            stops: state.stops,
                            serviceDate: widget.date,
                            delayMinutes:
                                state.liveDelayMinutes ?? widget.delayMinutes,
                            userOrigin: widget.userOrigin,
                            alight: widget.userDest,
                          ),
                          _InfoTab(
                            type: widget.type,
                            trainNo: widget.trainNo,
                            stops: state.stops,
                            fullFare: state.fullFare,
                            userFare: state.userFare,
                            userOrigin: widget.userOrigin,
                            userDest: widget.userDest,
                            marks: widget.marks,
                            remark: widget.remark,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
            }
          },
        ),
      ),
    );
  }
}

/// The pinned 訂購 action. Opens the operator's own booking flow — the app
/// never sells tickets itself — so the label says where the tap leads.
class _BookingBar extends StatelessWidget {
  const _BookingBar({
    required this.isThsr,
    required this.trainNo,
    required this.date,
    required this.origin,
    required this.destination,
    required this.departTime,
    required this.fareQuote,
    required this.trainType,
    required this.hasBikeService,
  });

  final bool isThsr;
  final String trainNo;

  /// Backend train-type label, and whether this train carries bicycles. They
  /// gate the TRA booking classes: 騰雲座艙 exists only on 新自強, 兩鐵 only on
  /// bike-carrying trains.
  final String trainType;
  final bool hasBikeService;
  final String date;
  final String origin;
  final String destination;

  /// `HH:mm` departure from [origin]. THSR's deeplink needs it; TRA ignores it.
  final String departTime;

  /// Fares for this journey, or null when the fare query landed no data. The
  /// price shown is the one matching the rider's ticket type; a quote that
  /// resolves to nothing drops the price from the label rather than quoting 0,
  /// since no TRA/THSR O/D costs NT$0.
  final RailFareQuote? fareQuote;

  // Opens the booking sheet rather than handing off directly. Both operators
  // take options the deeplink carries — THSR a cabin and five per-category
  // counts, TRA a booking class and a quantity — and the sheet exchanges the
  // deeplink in the background, so the tap no longer blocks on a round-trip.
  void _openSheet(BuildContext context) {
    unawaited(HapticService.instance.lightTap());
    unawaited(
      showRailBookingSheet(
        context,
        RailBookingRequest(
          isThsr: isThsr,
          origin: origin,
          destination: destination,
          date: date,
          time: departTime,
          trainNumber: trainNo,
        ),
        trainType: trainType,
        hasBikeService: hasBikeService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Pressable(
            onTap: () => _openSheet(context),
            semanticLabel: AppI18n.of(context).railBookTicketSemantics(trainNo),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppI18n.of(context).railBook,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  // The price the rider is actually quoted, so the action and
                  // the number they will pay stay one sentence. A concession
                  // fare names its type here: 'NT$ 63' alone beside 訂購 would
                  // read as the standard price on a screen where it is not.
                  FarePreferenceBuilder(
                    builder: (context, fareType) {
                      final resolved = fareQuote?.resolve(fareType);
                      if (resolved == null || resolved.price <= 0) {
                        return const SizedBox.shrink();
                      }
                      final suffix = resolved.matched == FareType.full
                          ? ''
                          : ' ${resolved.matched.labelOf(AppI18n.of(context))}';
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          'NT\$ ${resolved.price}$suffix',
                          style: AppTextStyles.memo.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onPrimary.withValues(alpha: 0.82),
                            fontFeatures: AppTextStyles.tabularFigures,
                          ),
                        ),
                      );
                    },
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

class _TimetableTab extends StatefulWidget {
  const _TimetableTab({
    required this.stops,
    required this.serviceDate,
    required this.delayMinutes,
    required this.alight,
    this.userOrigin,
  });

  final List<RailTrainStop> stops;
  final String serviceDate;

  /// Live 誤點 for this train, when the caller had it. Shifts the position
  /// marker; the printed times stay as printed, because that is what the
  /// station announcements and the ticket say.
  final int delayMinutes;

  /// The station the rider boards at — their searched origin, or the train's
  /// own first stop.
  final String? userOrigin;

  /// The station the rider gets off at, from the O/D they searched, or null
  /// when they opened this train by number alone. Both ends come from the
  /// search and are read-only here: tapping a row must not silently re-point
  /// the fare, 追蹤 and the booking hand-off at a different trip.
  final String? alight;

  @override
  State<_TimetableTab> createState() => _TimetableTabState();
}

class _TimetableTabState extends State<_TimetableTab> {
  /// Stops the train has already called at stay collapsed behind one line: a
  /// 區間車 runs ~30 stations, and opening the list on the part that has
  /// already happened costs the rider the scroll every time.
  bool _showPast = false;

  int _indexOf(String? name, int fallback) {
    if (name == null) return fallback;
    for (var i = 0; i < widget.stops.length; i++) {
      if (sameStation(widget.stops[i].name, name)) return i;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final stops = widget.stops;
    final last = stops.length - 1;
    final boardIndex = _indexOf(widget.userOrigin, 0);
    final alightIndex = widget.alight == null
        ? null
        : _indexOf(widget.alight, last);
    final position = railPositionIndex(
      stops,
      widget.serviceDate,
      widget.delayMinutes,
      DateTime.now(),
    );

    // Only worth a collapse when it actually hides something: at one passed
    // stop the summary line costs as much room as the row it replaces.
    final collapseUntil = (position != null && position >= 2 && !_showPast)
        ? position - 1
        : -1;

    final children = <Widget>[];
    if (collapseUntil >= 0) {
      children.add(
        _PassedStopsSummary(
          count: collapseUntil + 1,
          names: stops.take(collapseUntil + 1).map((s) => s.name).toList(),
          onExpand: () => setState(() => _showPast = true),
        ),
      );
    }

    // One decision for the whole list, not one per row: a column that appears
    // on some rows and not others is a column whose x moves.
    final showElapsed = boardIndex < last;

    for (var i = collapseUntil + 1; i < stops.length; i++) {
      final stop = stops[i];
      final travelled = position != null && i <= position;
      children.add(
        _StopRow(
          stop: stop,
          isFirst: i == 0,
          isLast: i == last,
          elapsed: i > boardIndex
              ? elapsedMinutes(widget.serviceDate, stops[boardIndex], stop)
              : null,
          // The spine's covered track ends at the train, so the segment above
          // the marker row is solid and everything past it is not.
          travelledAbove: travelled,
          travelledBelow: position != null && i < position,
          isBoard: widget.userOrigin != null && i == boardIndex,
          isAlight: alightIndex != null && i == alightIndex,
          showElapsed: showElapsed,
        ),
      );
    }

    return Column(
      children: [
        _TimetableColumnHeader(showElapsed: showElapsed),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: children),
        ),
      ],
    );
  }
}

class _TimetableColumnHeader extends StatelessWidget {
  const _TimetableColumnHeader({required this.showElapsed});

  /// The 歷時 column is only meaningful when there is a downstream segment to
  /// measure; a rider boarding at the terminus has nothing to accumulate.
  final bool showElapsed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = AppTextStyles.bodyVerySmall.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(kTimelineGutter, 8, 16, 6),
      child: Row(
        children: [
          Text(AppI18n.of(context).railColStation, style: style),
          const Spacer(),
          // Same fixed widths as the rows below, so each heading sits over its
          // own column rather than over wherever that row's content ended.
          SizedBox(
            width: scaledWidth(context, _StopRow.timeWidth),
            child: Text(
              AppI18n.of(context).railColTime,
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          if (showElapsed) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: scaledWidth(context, _StopRow.elapsedWidth),
              child: Text(
                AppI18n.of(context).railColElapsed,
                textAlign: TextAlign.right,
                style: style,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PassedStopsSummary extends StatelessWidget {
  const _PassedStopsSummary({
    required this.count,
    required this.names,
    required this.onExpand,
  });

  final int count;
  final List<String> names;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Name the first few so the collapse is verifiable at a glance rather than
    // asking the rider to expand just to confirm which stops it swallowed.
    final preview = names.take(3).join('、');
    final suffix = names.length > 3 ? '⋯' : '';

    return Pressable(
      onTap: onExpand,
      semanticLabel: AppI18n.of(context).railStopsPassed(count),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(0, 9, 16, 9),
        child: Row(
          children: [
            SizedBox(
              width: kTimelineGutter,
              child: Center(
                child: Container(
                  width: 2,
                  height: 22,
                  decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text(
                AppI18n.of(
                  context,
                ).railStopsPassedPreview(count, '$preview$suffix'),
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.isFirst,
    required this.isLast,
    required this.elapsed,
    required this.travelledAbove,
    required this.travelledBelow,
    required this.isBoard,
    required this.isAlight,
    required this.showElapsed,
  });

  final RailTrainStop stop;

  /// Origin stop of the train's run: an arrival time here is meaningless.
  final bool isFirst;

  /// Terminus stop of the train's run: a departure time here is meaningless.
  final bool isLast;

  /// Minutes from the boarding stop, or null upstream of it.
  final int? elapsed;

  final bool travelledAbove;
  final bool travelledBelow;
  final bool isBoard;
  final bool isAlight;

  /// Whether the 歷時 column exists on this list at all. Uniform across every
  /// row so the column keeps one x; a per-row decision is what let the times
  /// wander in the first place.
  final bool showElapsed;

  /// The two right-hand columns are fixed-width, because a timetable is only
  /// scannable while its figures stack into columns the eye can run straight
  /// down. Sized for the widest content each holds at text scale 1 — '18:08'
  /// in 15px mono, '+34分' in 12px mono.
  static const double timeWidth = 58;
  static const double elapsedWidth = 46;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final marked = isBoard || isAlight;
    final primaryTime = isFirst
        ? stop.depart
        : (stop.arrive.isNotEmpty ? stop.arrive : stop.depart);
    // TRA prints a one-minute dwell at nearly every station: the default, not
    // information. Only a wait worth noticing is called out.
    final dwell = isLast ? 0 : dwellMinutes(stop);

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      // The static, non-pulsing highlight the design system reserves for
      // "find this row" cases — fill and weight only, no new colour.
      color: isAlight ? cs.surfaceContainerHighest : null,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TimelineSpine(
              kind: marked
                  ? TimelineNodeKind.emphasis
                  : (isFirst || isLast
                        ? TimelineNodeKind.terminus
                        : TimelineNodeKind.intermediate),
              lineAbove: !isFirst,
              lineBelow: !isLast,
              travelledAbove: travelledAbove,
              travelledBelow: travelledBelow,
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(0, 11, 16, 11),
                child: Row(
                  children: [
                    // One Expanded owns all the slack, rather than a Flexible
                    // name next to a Spacer: two flex-1 children split the free
                    // space in half each, the name leaves its half part-used,
                    // and the unused remainder lands after the time columns —
                    // which is what pushed the times off the heading's x by a
                    // different amount on every row.
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              stop.name,
                              style: AppTextStyles.bodyRegular.copyWith(
                                height: 1.3,
                                fontWeight: marked ? FontWeight.w700 : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isBoard) ...[
                            const SizedBox(width: 6),
                            TimelineStopTag(
                              AppI18n.of(context).railBoard,
                              solid: false,
                            ),
                          ],
                          if (isAlight) ...[
                            const SizedBox(width: 6),
                            TimelineStopTag(AppI18n.of(context).railAlight),
                          ],
                          // The dwell note rides in the flexible area rather
                          // than in the time slot: a variable-width note inside
                          // a fixed column either clips or drags it off its x.
                          if (dwell >= 2) ...[
                            const SizedBox(width: 8),
                            Text(
                              AppI18n.of(context).railDwellMinutes(dwell),
                              style: AppTextStyles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      width: scaledWidth(context, timeWidth),
                      child: Text(
                        primaryTime.isEmpty ? '' : hhmm(primaryTime),
                        textAlign: TextAlign.right,
                        style: AppTextStyles.memo.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                          fontFeatures: AppTextStyles.tabularFigures,
                        ),
                      ),
                    ),
                    // Reserved even when this row has no figure, so the column
                    // holds its x down the whole list instead of every
                    // upstream row shunting the times right by its width.
                    if (showElapsed) ...[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: scaledWidth(context, elapsedWidth),
                        child: Text(
                          elapsed == null
                              ? ''
                              : AppI18n.of(context).railElapsedPlus(elapsed!),
                          textAlign: TextAlign.right,
                          style: AppTextStyles.memo.copyWith(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                            fontFeatures: AppTextStyles.tabularFigures,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({
    required this.type,
    required this.trainNo,
    required this.stops,
    required this.fullFare,
    required this.userFare,
    this.userOrigin,
    this.userDest,
    this.marks = const [],
    this.remark = '',
  });

  final String type;
  final String trainNo;
  final List<RailTrainStop> stops;

  /// Amenities this train carries, shown here in the operator's own artwork
  /// with labels — the timetable list only had room for muted silhouettes.
  final List<RailServiceMark> marks;

  /// Operator free text about this train, e.g. "本車次不停靠苗栗、彰化、雲林
  /// 站". Variable length, so it belongs here rather than in a list row where
  /// it would break the alignment the timetable depends on.
  final String remark;

  /// Fare for the train's own full run (its first stop to its last),
  /// best-effort and possibly null.
  final RailFareQuote? fullFare;

  /// Fare for the segment the user actually searched, when known — the
  /// number an O/D result list already showed, so this (not [fullFare]) is
  /// the headline figure once available. See RailTrainBloc for why quoting
  /// the wrong one used to price the same trip two different ways.
  final RailFareQuote? userFare;
  final String? userOrigin;
  final String? userDest;

  static const TextStyle _labelStyle = AppTextStyles.bodyLarge;
  static const TextStyle _valueStyle = AppTextStyles.heading2;

  RailTrainStop? _findStop(String name) {
    for (final s in stops) {
      if (sameStation(s.name, name)) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Match the user's searched station names back into this train's own
    // stop list so every row below quotes that stop's actual scheduled time
    // rather than mixing a user-supplied name with the full run's times.
    // Falls back to the full run when a name can't be matched (e.g. a
    // formatting difference between the search source and the stop list) so
    // the 起迄站 and 行駛時間 rows can never disagree with each other.
    final userOriginStop = userOrigin != null ? _findStop(userOrigin!) : null;
    final userDestStop = userDest != null ? _findStop(userDest!) : null;
    final showUserSegment = userOriginStop != null && userDestStop != null;
    final isFullRun =
        !showUserSegment ||
        (userOriginStop.name == stops.first.name &&
            userDestStop.name == stops.last.name);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          _buildTrainInfo(
            AppI18n.of(context),
            cs,
            userOriginStop,
            userDestStop,
            showUserSegment,
            isFullRun,
          ),
          if (userFare != null || fullFare != null)
            _buildFare(
              cs,
              userOriginStop,
              userDestStop,
              showUserSegment,
              isFullRun,
            ),
          if (remark.trim().isNotEmpty) ...[
            Divider(height: 1, thickness: 0.5, color: cs.outlineVariant),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 5,
              children: [
                Text(
                  AppI18n.of(context).commonNote,
                  style: _labelStyle.copyWith(color: cs.onSurfaceVariant),
                ),
                Row(
                  spacing: 5,
                  children: [
                    if (marks.isNotEmpty) ...[
                    RailServiceMarkChips(marks: marks),
                    ],
                    Text(
                      remark.trim(),
                      style: AppTextStyles.bodyRegular.copyWith(
                        color: cs.onSurface,
                      ),
                    )
                  ]
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrainInfo(
    AppI18n i18n,
    ColorScheme cs,
    RailTrainStop? userOriginStop,
    RailTrainStop? userDestStop,
    bool showUserSegment,
    bool isFullRun,
  ) {
    final runOrigin = stops.first;
    final runDest = stops.last;

    // Product decision: the user's own segment is the primary information,
    // the train's full run is secondary context — so it, not the run, is
    // the headline once we have it.
    final headlineOrigin = showUserSegment ? userOriginStop! : runOrigin;
    final headlineDest = showUserSegment ? userDestStop! : runDest;

    final departTime = hhmm(
      headlineOrigin.depart.isNotEmpty
          ? headlineOrigin.depart
          : headlineOrigin.arrive,
    );
    final arriveTime = hhmm(
      headlineDest.arrive.isNotEmpty
          ? headlineDest.arrive
          : headlineDest.depart,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Text(
              i18n.railTrainAndType,
              style: _labelStyle.copyWith(color: cs.onSurfaceVariant),
            ),
            Row(
              children: [
                Text(trainNo, style: _valueStyle),
                const SizedBox(width: 10),
                TrainTypeChip(type: type),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 5,
          children: [
            Text(
              i18n.railEndpoints,
              style: _labelStyle.copyWith(color: cs.onSurfaceVariant),
            ),
            Row(
              spacing: 6,
              children: [
                Text(headlineOrigin.name, style: _valueStyle),
                const Text('→', style: _valueStyle),
                Text(headlineDest.name, style: _valueStyle),
              ],
            ),
            // Secondary context, only shown when it actually differs from
            // the headline above — the train's full route, not the user's
            // slice of it.
            if (showUserSegment && !isFullRun)
              Text(
                i18n.railFullRun(runOrigin.name, runDest.name),
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
        Divider(height: 1, thickness: 0.5, color: cs.outlineVariant),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 5,
          children: [
            Text(
              i18n.railRunningTime,
              style: _labelStyle.copyWith(color: cs.onSurfaceVariant),
            ),
            Row(
              spacing: 6,
              children: [
                Text(departTime, style: _valueStyle),
                const Text('→', style: _valueStyle),
                Text(arriveTime, style: _valueStyle),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFare(
    ColorScheme cs,
    RailTrainStop? userOriginStop,
    RailTrainStop? userDestStop,
    bool showUserSegment,
    bool isFullRun,
  ) {
    final runOrigin = stops.first;
    final runDest = stops.last;

    return FarePreferenceBuilder(
      builder: (context, fareType) {
        final i18n = AppI18n.of(context);
        final userResolved = userFare?.resolve(fareType);
        final fullResolved = fullFare?.resolve(fareType);
        final useUserFare = showUserSegment && userResolved != null;
        final primary = useUserFare ? userResolved : fullResolved;
        final primaryLabel = useUserFare
            ? '${userOriginStop!.name} → ${userDestStop!.name}'
            : i18n.railRunPair(runOrigin.name, runDest.name);

        // A second figure never appears without saying what it prices — that
        // ambiguity (an unlabelled full-run fare beside a list that already
        // quoted the segment fare) is the P0 bug this screen used to have.
        Widget? secondary;
        if (useUserFare && !isFullRun && fullResolved != null) {
          secondary = Text(
            '${i18n.railFullRunInline(runOrigin.name, runDest.name)}'
            '\$${fullResolved.price}',
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          );
        } else if (!useUserFare && showUserSegment && !isFullRun) {
          // Wanted the user's segment fare but it failed to resolve (the RPC
          // is best-effort) — say so rather than silently substituting the
          // full-run number unlabelled.
          secondary = Text(
            i18n.railNoFareForPair(userOriginStop!.name, userDestStop!.name),
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text(
              AppI18n.of(context).railFareInfo,
              style: AppTextStyles.heading2.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            AppCard.outlined(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(
                    primaryLabel,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (primary == null)
                    Text(
                      AppI18n.of(context).railNoFare,
                      style: AppTextStyles.bodyRegular.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  else
                    FareAmount(fare: primary, requested: fareType),
                  if (secondary != null) ...[
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      color: cs.outlineVariant,
                    ),
                    secondary,
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 追蹤 toggle for this train, shown in the app bar beside the bookmark.
///
/// Moved here from the O/D result card, whose header could not fit chip,
/// number, fare, 追蹤 and 訂購 on one line even at the default text scale.
class _TrackButton extends StatelessWidget {
  const _TrackButton({
    required this.trainLabel,
    required this.trainNo,
    required this.date,
    required this.isThsr,
    required this.delayMinutes,
    required this.stops,
    required this.userOrigin,
    required this.userDest,
  });

  final String trainLabel;
  final String trainNo;
  final String date;
  final bool isThsr;
  final int delayMinutes;
  final List<RailTrainStop> stops;
  final String? userOrigin;
  final String? userDest;

  // trainNo lives in identity.routeKey and the service date in
  // identity.direction (trackOnly rail legs carry no real O/D keys), so both
  // must match to recognise this train as the one being tracked.
  bool _isTracking(JourneySessionState s) {
    final leg = s.currentLeg;
    return s.trackOnly &&
        s.phase == JourneyPhase.waiting &&
        leg != null &&
        (leg.kind == JourneyLegKind.tra || leg.kind == JourneyLegKind.thsr) &&
        leg.identity.routeKey == trainNo &&
        leg.identity.direction == date;
  }

  RailTrainStop? _stopFor(String? name, RailTrainStop fallback) {
    if (name == null) return fallback;
    for (final s in stops) {
      if (sameStation(s.name, name)) return s;
    }
    return fallback;
  }

  /// The boarding stop: the one the rider actually searched from, falling back
  /// to the train's origin when this screen was opened by train number alone.
  RailTrainStop? get _board =>
      stops.isEmpty ? null : _stopFor(userOrigin, stops.first);

  /// Stops the train still calls at after boarding — the 下車站 candidates.
  List<RailTrainStop> get _ahead {
    final board = _board;
    if (board == null) return const [];
    final at = stops.indexOf(board);
    return at < 0 ? const [] : stops.sublist(at + 1);
  }

  JourneyLeg? _buildLeg(AppI18n i18n, RailTrainStop alight) {
    final board = _board;
    if (board == null) return null;
    final departRaw = board.depart.isNotEmpty ? board.depart : board.arrive;
    final arriveRaw = alight.arrive.isNotEmpty ? alight.arrive : alight.depart;
    final departAt = DateTime.tryParse('$date ${hhmm(departRaw)}');
    // Fold the current delay into the countdown so 追蹤 reflects live 誤點.
    final scheduledDeparture = departAt?.add(Duration(minutes: delayMinutes));
    return JourneyLeg(
      kind: isThsr ? JourneyLegKind.thsr : JourneyLegKind.tra,
      routeLabel: i18n.railTrainTowards(trainLabel, trainNo, alight.name),
      boardStop: board.name,
      alightStop: alight.name,
      stopNames: const [],
      identity: PlanIdentity(
        routeType: isThsr ? 'thsr' : 'tra',
        routeKey: trainNo,
        direction: date,
        departureStopKey: '',
        arrivalStopKey: '',
        supported: false,
      ),
      leadingWalkMinutes: 0,
      scheduledDeparture: scheduledDeparture,
      scheduledArrival: DateTime.tryParse('$date ${hhmm(arriveRaw)}'),
      boardLocation: const PlanPoint(lat: 0, lng: 0),
      stopLocations: const [],
      // The whole board→alight segment travels on the leg so the live tracker
      // can keep deriving 還剩 N 站 / progress after this screen is disposed.
      // Delay is NOT folded in here — the tracker applies live 誤點 itself.
      railSchedule: railTrackSchedule(
        stops,
        date,
        board: board.name,
        alight: alight.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to set a reminder on until the stop list has landed.
    if (_ahead.isEmpty) return const SizedBox.shrink();

    return BlocSelector<JourneySessionBloc, JourneySessionState, bool>(
      selector: _isTracking,
      builder: (context, active) {
        final i18n = AppI18n.of(context);
        return AlightTrackBell(
          active: active,
          semanticLabel: active
              ? i18n.railTrackingSemantics(trainLabel, trainNo)
              : i18n.railTrackSemantics(trainLabel, trainNo),
          onTap: () {
            final session = context.read<JourneySessionBloc>();
            if (active) {
              session.add(const JourneyCancelled());
              return;
            }
            unawaited(_openSheet(context, session));
          },
        );
      },
    );
  }

  Future<void> _openSheet(BuildContext context, JourneySessionBloc session) {
    final i18n = AppI18n.of(context);
    // A single data colour per network: at 8px the useful distinction is
    // TRA-versus-THSR, and the train type is already named on the screen.
    final dot = isThsr ? AppTheme.trainThsr : AppTheme.markerRail;
    return AlightTrackSheet.show(
      context: context,
      child: AlightTrackSheet(
        bindingRow: _BindingLine(trainLabel: trainLabel, trainNo: trainNo),
        stops: [
          for (final stop in _ahead)
            AlightStopOption(id: stop.name, name: stop.name, dotColor: dot),
        ],
        onStart: (stopId, lead) {
          final alight = _ahead.firstWhere(
            (s) => s.name == stopId,
            orElse: () => _ahead.last,
          );
          final leg = _buildLeg(i18n, alight);
          if (leg == null) return;
          session.add(
            JourneyStarted(trackOnly: true, legs: [leg], leadStops: lead),
          );
          unawaited(Navigator.of(context).maybePop());
        },
      ),
    );
  }
}

/// What the rail reminder is bound to: the train, not a vehicle within it.
class _BindingLine extends StatelessWidget {
  const _BindingLine({required this.trainLabel, required this.trainNo});

  final String trainLabel;
  final String trainNo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i18n = AppI18n.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          i18n.mrtAlightBound,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
        AlightBindingChip(label: '$trainLabel $trainNo'),
      ],
    );
  }
}
