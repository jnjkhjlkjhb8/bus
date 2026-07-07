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
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_bloc.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_state.dart';
import 'package:wheres_the_car/features/rail/view/rail_train_screen.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_card.dart';
import 'package:wheres_the_car/shared/widgets/app_date_picker.dart';
import 'package:wheres_the_car/shared/widgets/app_time_picker.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
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

Future<String> _resolveTraStationId(String name) async {
  final rows = await PowerSyncService.instance.db.getAll(
    'SELECT station_id FROM tra_stations WHERE station_name = ? LIMIT 1',
    [name],
  );
  if (rows.isEmpty) return name;
  return rows.first['station_id'] as String? ?? name;
}

class RailScreen extends StatefulWidget {
  const RailScreen({super.key});

  @override
  State<RailScreen> createState() => _RailScreenState();
}

class _RailScreenState extends State<RailScreen> {
  final _bloc = RailBloc();
  String _originName = '台北';
  String _originId = '';
  String _destName = '花蓮';
  String _destId = '';
  late final SheetController _sheetController;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _sheetController = SheetController();
    unawaited(_resolveInitialIds());
  }

  Future<void> _resolveInitialIds() async {
    final originId = await _resolveTraStationId(_originName);
    final destId = await _resolveTraStationId(_destName);
    if (mounted) {
      setState(() {
        _originId = originId;
        _destId = destId;
      });
    }
  }

  @override
  void dispose() {
    _sheetController.dispose();
    unawaited(_bloc.close());
    super.dispose();
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
    _bloc.add(
      RailTimetableRequested(
        originId: _originId,
        destId: _destId,
        date: _dateFormat.format(_selectedDate),
      ),
    );
  }

  Future<void> _pickOrigin() async {
    unawaited(HapticService.instance.lightTap());
    final name = await showTRAStationPicker(context);
    if (name != null && mounted) {
      final id = await _resolveTraStationId(name);
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
    final name = await showTRAStationPicker(context);
    if (name != null && mounted) {
      final id = await _resolveTraStationId(name);
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
                    if (state is RailTimetableLoading) {
                      return ListView(
                        padding: EdgeInsets.fromLTRB(16, topPad + 68, 16, 16),
                        children: const [
                          SizedBox(height: 12),
                          _ShimmerTrainList(),
                        ],
                      );
                    }
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
                    if (state is! RailTimetableLoaded) {
                      return const SizedBox.shrink();
                    }
                    final items = [
                      for (final item in state.traItems)
                        (
                          type: item.trainType,
                          number: item.trainNo,
                          delay: state.delays[item.trainNo] ?? 0,
                          depart: item.departureTime,
                          arrive: item.arrivalTime,
                        ),
                      for (final item in state.thsrItems)
                        (
                          type: '高鐵',
                          number: item.trainNo,
                          delay: state.delays[item.trainNo] ?? 0,
                          depart: item.departureTime,
                          arrive: item.arrivalTime,
                        ),
                    ];
                    return ValueListenableBuilder<double?>(
                      valueListenable: _sheetController,
                      builder: (context, offset, _) {
                        return RefreshIndicator(
                          onRefresh: () async => _dispatchSearch(),
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              16,
                              topPad + 68 + 12,
                              16,
                              (offset ?? 0.0) + 16,
                            ),
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
                      origin: _originName,
                      destination: _destName,
                      selectedDate: _selectedDate,
                      onSwap: _swap,
                      onDateChanged: (date) {
                        setState(() => _selectedDate = date);
                      },
                      onOriginTap: _pickOrigin,
                      onDestTap: _pickDest,
                      onSearch: () {
                        _dispatchSearch();
                        Navigator.of(context).pop();
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
