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
import 'package:wheres_the_car/data/repositories/thsr_repository.dart';
import 'package:wheres_the_car/data/repositories/tra_repository.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_bloc.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_state.dart';
import 'package:wheres_the_car/features/rail/rail_navigation_request.dart';
import 'package:wheres_the_car/features/rail/view/rail_train_screen.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_card.dart';
import 'package:wheres_the_car/shared/widgets/app_date_picker.dart';
import 'package:wheres_the_car/shared/widgets/app_sliding_segment.dart';
import 'package:wheres_the_car/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_car/shared/widgets/app_time_picker.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/thsr_station_picker.dart';
import 'package:wheres_the_car/shared/widgets/tra_station_picker.dart';
import 'package:wheres_the_car/shared/widgets/train_type_chip.dart';

part '../widgets/rail_query_sheet_widgets.dart';
part '../widgets/rail_shimmer_widgets.dart';
part '../widgets/rail_train_card_widgets.dart';

const List<FontFeature> _tnum = AppTextStyles.tabularFigures;

final _dateFormat = DateFormat('yyyy-MM-dd');

String _formatDateDisplay(DateTime date) {
  final weekdayMap = {
    DateTime.monday: '一',
    DateTime.tuesday: '二',
    DateTime.wednesday: '三',
    DateTime.thursday: '四',
    DateTime.friday: '五',
    DateTime.saturday: '六',
    DateTime.sunday: '日',
  };
  return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} (${weekdayMap[date.weekday]})';
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

// Falls back to the name itself when the station is unknown, so the query
// still carries a value the caller can display.
Future<String> _resolveTraStationId(String name) async =>
    await TraRepository.instance.stationId(name) ?? name;

Future<String> _resolveThsrStationId(String name) async =>
    await ThsrRepository.instance.stationId(name) ?? name;

class RailScreen extends StatefulWidget {
  const RailScreen({super.key});

  @override
  State<RailScreen> createState() => _RailScreenState();
}

class _RailScreenState extends State<RailScreen> {
  final _bloc = RailBloc();
  RailSystem _system = RailSystem.tra;
  String _originName = '台北';
  String _originId = '';
  String _destName = '花蓮';
  String _destId = '';
  late final SheetController _sheetController;
  DateTime _selectedDate = DateTime.now();
  bool _initialized = false;

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
    if (request != null) {
      _system = request.system;
      _originName = request.stationName;
      // The near station id is already a valid tra/thsr station_id, so carry it
      // directly rather than re-resolving by name.
      _originId = request.stationId;
      _destName = _defaultDest(request.system);
      // If the preset station is itself the default destination, fall back to
      // the default origin so the initial query is a real O/D pair.
      if (_originName == _destName) _destName = _defaultOrigin(request.system);
      _destId = '';
    }
    // No auto-query: the default O/D is just a placeholder for the picker, not
    // a real request. A timetable is only fetched when the user taps 查詢.
  }

  String _defaultOrigin(RailSystem system) =>
      system == RailSystem.thsr ? '南港' : '台北';

  String _defaultDest(RailSystem system) =>
      system == RailSystem.thsr ? '左營' : '花蓮';

  Future<String> _resolveStationId(String name) => _system == RailSystem.thsr
      ? _resolveThsrStationId(name)
      : _resolveTraStationId(name);

  Future<String?> _showStationPicker() => _system == RailSystem.thsr
      ? showTHSRStationPicker(context)
      : showTRAStationPicker(context);

  /// Resolves any missing ids for the current origin/dest, then runs the query.
  Future<void> _resolveAndSearch() async {
    final originId = _originId.isNotEmpty
        ? _originId
        : await _resolveStationId(_originName);
    final destId = await _resolveStationId(_destName);
    if (!mounted) return;
    setState(() {
      _originId = originId;
      _destId = destId;
    });
    _dispatchSearch();
  }

  @override
  void dispose() {
    _sheetController.dispose();
    unawaited(_bloc.close());
    super.dispose();
  }

  void _switchSystem(RailSystem system) {
    if (system == _system) return;
    unawaited(HapticService.instance.lightTap());
    setState(() {
      _system = system;
      _originName = _defaultOrigin(system);
      _destName = _defaultDest(system);
      _originId = '';
      _destId = '';
    });
    // Clear stale results back to the prompt (no query until user searches).
    _bloc.add(RailSystemChanged(system));
  }

  void _swap() {
    unawaited(HapticService.instance.lightTap());
    setState(() {
      final tmpName = _originName;
      final tmpId = _originId;
      _originName = _destName;
      _originId = _destId;
      _destName = tmpName;
      _destId = tmpId;
    });
    _dispatchSearch();
  }

  void _dispatchSearch() {
    if (_originId.isEmpty || _destId.isEmpty) return;
    // The bloc reads system + O/D names off a RailLiveBoardLoaded state, so
    // re-establish it before every request; without this a repeat THSR query
    // would silently fall back to TRA.
    _bloc
      ..add(RailSystemChanged(_system))
      ..add(RailQueryChanged(originName: _originName, destName: _destName))
      ..add(
        RailTimetableRequested(
          originId: _originId,
          destId: _destId,
          date: _dateFormat.format(_selectedDate),
        ),
      );
  }

  Future<void> _pickOrigin() async {
    unawaited(HapticService.instance.lightTap());
    final name = await _showStationPicker();
    if (name != null && mounted) {
      final id = await _resolveStationId(name);
      if (mounted) {
        setState(() {
          _originName = name;
          _originId = id;
        });
      }
    }
  }

  Future<void> _pickDest() async {
    unawaited(HapticService.instance.lightTap());
    final name = await _showStationPicker();
    if (name != null && mounted) {
      final id = await _resolveStationId(name);
      if (mounted) {
        setState(() {
          _destName = name;
          _destId = id;
        });
      }
    }
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
                    final items = [
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
                              '$_originName ➔ $_destName',
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
                    child: _QuerySheetContent(
                      system: _system,
                      origin: _originName,
                      destination: _destName,
                      selectedDate: _selectedDate,
                      onSystemChanged: _switchSystem,
                      onSwap: _swap,
                      onDateChanged: (date) {
                        setState(() => _selectedDate = date);
                      },
                      onOriginTap: _pickOrigin,
                      onDestTap: _pickDest,
                      onSearch: () {
                        unawaited(_resolveAndSearch());
                        // Collapse the inline sheet to reveal results. Never
                        // pop the navigator here — the sheet is part of this
                        // screen's Stack, so popping unwinds back to home.
                        unawaited(
                          _sheetController.animateTo(
                            const SheetOffset.proportionalToViewport(0.15),
                          ),
                        );
                      },
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
