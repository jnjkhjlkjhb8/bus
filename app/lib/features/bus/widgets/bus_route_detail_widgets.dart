part of '../view/bus_route_screen.dart';

class _RouteDetailTab extends StatelessWidget {
  const _RouteDetailTab({required this.state});
  final BusRouteState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final departures = _departuresFor(state);
    final timetable = _timetableFor(state);
    final fareRows = _fareRows(state.fare);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 24,
        children: [
          _NextDepartures(cs: cs, departures: departures),
          _RouteMeta(cs: cs, state: state),
          _Fares(cs: cs, rows: fareRows),
          _Timetable(cs: cs, rows: timetable),
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

class _Fares extends StatelessWidget {
  const _Fares({required this.cs, required this.rows});
  final ColorScheme cs;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _SectionLabel('票價資訊', cs: cs),
        if (rows.isEmpty)
          _EmptyDetailText('尚無票價資料', cs: cs)
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final row in rows)
                SizedBox(
                  width: 148,
                  child: _FareTile(label: row.$1, price: row.$2, cs: cs),
                ),
            ],
          ),
      ],
    );
  }
}

class _FareTile extends StatelessWidget {
  const _FareTile({
    required this.label,
    required this.price,
    required this.cs,
  });
  final String label;
  final String price;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return AppCard.outlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          Text(
            price,
            style: AppTextStyles.heading1.copyWith(
              fontFeatures: _tnum,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _Timetable extends StatelessWidget {
  const _Timetable({required this.cs, required this.rows});
  final ColorScheme cs;
  final List<_TimetableInfo> rows;

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
          AppCard.outlined(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _row('往', '時間', '班次', '車型', isHeader: true),
                for (final r in rows) ...[
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: cs.outlineVariant,
                    indent: 12,
                    endIndent: 12,
                  ),
                  _row(r.destination, r.time, r.trip, r.vehicle),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(String a, String b, String c, String d, {bool isHeader = false}) {
    final style = isHeader
        ? AppTextStyles.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          )
        : AppTextStyles.bodySmall.copyWith(color: cs.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          for (final cell in [a, b, c, d])
            Expanded(
              child: Text(
                cell,
                style: cell == b ? style.copyWith(fontFeatures: _tnum) : style,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
