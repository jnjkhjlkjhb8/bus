import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/features/rail/bloc/rail_bloc.dart';
import 'package:wheres_the_bus/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_bus/features/rail/bloc/rail_state.dart';
import 'package:wheres_the_bus/features/rail/rail_navigation_request.dart';
import 'package:wheres_the_bus/features/rail/view/rail_train_screen.dart';
import 'package:wheres_the_bus/features/rail/widgets/rail_query_sheet.dart';
import 'package:wheres_the_bus/features/rail/widgets/rail_service_marks.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';
import 'package:wheres_the_bus/shared/widgets/app_bars.dart';
import 'package:wheres_the_bus/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_bus/shared/widgets/error_state_view.dart';
import 'package:wheres_the_bus/shared/widgets/state_cards.dart';
import 'package:wheres_the_bus/shared/widgets/train_type_chip.dart';

part '../widgets/rail_shimmer_widgets.dart';
part '../widgets/rail_timetable_row_widgets.dart';

final _dateFormat = DateFormat('yyyy-MM-dd');

// One timetable row: the exact fields the row renders, times as "HH:mm".
typedef _RailRow = ({
  String type,
  String number,
  int delay,
  String depart,
  String arrive,
  String duration,
  List<RailServiceMark> marks,
  String remark,
  bool isSuspended,
  bool isAddedService,
});

// This screen's own detents. The query form only ever fills ~45% of the
// screen, so every detent above `half` leaves it floating over blank space
// while occluding the timetable behind it; Apple HIG sheets never present a
// taller sheet than their content needs. `half` gives the form all the room
// it has to fill. Defined locally rather than mutating [AppSheetSnap.grid],
// which other screens depend on.
const _railSheetSnapGrid = SheetSnapGrid(
  snaps: [AppSheetSnap.peek, AppSheetSnap.half],
  minFlingSpeed: AppSheetSnap.flingSpeed,
);

// Built per call rather than held in a const map: the names follow the
// rider's language.
Map<int, String> _weekdayMap(AppI18n i18n) => {
  DateTime.monday: i18n.weekdayMon,
  DateTime.tuesday: i18n.weekdayTue,
  DateTime.wednesday: i18n.weekdayWed,
  DateTime.thursday: i18n.weekdayThu,
  DateTime.friday: i18n.weekdayFri,
  DateTime.saturday: i18n.weekdaySat,
  DateTime.sunday: i18n.weekdaySun,
};

String _formatDateDisplay(AppI18n i18n, DateTime date) {
  return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} (${_weekdayMap(i18n)[date.weekday]})';
}

/// Normalizes a backend time to `HH:mm`, accepting both an RFC3339 timestamp
/// (`2026-07-08T06:59:00+08:00`) and a bare `HH:mm:ss.ffffff` clock string.
String _railHhmm(String t) {
  final s = t.contains('T') ? t.split('T').last : t;
  return s.length >= 5 ? s.substring(0, 5) : s;
}

