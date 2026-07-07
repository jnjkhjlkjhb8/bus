import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/powersync/powersync_service.dart';
import 'package:wheres_the_car/data/repositories/thsr_repository.dart';
import 'package:wheres_the_car/data/repositories/tra_repository.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_card.dart';
import 'package:wheres_the_car/shared/widgets/bookmark_button.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/route_tab_bar.dart';

/// One stop on a train's timetable, normalized across TRA/THSR.
class _Stop {
  const _Stop(this.name, this.arrive, this.depart);
  final String name;
  final String arrive;
  final String depart;
}

/// Everything the detail screen renders, loaded from real data.
class _TrainDetail {
  const _TrainDetail({
    required this.stops,
    required this.fullFare,
  });
  final List<_Stop> stops;

  /// Adult (全票) fare in NT$, or null when the fare query has no data.
  final int? fullFare;
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
  late Future<_TrainDetail> _future;

  bool get _isThsr => widget.type == '高鐵';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _future = _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<_TrainDetail> _load() async {
    final stops = _isThsr
        ? (await ThsrRepository.instance.stops(widget.date, widget.trainNo))
              .map((s) => _Stop(s.stationName, s.arrivalTime, s.departureTime))
              .toList()
        : (await TraRepository.instance.stops(widget.date, widget.trainNo))
              .map((s) => _Stop(s.stationName, s.arrivalTime, s.departureTime))
              .toList();

    if (stops.isEmpty) {
      return const _TrainDetail(stops: [], fullFare: null);
    }

    return _TrainDetail(
      stops: stops,
      fullFare: await _loadFare(stops.first.name, stops.last.name),
    );
  }

  /// Best-effort adult fare for the origin→destination pair. Returns null on
  /// any failure so the timetable still renders without a fare card.
  Future<int?> _loadFare(String originName, String destName) async {
    try {
      final table = _isThsr ? 'thsr_stations' : 'tra_stations';
      final originId = await _resolveStationId(table, originName);
      final destId = await _resolveStationId(table, destName);
      if (originId == null || destId == null) return null;

      if (_isThsr) {
        final fare = await ThsrRepository.instance.fare(
          widget.date,
          originId,
          destId,
        );
        return fare.price;
      }
      final fare = await TraRepository.instance.fare(
        '$originId:$destId',
        widget.date,
      );
      return fare.price;
    } on Object {
      return null;
    }
  }

  Future<String?> _resolveStationId(String table, String name) async {
    final rows = await PowerSyncService.instance.db.getAll(
      'SELECT station_id FROM $table WHERE station_name = ? LIMIT 1',
      [name],
    );
    if (rows.isEmpty) return null;
    return rows.first['station_id'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = widget.date.replaceAll('-', '/');

    return Scaffold(
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
      body: FutureBuilder<_TrainDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorStateView(
              error: AppError.from(snapshot.error!),
              onRetry: () => setState(() => _future = _load()),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final detail = snapshot.data!;
          if (detail.stops.isEmpty) {
            return Center(
              child: Text(
                '查無此車次的停靠資訊',
                style: AppTextStyles.bodyRegular.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
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
                    _TimetableTab(stops: detail.stops),
                    _InfoTab(
                      type: widget.type,
                      trainNo: widget.trainNo,
                      detail: detail,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TimetableTab extends StatelessWidget {
  const _TimetableTab({required this.stops});

  final List<_Stop> stops;

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

  Widget _times(_Stop stop, ColorScheme cs) {
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
    required this.detail,
  });

  final String type;
  final String trainNo;
  final _TrainDetail detail;

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
          if (detail.fullFare != null) _buildFares(cs, detail.fullFare!),
        ],
      ),
    );
  }

  Widget _buildTrainInfo(ColorScheme cs) {
    final origin = detail.stops.first;
    final dest = detail.stops.last;
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

  Widget _buildFares(ColorScheme cs, int fullFare) {
    // ponytail: API returns the adult fare only; child/disabled/companion are
    // half fare (floor) by TRA/THSR regulation. Add per-type queries if the
    // agencies ever diverge from the 半票 rule.
    final halfFare = fullFare ~/ 2;
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
        AppCard.filled(
          child: Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              for (final label in ['孩童', '愛心', '愛陪'])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '\$$halfFare',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
