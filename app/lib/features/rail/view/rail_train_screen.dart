import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/timeline_stop.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_card.dart';
import 'package:wheres_the_car/shared/widgets/bookmark_button.dart';
import 'package:wheres_the_car/shared/widgets/route_tab_bar.dart';

const _stubStops = [
  TimelineStop(
    uid: 'TW-0',
    name: '台北',
    secondaryTime: '07:00',
    secondaryLabel: '出發',
    lat: 25.0478,
    lon: 121.5170,
  ),
  TimelineStop(
    uid: 'TW-1',
    name: '板橋',
    primaryTime: '07:11',
    primaryLabel: '抵達',
    secondaryTime: '07:13',
    secondaryLabel: '出發',
    lat: 25.0143,
    lon: 121.4628,
  ),
  TimelineStop(
    uid: 'TW-2',
    name: '桃園',
    primaryTime: '07:31',
    primaryLabel: '抵達',
    secondaryTime: '07:33',
    secondaryLabel: '出發',
    lat: 24.9893,
    lon: 121.3145,
  ),
  TimelineStop(
    uid: 'TW-3',
    name: '新竹',
    primaryTime: '07:58',
    primaryLabel: '抵達',
    secondaryTime: '08:01',
    secondaryLabel: '出發',
    lat: 24.8017,
    lon: 120.9716,
  ),
  TimelineStop(
    uid: 'TW-4',
    name: '苗栗',
    primaryTime: '08:20',
    primaryLabel: '抵達',
    secondaryTime: '08:22',
    secondaryLabel: '出發',
    lat: 24.5603,
    lon: 120.8213,
  ),
  TimelineStop(
    uid: 'TW-5',
    name: '台中',
    primaryTime: '08:54',
    primaryLabel: '抵達',
    secondaryTime: '08:57',
    secondaryLabel: '出發',
    lat: 24.1369,
    lon: 120.6853,
    state: TimelineStopState.approaching,
    active: true,
  ),
  TimelineStop(
    uid: 'TW-6',
    name: '彰化',
    primaryTime: '09:08',
    primaryLabel: '抵達',
    secondaryTime: '09:10',
    secondaryLabel: '出發',
    lat: 24.0817,
    lon: 120.5387,
  ),
  TimelineStop(
    uid: 'TW-7',
    name: '雲林',
    primaryTime: '09:27',
    primaryLabel: '抵達',
    secondaryTime: '09:29',
    secondaryLabel: '出發',
    lat: 23.7565,
    lon: 120.4719,
  ),
  TimelineStop(
    uid: 'TW-8',
    name: '嘉義',
    primaryTime: '09:47',
    primaryLabel: '抵達',
    secondaryTime: '09:49',
    secondaryLabel: '出發',
    lat: 23.4803,
    lon: 120.4497,
  ),
  TimelineStop(
    uid: 'TW-9',
    name: '台南',
    primaryTime: '10:16',
    primaryLabel: '抵達',
    secondaryTime: '10:18',
    secondaryLabel: '出發',
    lat: 22.9972,
    lon: 120.2122,
  ),
  TimelineStop(
    uid: 'TW-10',
    name: '高雄',
    primaryTime: '10:45',
    primaryLabel: '抵達',
    lat: 22.6383,
    lon: 120.2866,
  ),
];

const _stubFares = [
  ('全票', r'$843'),
  ('孩童', r'$421'),
  ('敬老', r'$421'),
  ('愛心', r'$421'),
  ('愛陪', r'$421'),
];

class RailTrainScreen extends StatefulWidget {
  const RailTrainScreen({
    required this.type,
    required this.trainNo,
    super.key,
  });

  final String type;
  final String trainNo;

  @override
  State<RailTrainScreen> createState() => _RailTrainScreenState();
}

class _RailTrainScreenState extends State<RailTrainScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

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
      body: Column(
        children: [
          RouteTabBar(
            controller: _tabController,
            tabs: const ['時刻表', '車次詳細資訊'],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                const _TimetableTab(),
                _InfoTab(type: widget.type, trainNo: widget.trainNo),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimetableTab extends StatelessWidget {
  const _TimetableTab();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLight = cs.brightness == Brightness.light;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _stubStops.length,
      itemBuilder: (_, i) {
        final stop = _stubStops[i];
        final isHighlighted =
            stop.state == TimelineStopState.approaching || stop.active;

        final row = Row(
          children: [
            Expanded(
              child: Text(
                stop.name,
                style: AppTextStyles.bodyRegular.copyWith(
                  fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            _times(stop, cs, isHighlighted),
            const SizedBox(width: 12),
            _bell(cs, isLight, isHighlighted),
          ],
        );

        if (isHighlighted) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            ),
            child: row,
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: row,
        );
      },
    );
  }

  Widget _times(TimelineStop stop, ColorScheme cs, bool isHighlighted) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (stop.primaryTime != null)
          _timeRow('抵達', stop.primaryTime!, cs, isHighlighted),
        if (stop.secondaryTime != null)
          _timeRow('開車', stop.secondaryTime!, cs, isHighlighted),
      ],
    );
  }

  Widget _timeRow(String label, String time, ColorScheme cs, bool bold) {
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
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            fontFeatures: AppTextStyles.tabularFigures,
          ),
        ),
      ],
    );
  }

  Widget _bell(ColorScheme cs, bool isLight, bool isHighlighted) {
    final bg = isHighlighted
        ? cs.onSurface.withValues(alpha: 0.06)
        : cs.surfaceContainerHigh;
    final color = isHighlighted ? cs.onSurface : cs.outline;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Center(
        child: Icon(
          Icons.notifications_none_rounded,
          size: 16,
          color: color,
        ),
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.type, required this.trainNo});

  final String type;
  final String trainNo;

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
          _buildFares(cs),
        ],
      ),
    );
  }

  Widget _buildTrainInfo(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 5,
          children: [
            Expanded(
              child: Column(
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
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: 4,
                children: [
                  Text(
                    '方向',
                    style: _labelStyle.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const Text('南下', style: _valueStyle),
                ],
              ),
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
            const Row(
              spacing: 6,
              children: [
                Text('台北', style: _valueStyle),
                Text('→', style: _valueStyle),
                Text('高雄', style: _valueStyle),
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
            const Row(
              spacing: 6,
              children: [
                Text('07:00', style: _valueStyle),
                Text('→', style: _valueStyle),
                Text('10:45', style: _valueStyle),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFares(ColorScheme cs) {
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
                _stubFares.first.$1,
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                _stubFares.first.$2,
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
              for (final f in _stubFares.skip(1))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    Text(
                      f.$1,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      f.$2,
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
