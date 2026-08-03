part of '../view/bus_route_screen.dart';

class _RouteDetailTab extends StatelessWidget {
  const _RouteDetailTab({required this.state});
  final BusRouteState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final departures = _departuresFor(state);
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
          _Timetable(cs: cs, headsign: _headsignFor(state), state: state),
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
        _SectionLabel(AppI18n.of(context).busNextDepartures, cs: cs),
        if (departures.isEmpty)
          _EmptyDetailText(AppI18n.of(context).busNoDepartures, cs: cs)
        else
          // Edge fade signals the strip is scrollable instead of cutting the
          // last pill off mid-glyph with no affordance. The gradient is a
          // mask (dstIn), not UI color, so it sits outside the token rule.
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0, 0.03, 0.94, 1],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
    // route.city is a TDX county code (e.g. "Taoyuan"), and it names where
    // the route operates, not a regulator — map it to its Chinese name
    // rather than label it 主管機關 and leak the English identifier.
    final city = route?.city.isNotEmpty == true
        ? _dtCityLabel(AppI18n.of(context), route!.city)
        : '-';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              _SectionLabel(AppI18n.of(context).busOperatingCities, cs: cs),
              Text(city, style: AppTextStyles.bodyLarge),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 4,
            children: [
              _SectionLabel(AppI18n.of(context).busEndpoints, cs: cs),
              _originDestinationLine(
                context,
                origin: origin,
                destination: destination,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // At large text-scale factors, two Flexible halves of a Row squeeze each
  // station name down to a single ellipsised glyph (verified at 2.0x). Measure
  // both labels against the width actually on offer and fall back to a
  // stacked column instead of destroying the names.
  Widget _originDestinationLine(
    BuildContext context, {
    required String origin,
    required String destination,
  }) {
    const style = AppTextStyles.bodyLarge;
    const arrow = '→';
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        double widthOf(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout();
          return painter.width;
        }

        final needed =
            widthOf(origin) + widthOf(arrow) + widthOf(destination) + 8;
        final fits =
            constraints.maxWidth.isFinite && needed <= constraints.maxWidth;
        if (fits) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: 4,
            children: [
              Flexible(
                child: Text(
                  origin,
                  style: style,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Text(arrow, style: style),
              Flexible(
                child: Text(
                  destination,
                  style: style,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: 2,
          children: [
            Text(origin, style: style, textAlign: TextAlign.end),
            const Text('↓', style: style),
            Text(destination, style: style, textAlign: TextAlign.end),
          ],
        );
      },
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
        _SectionLabel(AppI18n.of(context).busOperators, cs: cs),
        if (operators.isEmpty)
          _EmptyDetailText(AppI18n.of(context).busNoOperators, cs: cs)
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
    final inApp = uri.scheme == 'https' || uri.scheme == 'http';
    if (inApp) {
      try {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        return;
      } on Object catch (_) {
        // Fall through to the external handler below.
      }
    }
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
              label: AppI18n.of(context).callOperator(op.name),
              cs: cs,
              onTap: () => _dial(op.phone),
            ),
          if (op.url.isNotEmpty) ...[
            const SizedBox(width: 8),
            _OperatorIconButton(
              icon: Icons.language_outlined,
              label: AppI18n.of(context).operatorWebsite(op.name),
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
    final od = decodeOdFares(AppI18n.of(context), fare);
    // City buses have no origin→destination table; their class rows are short
    // enough to sit inline. Only 公路客運 with an OD table gets the accordion.
    final flatGroups = od.isEmpty
        ? decodeFareTable(AppI18n.of(context), fare)
        : const <FareGroup>[];
    final odCount = od.fold<int>(0, (n, o) => n + o.destinations.length);

    return FarePreferenceBuilder(
      builder: (context, fareType) {
        final range = odFareRange(od, fareType);
        // A genuine range (min != max) means the OD table really does carry
        // per-stop variation, which contradicts TDX's own 一段票 (flat-fare)
        // label for some routes — reconcile them instead of showing both.
        final hasFareRange =
            od.isNotEmpty && range != null && range.min != range.max;
        // Every class the route prices, for the 全部票種 disclosure. A route
        // that only ever publishes 全票 gets no disclosure rather than one
        // that opens onto a single row the rider is already looking at.
        final allClasses = _fareClassCount(flatGroups, od);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            _SectionLabel(AppI18n.of(context).busFareInfo, cs: cs),
            if (fare == null)
              _EmptyDetailText(AppI18n.of(context).busNoFare, cs: cs)
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
                            label: AppI18n.of(context).busFarePricingType,
                            value: _farePricingTypeLabel(
                              AppI18n.of(context),
                              fare.pricingType,
                              hasFareRange: hasFareRange,
                            ),
                            cs: cs,
                          ),
                        ),
                        // "需付費" told the rider nothing they didn't already
                        // know; 免費 is the only value of this fact worth a
                        // slot.
                        if (fare.isFreeBus)
                          _FareFact(
                            label: AppI18n.of(context).busFareChargingMethod,
                            value: AppI18n.of(context).busFareFree,
                            alignEnd: true,
                            cs: cs,
                          ),
                      ],
                    ),
                    if (od.isNotEmpty && range != null)
                      _FareRangeLine(
                        range: range,
                        fareType: fareType,
                        cs: cs,
                      )
                    else
                      for (final (i, group) in flatGroups.indexed)
                        _FareGroupBlock(
                          group: group,
                          fareType: fareType,
                          showDivider: i > 0,
                          cs: cs,
                        ),
                  ],
                ),
              ),
              // The rider's own ticket type is the headline above; the rest of
              // the classes stay one tap away rather than stacking six rows
              // per segment on a screen read at a bus stop.
              if (allClasses > 1 && flatGroups.isNotEmpty)
                AppAccordion(
                  title: AppI18n.of(
                    context,
                  ).busAllFareClasses(allClasses),
                  child: _AllFareClasses(groups: flatGroups, cs: cs),
                ),
              if (od.isNotEmpty)
                AppAccordion(
                  title: AppI18n.of(
                    context,
                  ).busAllOdFares(odCount),
                  child: _OdFareTable(
                    origins: od,
                    fareType: fareType,
                    cs: cs,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// How many distinct fare classes the route prices anywhere, which decides
/// whether a 全部票種 disclosure has anything to disclose.
int _fareClassCount(List<FareGroup> groups, List<OdOrigin> origins) {
  final classes = <int>{};
  for (final group in groups) {
    for (final row in group.rows) {
      classes.add(row.fareClass);
    }
  }
  for (final origin in origins) {
    for (final dest in origin.destinations) {
      for (final row in dest.rows) {
        classes.add(row.fareClass);
      }
    }
  }
  return classes.length;
}

/// Every fare class the route prices, per segment. The rider's own type is
/// already shown above, so this is reference material: a plain label/price
/// list, no highlighting, no second hierarchy competing with the headline.
class _AllFareClasses extends StatelessWidget {
  const _AllFareClasses({required this.groups, required this.cs});
  final List<FareGroup> groups;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, group) in groups.indexed) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: DividerLine(),
            ),
          if (group.segment case final segment?)
            Padding(
              padding: EdgeInsets.only(top: i > 0 ? 0 : 4, bottom: 2),
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
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      style: AppTextStyles.bodyRegular.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    row.price,
                    style: AppTextStyles.bodyRegular.copyWith(
                      fontFeatures: _tnum,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _FareRangeLine extends StatelessWidget {
  const _FareRangeLine({
    required this.range,
    required this.fareType,
    required this.cs,
  });
  final ({int min, int max}) range;

  /// The ticket type [range] was computed for. Named on the row, because a
  /// range with no ticket type beside it reads as the standard fare.
  final FareType fareType;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final label = range.min == range.max
        ? 'NT\$${range.min}'
        : 'NT\$${range.min} – NT\$${range.max}';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              i18n.busFareRange(fareType.labelOf(i18n)),
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
  const _OdFareTable({
    required this.origins,
    required this.fareType,
    required this.cs,
  });
  final List<OdOrigin> origins;

  /// The rider's ticket type. Each destination shows the one price they pay;
  /// listing every class per destination turned an 80-row table into a 300-row
  /// one nobody scrolled to the bottom of.
  final FareType fareType;
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
          label: AppI18n.of(context).busSearchStops,
          hint: AppI18n.of(context).busSearchStopsHint,
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
              AppI18n.of(context).busNoStopMatch(q),
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
                AppI18n.of(context).busFareTruncated(_maxRows),
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
                AppI18n.of(context).busDepart,
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
    final picked = pickFareRow(dest.rows, widget.fareType);
    if (picked == null) return const SizedBox.shrink();
    // The class label rides along only when it is not what the rider asked
    // for — otherwise the whole column repeats their own ticket type on every
    // row, which the section heading already states once.
    final needsLabel = picked.matched != widget.fareType;
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
          Text(
            needsLabel
                ? '${picked.row.label} ${picked.row.price}'
                : picked.row.price,
            style: AppTextStyles.bodyRegular.copyWith(
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

/// One segment's headline price: the single row the rider actually pays. Every
/// other class for the segment lives in the 全部票種 disclosure — stacking all
/// six here is what made this block unreadable at a stop.
class _FareGroupBlock extends StatelessWidget {
  const _FareGroupBlock({
    required this.group,
    required this.fareType,
    required this.showDivider,
    required this.cs,
  });
  final FareGroup group;
  final FareType fareType;
  final bool showDivider;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final picked = pickFareRow(group.rows, fareType);
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
        if (picked != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    // The matched label, not the requested one: a segment that
                    // prices no 敬老票 says 全票 here rather than mislabelling
                    // the standard fare as a concession.
                    picked.matched == fareType
                        ? picked.row.label
                        : i18n.busFareMissing(
                            picked.row.label,
                            fareType.labelOf(i18n),
                          ),
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  picked.row.price,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontFeatures: _tnum,
                    fontWeight: FontWeight.w600,
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

class _Timetable extends StatefulWidget {
  const _Timetable({
    required this.cs,
    required this.headsign,
    required this.state,
  });
  final ColorScheme cs;
  final String headsign;
  final BusRouteState state;

  static const int _columns = 4;

  @override
  State<_Timetable> createState() => _TimetableState();
}

class _TimetableState extends State<_Timetable> {
  late int _day = busWeekdayIndex(DateTime.now());

  ColorScheme get cs => widget.cs;

  @override
  Widget build(BuildContext context) {
    final schedules = _schedulesFor(widget.state);
    final serviceDays = busServiceDays(schedules);
    final timetable = _timetableFor(widget.state, _day);
    final today = busWeekdayIndex(DateTime.now());
    // Without a weekly pattern only today is knowable: showing a day picker
    // would offer six answers the data cannot give.
    final weekly = serviceDays.isNotEmpty;
    final reduceMotion = AppMotion.reduced(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _SectionLabel(AppI18n.of(context).busTimetable, cs: cs),
        if (!weekly && timetable.departures.isEmpty)
          _EmptyDetailText(AppI18n.of(context).busNoTimetable, cs: cs)
        else ...[
          if (weekly)
            AppSlidingSegment<int>(
              options: {
                for (final (i, label) in _dtWeekdayLabels(
                  AppI18n.of(context),
                ).indexed)
                  i: label,
              },
              value: _day,
              // A day the route does not run reads as an answer before the tap
              // — the muted label is the "沒有班" the picker exists to give.
              muted: {
                for (var d = 0; d < 7; d++)
                  if (!serviceDays.contains(d) &&
                      !(d == today && timetable.departures.isNotEmpty))
                    d,
              },
              onChanged: (day) => setState(() => _day = day),
            ),
          AnimatedSize(
            duration: reduceMotion ? AppMotion.instant : AppMotion.micro,
            curve: AppMotion.easeOut,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              // The board is data, so days cross-fade in place rather than
              // sliding: nothing travels, the numbers just change.
              duration: reduceMotion ? AppMotion.instant : AppMotion.micro,
              switchInCurve: AppMotion.easeOut,
              switchOutCurve: AppMotion.easeOut,
              child: KeyedSubtree(
                key: ValueKey((_day, widget.state.direction)),
                child: AppCard.outlined(
                  padding: EdgeInsets.zero,
                  child: _board(timetable),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _dayLabel(AppI18n i18n) =>
      i18n.busWeekday(_dtWeekdayLabels(i18n)[_day]);

  Widget _board(BusDayTimetable timetable) {
    final rows = timetable.departures;
    // Chunk the day's departures into fixed-width columns so the board reads as
    // a scannable timetable rather than a list. The headsign is stated once in
    // the header instead of repeating on every trip.
    final gridRows = <List<BusTimetableCell?>>[];
    for (var i = 0; i < rows.length; i += _Timetable._columns) {
      final end = i + _Timetable._columns < rows.length
          ? i + _Timetable._columns
          : rows.length;
      final chunk = rows.sublist(i, end);
      gridRows.add([
        ...chunk,
        for (var p = chunk.length; p < _Timetable._columns; p++) null,
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
                        text: AppI18n.of(context).towardsPrefix,
                        style: AppTextStyles.bodyRegular.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      TextSpan(
                        text: widget.headsign,
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
                rows.isEmpty
                    ? _dayLabel(AppI18n.of(context))
                    : AppI18n.of(context).busRunCount(rows.length),
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
        // Headway routes publish no departure times at all, so the window is
        // the whole answer; routes that publish both get it as a footer.
        for (final window in timetable.windows) ...[
          const DividerLine(),
          _HeadwayRow(window: window, cs: cs),
        ],
        if (rows.isEmpty && timetable.windows.isEmpty) ...[
          const DividerLine(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Text(
              AppI18n.of(context).busNotRunningToday,
              style: AppTextStyles.bodyRegular.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _cell(BusTimetableCell? info) {
    if (info == null) return const SizedBox.shrink();
    // The next not-yet-departed trip is highlighted in place (static, per the
    // no-pulse rule): highlight fill + heavier tabular time.
    final highlight = AppTheme.surfaceHighlight(cs.brightness);
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
          // Minimum-height tag slot keeps the time baseline aligned across
          // the grid whether or not a cell carries a tag, while still
          // growing with the tag text at large accessibility scales instead
          // of clipping it. 下一班 wins over 低地板 when a trip is both.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 14),
            child: info.isNext
                ? _tag(
                    AppI18n.of(context).busNextRun,
                    cs.onSurface,
                    FontWeight.w700,
                  )
                : info.lowFloor
                ? _tag(
                    AppI18n.of(context).busLowFloor,
                    cs.onSurfaceVariant,
                    FontWeight.w600,
                  )
                : const SizedBox.shrink(),
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

/// A headway-operated window on the timetable board: the service span in mono
/// so it aligns with the departure grid above it, the interval as prose.
class _HeadwayRow extends StatelessWidget {
  const _HeadwayRow({required this.window, required this.cs});
  final BusHeadwayWindow window;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    // TDX sends both bounds even when they are equal; "每 15 分" is the honest
    // reading of a 15–15 range.
    final headway = window.minMins == window.maxMins
        ? AppI18n.of(context).busHeadwayFixed(window.minMins)
        : AppI18n.of(context).busHeadwayRange(window.minMins, window.maxMins);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        spacing: 12,
        children: [
          Text(
            '${window.start}–${window.end}',
            style: AppTextStyles.memo.copyWith(
              fontSize: 16,
              fontFeatures: _tnum,
              color: cs.onSurface,
            ),
          ),
          Expanded(
            child: Text(
              headway,
              style: AppTextStyles.bodyRegular.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
