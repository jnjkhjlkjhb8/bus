import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_train_bloc.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_train_event.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_train_state.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_card.dart';
import 'package:wheres_the_car/shared/widgets/app_spinner.dart';
import 'package:wheres_the_car/shared/widgets/bookmark_button.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/route_tab_bar.dart';
import 'package:wheres_the_car/shared/widgets/train_type_chip.dart';

/// Trims the backend's `HH:mm:ss.ffffff` time strings down to `HH:mm`.
String _hhmm(String t) => t.length >= 5 ? t.substring(0, 5) : t;

/// The stop's scheduled arrival (falling back to departure) as a local DateTime
/// on [serviceDate] (`yyyy-MM-dd`), or null when it can't be parsed.
DateTime? _stopDateTime(String serviceDate, RailTrainStop stop) {
  final time = stop.arrive.isNotEmpty ? stop.arrive : stop.depart;
  final d = serviceDate.split('-');
  final hm = time.split(':');
  if (d.length != 3 || hm.length < 2) return null;
  final year = int.tryParse(d[0]);
  final month = int.tryParse(d[1]);
  final day = int.tryParse(d[2]);
  final hour = int.tryParse(hm[0]);
  final minute = int.tryParse(hm[1]);
  if (year == null ||
      month == null ||
      day == null ||
      hour == null ||
      minute == null) {
    return null;
  }
  return DateTime(year, month, day, hour, minute);
}

class RailTrainScreen extends StatefulWidget {
  const RailTrainScreen({
    required this.type,
    required this.trainNo,
    required this.date,
    super.key,
  });

  final String type;
  final String trainNo;

  /// Service date in `yyyy-MM-dd`.
  final String date;

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
    final dateStr = widget.date.replaceAll('-', '/');

    return BlocProvider.value(
      value: _bloc,
      child: Scaffold(
        appBar: DetailAppBar(
          title: '${widget.type} ${widget.trainNo}',
          subtitle: dateStr,
          actions: [
            BookmarkButton(
              routeType: widget.type,
              routeKey: widget.trainNo,
              routeLabel: '${widget.type} ${widget.trainNo}',
            ),
          ],
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
                  child: Text(
                    '查無此車次的停靠資訊',
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              case RailTrainStatus.loaded:
                return Column(
                  children: [
                    RouteTabBar(
                      controller: _tabController,
                      tabs: const ['時刻表', '車次詳細資訊'],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _TimetableTab(
                            stops: state.stops,
                            serviceDate: widget.date,
                            reminders: state.reminders,
                          ),
                          _InfoTab(
                            type: widget.type,
                            trainNo: widget.trainNo,
                            stops: state.stops,
                            fullFare: state.fullFare,
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

class _TimetableTab extends StatelessWidget {
  const _TimetableTab({
    required this.stops,
    required this.serviceDate,
    required this.reminders,
  });

  final List<RailTrainStop> stops;
  final String serviceDate;
  final Map<String, String> reminders;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: stops.length,
      itemBuilder: (_, i) {
        final stop = stops[i];
        final scheduled = _stopDateTime(serviceDate, stop);
        final reminder = reminders[stop.name];
        // Offer a reminder only for stops still ahead of the train; an already
        // departed stop can't be reminded, but an active one stays cancellable.
        final canRemind =
            reminder != null || (scheduled != null && scheduled.isAfter(now));
        return _StopRow(
          stop: stop,
          reminder: reminder,
          canRemind: canRemind,
        );
      },
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.reminder,
    required this.canRemind,
  });

  final RailTrainStop stop;

  /// Null when off, `'pending'` while toggling, otherwise the reminder id.
  final String? reminder;
  final bool canRemind;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = reminder != null;

    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stop.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                height: 1.3,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (stop.arrive.isNotEmpty) _time('抵達', stop.arrive, cs),
              if (stop.depart.isNotEmpty) _time('開車', stop.depart, cs),
            ],
          ),
          if (canRemind) ...[
            const SizedBox(width: 12),
            _ReminderBell(stopName: stop.name, active: active),
          ],
        ],
      ),
    );
  }

  Widget _time(String label, String value, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          Text(
            _hhmm(value),
            style: AppTextStyles.memo.copyWith(
              fontSize: 14,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Arrival-reminder toggle for one stop, mirroring the bus stop-list bell.
class _ReminderBell extends StatelessWidget {
  const _ReminderBell({required this.stopName, required this.active});

  final String stopName;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.brightness == Brightness.light
        ? cs.surface
        : cs.surfaceContainerHigh;
    final idleColor = cs.brightness == Brightness.light
        ? cs.outline
        : cs.onSurfaceVariant;

    return Pressable(
      onTap: () {
        unawaited(HapticService.instance.lightTap());
        context.read<RailTrainBloc>().add(RailTrainReminderToggled(stopName));
      },
      semanticLabel: active ? '取消到站提醒' : '設定到站提醒',
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: Icon(
            active
                ? Icons.notifications_rounded
                : Icons.notifications_none_rounded,
            size: 16,
            color: active ? cs.primary : idleColor,
          ),
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
  });

  final String type;
  final String trainNo;
  final List<RailTrainStop> stops;
  final int? fullFare;

  static const TextStyle _labelStyle = AppTextStyles.bodyLarge;
  static const TextStyle _valueStyle = AppTextStyles.heading2;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          _buildTrainInfo(cs),
          if (fullFare != null) _buildFare(cs, fullFare!),
        ],
      ),
    );
  }

  Widget _buildTrainInfo(ColorScheme cs) {
    final origin = stops.first;
    final dest = stops.last;
    final departTime = _hhmm(
      origin.depart.isNotEmpty ? origin.depart : origin.arrive,
    );
    final arriveTime = _hhmm(
      dest.arrive.isNotEmpty ? dest.arrive : dest.depart,
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
              '車次 / 車種',
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
              '起迄站',
              style: _labelStyle.copyWith(color: cs.onSurfaceVariant),
            ),
            Row(
              spacing: 6,
              children: [
                Text(origin.name, style: _valueStyle),
                const Text('→', style: _valueStyle),
                Text(dest.name, style: _valueStyle),
              ],
            ),
          ],
        ),
        Divider(height: 1, thickness: 0.5, color: cs.outlineVariant),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 5,
          children: [
            Text(
              '行駛時間',
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

  Widget _buildFare(ColorScheme cs, int fullFare) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Text(
          '票價資訊',
          style: AppTextStyles.heading2.copyWith(color: cs.onSurfaceVariant),
        ),
        AppCard.outlined(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                '全票',
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                '\$$fullFare',
                style: AppTextStyles.heading1.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
