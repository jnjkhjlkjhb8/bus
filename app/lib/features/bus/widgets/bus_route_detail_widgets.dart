part of '../view/bus_route_screen.dart';

class _RouteDetailTab extends StatelessWidget {
  const _RouteDetailTab({required this.state});
  final BusRouteState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final departures = _departuresFor(state);
    final timetable = _timetableFor(state);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          _NextDepartures(cs: cs, departures: departures),
          _RouteMeta(cs: cs, state: state),
          _Operators(cs: cs, operators: state.route?.operators ?? const []),
          _Fares(cs: cs, fare: state.fare),
          _Timetable(cs: cs, headsign: _headsignFor(state), rows: timetable),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.cs});
  final String text;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTextStyles.heading2.copyWith(color: cs.onSurfaceVariant),
  );
}

class _EmptyDetailText extends StatelessWidget {
  const _EmptyDetailText(this.text, {required this.cs});
  final String text;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return AppCard.filled(
      child: Text(
        text,
        style: AppTextStyles.bodyRegular.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _NextDepartures extends StatelessWidget {
  const _NextDepartures({required this.cs, required this.departures});
  final ColorScheme cs;
  final List<_DepartureInfo> departures;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _SectionLabel('今日發車班表', cs: cs),
        if (departures.isEmpty)
          _EmptyDetailText('尚無今日班表資料', cs: cs)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              spacing: 8,
              children: [
                for (final item in departures)
                  _DeparturePill(
                    time: item.time,
                    isNext: item.isNext,
                    cs: cs,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DeparturePill extends StatelessWidget {
  const _DeparturePill({
    required this.time,
    required this.isNext,
    required this.cs,
  });
  final String time;
  final bool isNext;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isNext ? cs.primary : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
      ),
      child: Text(
        time,
        style: AppTextStyles.bodyRegular.copyWith(
          fontFeatures: _tnum,
          fontWeight: isNext ? FontWeight.w600 : FontWeight.w400,
          color: isNext ? cs.onPrimary : cs.onSurface,
        ),
      ),
    );
  }
}

class _RouteMeta extends StatelessWidget {
  const _RouteMeta({required this.cs, required this.state});
  final ColorScheme cs;
  final BusRouteState state;

  @override
  Widget build(BuildContext context) {
    final route = state.route;
    final stops = state.currentStops;
    final origin = route?.departureStopName.isNotEmpty == true
        ? route!.departureStopName
        : (stops.isEmpty ? '-' : stops.first.stopName);
    final destination = route?.destinationStopName.isNotEmpty == true
        ? route!.destinationStopName
        : (stops.isEmpty ? '-' : stops.last.stopName);
    final city = route?.city.isNotEmpty == true ? route!.city : '-';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              _SectionLabel('主管機關', cs: cs),
              Text(city, style: AppTextStyles.bodyLarge),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 4,
            children: [
              _SectionLabel('起迄站', cs: cs),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 4,
                children: [
                  Flexible(
                    child: Text(
                      origin,
                      style: AppTextStyles.bodyLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Text('→', style: AppTextStyles.bodyLarge),
                  Flexible(
                    child: Text(
                      destination,
                      style: AppTextStyles.bodyLarge,
                      overflow: TextOverflow.ellipsis,
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

class _Operators extends StatelessWidget {
  const _Operators({required this.cs, required this.operators});
  final ColorScheme cs;
  final List<BusOperatorInfo> operators;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _SectionLabel('營運業者', cs: cs),
        if (operators.isEmpty)
          _EmptyDetailText('尚無營運業者資料', cs: cs)
        else
          AppCard.outlined(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, op) in operators.indexed) ...[
                  if (i > 0) const DividerLine(),
                  _OperatorRow(op: op, cs: cs),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _OperatorRow extends StatelessWidget {
  const _OperatorRow({required this.op, required this.cs});
  final BusOperatorInfo op;
  final ColorScheme cs;

  // TDX operator phones arrive as free text (e.g. "(02)2999-2020"); strip
  // formatting so the tel: URI dials.
  static Future<void> _dial(String phone) async {
    final digits = phone.replaceAll(RegExp('[^0-9+]'), '');
    if (digits.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: digits));
  }

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(
                  op.name.isEmpty ? '-' : op.name,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                if (op.phone.isNotEmpty)
                  Text(
                    op.phone,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontFeatures: _tnum,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (op.phone.isNotEmpty)
            _OperatorIconButton(
              icon: Icons.phone_outlined,
              label: '撥打 ${op.name} 電話',
              cs: cs,
              onTap: () => _dial(op.phone),
            ),
          if (op.url.isNotEmpty) ...[
            const SizedBox(width: 8),
            _OperatorIconButton(
              icon: Icons.language_outlined,
              label: '${op.name} 官方網站',
              cs: cs,
              onTap: () => _open(op.url),
            ),
          ],
        ],
      ),
    );
  }
}

class _OperatorIconButton extends StatelessWidget {
  const _OperatorIconButton({
    required this.icon,
    required this.label,
    required this.cs,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final ColorScheme cs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
        child: Icon(icon, size: 18, color: cs.onSurface),
      ),
    );
  }
}

class _Fares extends StatelessWidget {
  const _Fares({required this.cs, required this.fare});
  final ColorScheme cs;
  final BusFareInfo? fare;

  @override
  Widget build(BuildContext context) {
    final fare = this.fare;
    final od = decodeOdFares(fare);
    final range = odFareRange(od);
    // City buses have no origin→destination table; their class rows are short
    // enough to sit inline. Only 公路客運 with an OD table gets the accordion.
    final flatGroups = od.isEmpty
        ? decodeFareTable(fare)
        : const <FareGroup>[];
    final odCount = od.fold<int>(0, (n, o) => n + o.destinations.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _SectionLabel('票價資訊', cs: cs),
        if (fare == null)
          _EmptyDetailText('尚無票價資料', cs: cs)
        else ...[
          AppCard.outlined(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _FareFact(
                        label: '票價型態',
                        value: _farePricingTypeLabel(fare.pricingType),
                        cs: cs,
                      ),
                    ),
                    _FareFact(
                      label: '收費方式',
                      value: fare.isFreeBus ? '免費' : '需付費',
                      alignEnd: true,
                      cs: cs,
                    ),
                  ],
                ),
                if (od.isNotEmpty && range != null)
                  _FareRangeLine(range: range, cs: cs)
                else
                  for (final (i, group) in flatGroups.indexed)
                    _FareGroupBlock(group: group, showDivider: i > 0, cs: cs),
              ],
            ),
          ),
          if (od.isNotEmpty)
            AppAccordion(
              title: '完整起迄票價（$odCount 筆）',
              child: _OdFareTable(origins: od, cs: cs),
            ),
        ],
      ],
    );
  }
}

class _FareRangeLine extends StatelessWidget {
  const _FareRangeLine({required this.range, required this.cs});
  final ({int min, int max}) range;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final label = range.min == range.max
        ? 'NT\$${range.min}'
        : 'NT\$${range.min} – NT\$${range.max}';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '票價範圍',
              style: AppTextStyles.bodyRegular.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            label,
            style: AppTextStyles.bodyLarge.copyWith(
              fontFeatures: _tnum,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Searchable, origin-grouped 起迄 fare table. Rendered inside a collapsed
/// accordion, so it never dominates the detail tab. Rows are capped and the
/// remainder surfaced through search rather than an endless flat list.
class _OdFareTable extends StatefulWidget {
  const _OdFareTable({required this.origins, required this.cs});
  final List<OdOrigin> origins;
  final ColorScheme cs;

  @override
  State<_OdFareTable> createState() => _OdFareTableState();
}

class _OdFareTableState extends State<_OdFareTable> {
  static const int _maxRows = 80;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final q = _query.trim();
    // An origin match shows all its destinations; otherwise only the
    // destinations whose name matches, dropping origins with no hit.
    final matches = <OdOrigin>[];
    for (final origin in widget.origins) {
      if (q.isEmpty || origin.origin.contains(q)) {
        matches.add(origin);
        continue;
      }
      final dests = [
        for (final d in origin.destinations)
          if (d.destination.contains(q)) d,
      ];
      if (dests.isNotEmpty) {
        matches.add((origin: origin.origin, destinations: dests));
      }
    }

    final blocks = <Widget>[];
    var shown = 0;
    var truncated = false;
    for (final origin in matches) {
      if (shown >= _maxRows) {
        truncated = true;
        break;
      }
      final dests = origin.destinations.length + shown > _maxRows
          ? origin.destinations.sublist(0, _maxRows - shown)
          : origin.destinations;
      if (dests.length < origin.destinations.length) truncated = true;
      blocks.add(_originBlock(origin.origin, dests, cs));
      shown += dests.length;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppInput(
          label: '搜尋站牌',
          hint: '輸入起站或迄站名稱',
          prefixIcon: Icon(
            Icons.search,
            size: 20,
            color: cs.onSurfaceVariant,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        if (matches.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '查無「$q」相關站牌',
              style: AppTextStyles.bodyRegular.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          ...blocks,
          if (truncated)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '僅顯示前 $_maxRows 筆，輸入站牌以查詢其餘票價',
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _originBlock(
    String origin,
    List<OdDestination> dests,
    ColorScheme cs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 2),
          child: Row(
            children: [
              Text(
                origin,
                style: AppTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '出發',
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        for (final dest in dests) _destRow(dest, cs),
      ],
    );
  }

  Widget _destRow(OdDestination dest, ColorScheme cs) {
    // Usually one row (全票); multi-class OD entries append the class label so
    // 全票 / 半票 prices stay distinguishable.
    final multi = dest.rows.length > 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              dest.destination,
              style: AppTextStyles.bodyRegular.copyWith(color: cs.onSurface),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 2,
            children: [
              for (final row in dest.rows)
                Text(
                  multi ? '${row.label} ${row.price}' : row.price,
                  style: AppTextStyles.bodyRegular.copyWith(
                    fontFeatures: _tnum,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FareGroupBlock extends StatelessWidget {
  const _FareGroupBlock({
    required this.group,
    required this.showDivider,
    required this.cs,
  });
  final FareGroup group;
  final bool showDivider;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Separate consecutive segments (公路客運 起迄 / 分段) with a hairline so
        // each origin→destination block reads as its own fare panel.
        if (showDivider)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: DividerLine(),
          ),
        if (group.segment case final segment?)
          Padding(
            padding: EdgeInsets.only(top: showDivider ? 0 : 12, bottom: 4),
            child: Text(
              segment,
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        for (final row in group.rows)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  row.price,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontFeatures: _tnum,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FareFact extends StatelessWidget {
  const _FareFact({
    required this.label,
    required this.value,
    required this.cs,
    this.alignEnd = false,
  });
  final String label;
  final String value;
  final ColorScheme cs;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      spacing: 3,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
        Text(
          value,
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}

class _Timetable extends StatelessWidget {
  const _Timetable({
    required this.cs,
    required this.headsign,
    required this.rows,
  });
  final ColorScheme cs;
  final String headsign;
  final List<_TimetableInfo> rows;

  static const int _columns = 4;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _SectionLabel('班表', cs: cs),
        if (rows.isEmpty)
          _EmptyDetailText('尚無班表資料', cs: cs)
        else
          AppCard.outlined(padding: EdgeInsets.zero, child: _board()),
      ],
    );
  }

  Widget _board() {
    // Chunk the day's departures into fixed-width columns so the board reads as
    // a scannable timetable rather than a list. The headsign is stated once in
    // the header instead of repeating on every trip.
    final gridRows = <List<_TimetableInfo?>>[];
    for (var i = 0; i < rows.length; i += _columns) {
      final end = i + _columns < rows.length ? i + _columns : rows.length;
      final chunk = rows.sublist(i, end);
      gridRows.add([
        ...chunk,
        for (var p = chunk.length; p < _columns; p++) null,
      ]);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '往 ',
                        style: AppTextStyles.bodyRegular.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      TextSpan(
                        text: headsign,
                        style: AppTextStyles.bodyRegular.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${rows.length} 班次',
                style: AppTextStyles.bodySmall.copyWith(
                  fontFeatures: _tnum,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        for (final gridRow in gridRows) ...[
          const DividerLine(),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, cell) in gridRow.indexed) ...[
                  if (i > 0 && cell != null)
                    VerticalDivider(
                      width: 0.5,
                      thickness: 0.5,
                      color: cs.outlineVariant,
                    ),
                  Expanded(child: _cell(cell)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _cell(_TimetableInfo? info) {
    if (info == null) return const SizedBox.shrink();
    // The next not-yet-departed trip is highlighted in place (static, per the
    // no-pulse rule): highlight fill + heavier tabular time.
    final highlight = cs.brightness == Brightness.light
        ? AppTheme.surfaceHighlightLight
        : AppTheme.surfaceHighlightDark;
    return Container(
      color: info.isNext ? highlight : null,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            info.time,
            style: AppTextStyles.memo.copyWith(
              fontSize: 16,
              fontFeatures: _tnum,
              fontWeight: info.isNext ? FontWeight.w700 : FontWeight.w400,
              color: cs.onSurface,
            ),
          ),
          // Fixed-height tag slot keeps the time baseline aligned across the
          // grid whether or not a cell carries a tag. 下一班 wins over 低地板
          // when a trip is both.
          SizedBox(
            height: 14,
            child: info.isNext
                ? _tag('下一班', cs.onSurface, FontWeight.w700)
                : info.lowFloor
                ? _tag('低地板', cs.onSurfaceVariant, FontWeight.w600)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color, FontWeight weight) => Text(
    text,
    style: AppTextStyles.bodySmall.copyWith(
      fontSize: 10,
      height: 1.2,
      fontWeight: weight,
      color: color,
    ),
  );
}
