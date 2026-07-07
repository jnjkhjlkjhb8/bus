import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_train_bloc.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_train_event.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_train_state.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_card.dart';
import 'package:wheres_the_car/shared/widgets/bookmark_button.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/route_tab_bar.dart';

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
                return const Center(child: CircularProgressIndicator());
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
                          _TimetableTab(stops: state.stops),
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
  const _TimetableTab({required this.stops});

  final List<RailTrainStop> stops;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: stops.length,
      itemBuilder: (_, i) {
        final stop = stops[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  stop.name,
                  style: AppTextStyles.bodyRegular,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              _times(stop, cs),
            ],
          ),
        );
      },
    );
  }

  Widget _times(RailTrainStop stop, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (stop.arrive.isNotEmpty) _timeRow('抵達', stop.arrive, cs),
        if (stop.depart.isNotEmpty) _timeRow('開車', stop.depart, cs),
      ],
    );
  }

  Widget _timeRow(String label, String time, ColorScheme cs) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 4),
        Text(
          time,
          style: AppTextStyles.bodyRegular.copyWith(
            fontFeatures: AppTextStyles.tabularFigures,
          ),
        ),
      ],
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
    final departTime = origin.depart.isNotEmpty ? origin.depart : origin.arrive;
    final arriveTime = dest.arrive.isNotEmpty ? dest.arrive : dest.depart;

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
            Text('$trainNo / $type', style: _valueStyle),
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
