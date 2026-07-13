import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_bloc.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_state.dart';
import 'package:wheres_the_car/features/rail/rail_navigation_request.dart';
import 'package:wheres_the_car/features/rail/view/rail_train_screen.dart';
import 'package:wheres_the_car/features/rail/widgets/rail_query_sheet.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_card.dart';
import 'package:wheres_the_car/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/train_type_chip.dart';

part '../widgets/rail_shimmer_widgets.dart';
part '../widgets/rail_train_card_widgets.dart';

final _dateFormat = DateFormat('yyyy-MM-dd');

// One summary-card row: the exact fields the card renders, times as "HH:mm".
typedef _RailRow = ({
  String type,
  String number,
  int delay,
  String depart,
  String arrive,
});

const Map<int, String> _weekdayMap = {
  DateTime.monday: '一',
  DateTime.tuesday: '二',
  DateTime.wednesday: '三',
  DateTime.thursday: '四',
  DateTime.friday: '五',
  DateTime.saturday: '六',
  DateTime.sunday: '日',
};

String _formatDateDisplay(DateTime date) {
  return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} (${_weekdayMap[date.weekday]})';
}

/// Normalizes a backend time to `HH:mm`, accepting both an RFC3339 timestamp
/// (`2026-07-08T06:59:00+08:00`) and a bare `HH:mm:ss.ffffff` clock string.
String _railHhmm(String t) {
  final s = t.contains('T') ? t.split('T').last : t;
  return s.length >= 5 ? s.substring(0, 5) : s;
}

String _computeDuration(String depart, String arrive) {
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
  if (h == 0) return '$m分';
  if (m == 0) return '$h時';
  return '$h時$m分';
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
  String _originName = '台北';
  String _originId = '';
  String _destName = '花蓮';
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

  @override
  void initState() {
    super.initState();
    _sheetController = SheetController();
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
    _destName = request.destName ?? _defaultDest(request.system);
    // If the preset station is itself the default destination, fall back to the
    // default origin so the O/D pair is real.
    if (_originName == _destName) _destName = _defaultOrigin(request.system);
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

    if (request.autoSubmit) {
      // A full O/D hand-off (from the home sheet): run it immediately and drop
      // the query sheet out of the way so results are the first thing shown.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _hasSubmittedQuery = true);
        _dispatchSearch();
        unawaited(
          _sheetController.animateTo(
            const SheetOffset.proportionalToViewport(0.15),
          ),
        );
      });
    }
  }

  String _defaultOrigin(RailSystem system) =>
      system == RailSystem.thsr ? '南港' : '台北';

  String _defaultDest(RailSystem system) =>
      system == RailSystem.thsr ? '左營' : '花蓮';

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
          ),
        for (final item in state.thsrItems)
          (
            type: '高鐵',
            number: item.trainNo,
            delay: state.delays[item.trainNo] ?? 0,
            depart: _railHhmm(item.departureTime),
            arrive: _railHhmm(item.arrivalTime),
          ),
      ];
    }
    return _rowsCache;
  }

  @override
  void dispose() {
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
          _sheetController.animateTo(
            const SheetOffset.proportionalToViewport(0.15),
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
                      return ListView(
                        padding: EdgeInsets.fromLTRB(16, topPad + 68, 16, 16),
                        children: const [
                          SizedBox(height: 12),
                          _ShimmerTrainList(),
                        ],
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
                                '選擇起訖站查詢班次',
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
                      return ListView(
                        padding: EdgeInsets.fromLTRB(16, topPad + 68, 16, 16),
                        children: [
                          ErrorStateView(
                            error: const NotFoundError(),
                            onRetry: _dispatchSearch,
                          ),
                        ],
                      );
                    }
                    // The sheet offset changes every frame while the query
                    // sheet is dragged, but it only feeds the list's bottom
                    // inset. Hand the train list to the builder as a stable
                    // child so only the trailing spacer sliver rebuilds per
                    // frame instead of every visible card.
                    return ValueListenableBuilder<double?>(
                      valueListenable: _sheetController,
                      child: SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          topPad + 68 + 12,
                          16,
                          0,
                        ),
                        sliver: SliverList.builder(
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final item = items[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _TrainCard(
                                type: item.type,
                                number: item.number,
                                delay: item.delay,
                                depart: item.depart,
                                arrive: item.arrive,
                                duration: _computeDuration(
                                  item.depart,
                                  item.arrive,
                                ),
                                origin: state.originName,
                                destination: state.destName,
                                date: state.date,
                                isThsr: state.system == RailSystem.thsr,
                              ),
                            );
                          },
                        ),
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
              left: 12,
              right: 12,
              child: SafeArea(
                child: Row(
                  children: [
                    AppBarCircleButton(
                      onTap: () {
                        unawaited(HapticService.instance.lightTap());
                        context.pop();
                      },
                      semanticLabel: '返回',
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: cs.brightness == Brightness.light
                              ? Colors.white
                              : cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: AppShadows.floating,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _hasSubmittedQuery
                                  ? '$_originName ➔ $_destName'
                                  : '列車時刻查詢',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDateDisplay(_selectedDate),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                                color: cs.onSurfaceVariant,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 52),
                  ],
                ),
              ),
            ),

            NotificationListener<SheetNotification>(
              onNotification: (notification) {
                if (notification is SheetDragEndNotification) {
                  unawaited(HapticService.instance.lightTap());
                }
                return false;
              },
              child: SheetViewport(
                child: SheetExitGestureDetector(
                  onExit: () => context.pop(),
                  child: Sheet(
                    controller: _sheetController,
                    initialOffset: const SheetOffset.proportionalToViewport(
                      0.35,
                    ),
                    snapGrid: const SheetSnapGrid(
                      snaps: [
                        SheetOffset.proportionalToViewport(0.15),
                        SheetOffset.proportionalToViewport(0.35),
                        SheetOffset.proportionalToViewport(1),
                      ],
                    ),
                    scrollConfiguration: const SheetScrollConfiguration(),
                    decoration: MaterialSheetDecoration(
                      size: SheetSize.stretch,
                      color: cs.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppTheme.radiusBottomSheet),
                      ),
                    ),
                    child: RailQuerySheetContent(
                      preset: _preset,
                      onSubmit: _onSubmit,
                      onSystemChanged: _onSystemChanged,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