/// Minutes since midnight for an `HH:mm` clock string, or null when it does
/// not parse — a malformed time must not silently sort as 00:00.
int? _minutesOfDay(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String _computeDuration(AppI18n i18n, String depart, String arrive) {
  final dParts = depart.split(':');
  final aParts = arrive.split(':');
  if (dParts.length != 2 || aParts.length != 2) return '';
  final dMin =
      (int.tryParse(dParts[0]) ?? 0) * 60 + (int.tryParse(dParts[1]) ?? 0);
  var aMin =
      (int.tryParse(aParts[0]) ?? 0) * 60 + (int.tryParse(aParts[1]) ?? 0);
  if (aMin < dMin) aMin += 24 * 60;
  final diff = aMin - dMin;
  final h = diff ~/ 60;
  final m = diff % 60;
  if (h == 0) return i18n.durationMinutes(m);
  if (m == 0) return i18n.hoursValue(h);
  return i18n.hoursMinutesValue(h, m);
}

class RailScreen extends StatefulWidget {
  const RailScreen({super.key});

  @override
  State<RailScreen> createState() => _RailScreenState();
}

class _RailScreenState extends State<RailScreen> {
  final _bloc = RailBloc();
  RailSystem _system = RailSystem.tra;
  // Header + retry state, mirrored from the most recent O/D submission. The
  // query form itself lives in [RailQuerySheetContent]; these fields only feed
  // the top pill and the pull-to-refresh / error retry re-dispatch.
  String _originName = '';
  String _originId = '';
  String _destName = '';
  String _destId = '';
  late final SheetController _sheetController;
  // [_selectedDate] carries the query's time-of-day too; the backend request
  // stays date-only, but the time (with [_isDeparture]) is sent to the bloc as
  // a cutoff so results start at the time the user picked — depart at/after it,
  // or (arrive mode) arrive at/before it — not the first train of the day.
  DateTime _selectedDate = DateTime.now();
  bool _isDeparture = true;
  bool _initialized = false;
  bool _hasSubmittedQuery = false;
  RailQueryPreset? _preset;

  // Drives the "N 分後" countdown on the next departure. The values are
  // minute-granular, so a minute tick is as often as the display can change;
  // it only rebuilds the visible rows of a lazily-built list.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _sheetController = SheetController();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // One-shot: the hand-off request clears on read, so guard against the
    // repeated didChangeDependencies calls Flutter makes on dependency changes.
    if (_initialized) return;
    _initialized = true;

    final request = RailNavigationRequest.consume();
    if (request == null) return;

    _system = request.system;
    _originName = request.originName;
    // The near station id is already a valid tra/thsr station_id, so carry it
    // directly rather than re-resolving by name.
    _originId = request.originId ?? '';
    _destName = request.destName ?? '';
    // A hand-off can name the same station twice; clear the dest rather than
    // carry a zero-length trip into the form.
    if (_originName.isNotEmpty && _originName == _destName) _destName = '';
    _destId = request.destId ?? '';
    _selectedDate = request.date;
    _isDeparture = request.isDeparture;
    // Seed the form with the full effective query (not just the origin) so the
    // sheet and the auto-submitted results can't disagree.
    _preset = RailQueryPreset(
      system: request.system,
      originName: _originName,
      originId: request.originId,
      destName: _destName,
      destId: request.destId,
      date: request.date,
      isDeparture: request.isDeparture,
    );

    // An origin-only hand-off has nothing to submit: it opens the form with the
    // origin filled and waits for a destination.
    if (request.autoSubmit && _originName.isNotEmpty && _destName.isNotEmpty) {
      // A full O/D hand-off (from the home sheet): run it immediately and drop
      // the query sheet out of the way so results are the first thing shown.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _hasSubmittedQuery = true);
        _dispatchSearch();
        unawaited(
          _sheetController.animateToDetent(
            AppSheetSnap.peek,
            reduced: AppMotion.reduced(context),
          ),
        );
      });
    }
  }

  // Derived card rows, cached per loaded-state instance so local setState
  // (date picks, station picks, sheet drags) doesn't re-parse every train's
  // times; states are immutable, so identity is a sound cache key.
  RailTimetableLoaded? _rowsSource;
  late List<_RailRow> _rowsCache;

  List<_RailRow> _rowsFor(RailTimetableLoaded state) {
    if (!identical(state, _rowsSource)) {
      _rowsSource = state;
      _rowsCache = [
        for (final item in state.traItems)
          (
            type: item.trainType,
            number: item.trainNo,
            delay: state.delays[item.trainNo] ?? 0,
            depart: _railHhmm(item.departureTime),
            arrive: _railHhmm(item.arrivalTime),
            duration: _computeDuration(
              AppI18n.of(context),
              _railHhmm(item.departureTime),
              _railHhmm(item.arrivalTime),
            ),
            marks: RailServiceMark.forTra(item),
            remark: item.remark,
            isSuspended: item.isSuspended,
            isAddedService: item.isAddedService,
          ),
        for (final item in state.thsrItems)
          (
            type: '高鐵',
            number: item.trainNo,
            delay: state.delays[item.trainNo] ?? 0,
            depart: _railHhmm(item.departureTime),
            arrive: _railHhmm(item.arrivalTime),
            duration: _computeDuration(
              AppI18n.of(context),
              _railHhmm(item.departureTime),
              _railHhmm(item.arrivalTime),
            ),
            marks: RailServiceMark.forThsr(item),
            remark: item.remark,
            isSuspended: false,
            isAddedService: false,
          ),
      ];
    }
    return _rowsCache;
  }

  /// Index of the first departure still to come, and how many minutes away it
  /// is — or `(null, null)` when the query is not for today, where a countdown
  /// would be nonsense and no row deserves the coming-soon emphasis.
  ///
  /// Suspended trains are skipped: the next train you can actually board is
  /// the one worth highlighting.
  (int?, int?) _nextDeparture(List<_RailRow> rows, String date) {
    final now = DateTime.now();
    if (date != _dateFormat.format(now)) return (null, null);
    final nowMinutes = now.hour * 60 + now.minute;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].isSuspended) continue;
      final depart = _minutesOfDay(rows[i].depart);
      if (depart == null || depart < nowMinutes) continue;
      return (i, depart - nowMinutes);
    }
    return (null, null);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sheetController.dispose();
    unawaited(_bloc.close());
    super.dispose();
  }

  void _onSystemChanged(RailSystem system) {
    setState(() {
      _system = system;
      _hasSubmittedQuery = false;
    });
    // Clear stale results back to the prompt (no query until user searches).
    _bloc.add(RailSystemChanged(system));
  }

  void _onSubmit(RailQuerySubmission submission) {
    switch (submission) {
      case RailOdQuerySubmission():
        setState(() {
          _system = submission.system;
          _originName = submission.originName;
          _originId = submission.originId ?? '';
          _destName = submission.destName;
          _destId = submission.destId ?? '';
          _selectedDate = submission.date;
          _isDeparture = submission.isDeparture;
          _hasSubmittedQuery = true;
        });
        _dispatchSearch();
        // Collapse the inline sheet to reveal results. Never pop the navigator
        // here — the sheet is part of this screen's Stack, so popping unwinds
        // back to home.
        unawaited(
          _sheetController.animateToDetent(
            AppSheetSnap.peek,
            reduced: AppMotion.reduced(context),
          ),
        );
      case RailTrainQuerySubmission():
        unawaited(
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => RailTrainScreen(
                type: submission.system == RailSystem.thsr ? '高鐵' : '台鐵',
                trainNo: submission.trainNo,
                date: _dateFormat.format(submission.date),
              ),
            ),
          ),
        );
    }
  }

  void _dispatchSearch() {
    _hasSubmittedQuery = true;
    _bloc.add(
      RailTimetableRequested(
        system: _system,
        origin: RailStationSelection(
          name: _originName,
          id: _originId.isEmpty ? null : _originId,
        ),
        destination: RailStationSelection(
          name: _destName,
          id: _destId.isEmpty ? null : _destId,
        ),
        date: _dateFormat.format(_selectedDate),
        cutoffMinutes: _selectedDate.hour * 60 + _selectedDate.minute,
        isDeparture: _isDeparture,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPad = MediaQuery.paddingOf(context).top;

    return BlocProvider.value(
      value: _bloc,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: cs.surface,
                child: BlocBuilder<RailBloc, RailState>(
                  builder: (context, state) {
                    if (state is RailError) {
                      return ListView(
                        padding: EdgeInsets.fromLTRB(16, topPad + 68, 16, 16),
                        children: [
                          ErrorStateView(
                            error: state.error,
                            onRetry: _dispatchSearch,
                          ),
                        ],
                      );
                    }
                    if (state is RailTimetableLoading) {
                      // Full-bleed and offset exactly like the loaded list
                      // below (topPad + 68 + 12), so the table doesn't shift
                      // when the trains arrive.
                      return ListView(
                        padding: EdgeInsets.only(
                          top: topPad + 68 + 12,
                          bottom: 16,
                        ),
                        children: const [_TimetableSkeleton()],
                      );
                    }
                    if (state is! RailTimetableLoaded) {
                      // No search run yet — prompt instead of auto-querying a
                      // placeholder O/D pair.
                      return Padding(
                        padding: EdgeInsets.fromLTRB(24, topPad + 68, 24, 24),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.train_rounded,
                                size: 40,
                                color: cs.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                AppI18n.of(context).railPickStations,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodyRegular.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final items = _rowsFor(state);
                    if (items.isEmpty) {
                      // A successful query that simply found no departures in
                      // this window is not an error — ErrorStateView (with its
                      // retry button) would imply the request failed and
                      // retrying might help, when the fix is to change the
                      // search itself.
                      return ListView(
                        padding: EdgeInsets.fromLTRB(24, topPad + 68, 24, 24),
                        children: const [_NoTimetableEmpty()],
                      );
                    }
                    // The sheet offset changes every frame while the query
                    // sheet is dragged, but it only feeds the list's bottom
                    // inset. Hand the train list to the builder as a stable
                    // child so only the trailing spacer sliver rebuilds per
                    // frame instead of every visible card.
                    final (nextIndex, minutesUntil) = _nextDeparture(
                      items,
                      state.date,
                    );
                    return ValueListenableBuilder<double?>(
                      valueListenable: _sheetController,
                      child: SliverMainAxisGroup(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.only(top: topPad + 68 + 12),
                              child: const _TimetableHeader(),
                            ),
                          ),
                          SliverList.separated(
                            itemCount: items.length,
                            separatorBuilder: (context, i) => Divider(
                              height: 1,
                              thickness: 1,
                              indent: 16,
                              color: cs.outlineVariant.withValues(alpha: 0.4),
                            ),
                            itemBuilder: (context, i) => _TrainRow(
                              row: items[i],
                              date: state.date,
                              origin: state.originName,
                              destination: state.destName,
                              isNext: i == nextIndex,
                              minutesUntil: minutesUntil,
                            ),
                          ),
                        ],
                      ),
                      builder: (context, offset, listSliver) {
                        return RefreshIndicator(
                          onRefresh: () async => _dispatchSearch(),
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              listSliver!,
                              SliverToBoxAdapter(
                                child: SizedBox(height: (offset ?? 0.0) + 16),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              // Deliberately no fare in the subtitle. TRA prices the same O/D
              // differently per train type (自強 costs more than 區間車), so a
              // single figure over a mixed list would misquote most of the
              // rows under it. The per-train fare belongs to the detail
              // screen, which knows which train the user picked.
              child: FloatingAppBar(
                middle: AppBarTitlePill(
                  title: _hasSubmittedQuery
                      ? '$_originName → $_destName'
                      : AppI18n.of(context).railTimetableTitle,
                  subtitle: _formatDateDisplay(
                    AppI18n.of(context),
                    _selectedDate,
                  ),
                ),
              ),
            ),

            // RailQuerySheetContent starts its ListView flush with the sheet's
            // top edge and can't take a SafeArea itself; AppSheet's own
            // status-bar padding is what keeps its handle and title clear.
            AppSheet(
              controller: _sheetController,
              // Back button in the app bar above (see AppSheet.onExit).
              onExit: null,
              snapGrid: _railSheetSnapGrid,
              color: cs.surface,
              child: RailQuerySheetContent(
                preset: _preset,
                onSubmit: _onSubmit,
                onSystemChanged: _onSystemChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A successful timetable query with zero departures in the requested
/// window — distinct from [ErrorStateView], which implies the request
/// itself failed and a retry might help.
class _NoTimetableEmpty extends StatelessWidget {
  const _NoTimetableEmpty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy_rounded, size: 40, color: cs.outline),
          const SizedBox(height: 16),
          Text(
            AppI18n.of(context).railNoTrains,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyRegular.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppI18n.of(context).railNoTrainsHint,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.outline,
            ),
          ),
        ],
      ),
    );
  }
}
