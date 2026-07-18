part of '../view/go_screen.dart';

/// Plan-preview sheet: the single selected route shown as a full itinerary on
/// the same map-and-sheet screen. Swaps in for the results list when a route is
/// selected; navigation can only be started from here.
class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({
    required this.controller,
    required this.initialOffset,
    required this.route,
    required this.isFastest,
    required this.isSaved,
    required this.origin,
    required this.dest,
    required this.onBack,
    required this.onStartNavigation,
    required this.onToggleSave,
    super.key,
  });

  final SheetController controller;
  final SheetOffset initialOffset;
  final PlanRoute route;

  /// Whether this route is the fastest of a multi-route result (drives 最快).
  final bool isFastest;
  final bool isSaved;
  final String? origin;
  final String? dest;
  final VoidCallback onBack;
  final VoidCallback onStartNavigation;
  final VoidCallback onToggleSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sections = route.sections;
    final firstDeparture = sections.isEmpty
        ? ''
        : sections.first.departure.name;
    final originName = _firstNonEmpty([origin, firstDeparture, '出發地']);
    // _lastNamedArrival always resolves (falls back to 目的地).
    final destName = _firstNonEmpty([dest, _lastNamedArrival(sections)]);
    return SheetViewport(
      child: SheetExitGestureDetector(
        onExit: onBack,
        child: Sheet(
          controller: controller,
          initialOffset: initialOffset,
          snapGrid: AppSheetSnap.grid,
          scrollConfiguration: const SheetScrollConfiguration(),
          decoration: MaterialSheetDecoration(
            size: SheetSize.stretch,
            color: cs.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusBottomSheet),
            ),
            clipBehavior: Clip.antiAlias,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetDragHandle(),
              _PreviewSummaryHeader(
                route: route,
                originName: originName,
                destName: destName,
                isFastest: isFastest,
                isSaved: isSaved,
                onBack: onBack,
                onToggleSave: onToggleSave,
              ),
              const DividerLine(),
              Expanded(
                child: _PreviewItinerary(route: route, destName: destName),
              ),
              _PreviewFooter(onStartNavigation: onStartNavigation),
            ],
          ),
        ),
      ),
    );
  }
}

String _firstNonEmpty(List<String?> candidates) {
  for (final c in candidates) {
    if (c != null && c.isNotEmpty) return c;
  }
  return '';
}

/// Header: back chevron + origin→destination summary, then the big mono minutes
/// with the 最快 badge and metadata (出發 above 抵達, fare, walk time).
class _PreviewSummaryHeader extends StatelessWidget {
  const _PreviewSummaryHeader({
    required this.route,
    required this.originName,
    required this.destName,
    required this.isFastest,
    required this.isSaved,
    required this.onBack,
    required this.onToggleSave,
  });

  final PlanRoute route;
  final String originName;
  final String destName;
  final bool isFastest;
  final bool isSaved;
  final VoidCallback onBack;
  final VoidCallback onToggleSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minutes = routeMinutes(route);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pressable(
                onTap: onBack,
                semanticLabel: '返回路線列表',
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 26,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        originName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        destName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _PreviewSaveButton(saved: isSaved, onTap: onToggleSave),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$minutes',
                            style: AppTextStyles.memo.copyWith(
                              fontSize: AppTextStyles.heading1.fontSize,
                              fontWeight: AppTextStyles.heading1.fontWeight,
                              color: cs.onSurface,
                              fontFeatures: AppTextStyles.tabularFigures,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '分',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (isFastest) ...[
                            const SizedBox(width: 8),
                            const _PreviewBadge(label: '最快'),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      _PreviewMeta(route: route),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _PreviewClock(
                      label: '出發',
                      value: formatClock(route.startTime),
                    ),
                    const SizedBox(height: 4),
                    _PreviewClock(
                      label: '抵達',
                      value: formatClock(route.endTime),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Walk time and fare line under the minutes. Fare is omitted when unresolved.
class _PreviewMeta extends StatelessWidget {
  const _PreviewMeta({required this.route});

  final PlanRoute route;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          Icons.directions_walk_rounded,
          size: 14,
          color: cs.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          '步行 ${walkMinutes(route)} 分',
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
        if (route.totalFare > 0) ...[
          const SizedBox(width: 12),
          Text(
            r'NT$ ',
            style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
          ),
          Text(
            '${route.totalFare}',
            style: AppTextStyles.memo.copyWith(
              fontSize: AppTextStyles.bodySmall.fontSize,
              color: cs.onSurface,
              fontFeatures: AppTextStyles.tabularFigures,
            ),
          ),
        ],
      ],
    );
  }
}

/// A stacked label + mono time value (出發 / 抵達).
class _PreviewClock extends StatelessWidget {
  const _PreviewClock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (value.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: AppTextStyles.memo.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
            fontFeatures: AppTextStyles.tabularFigures,
          ),
        ),
      ],
    );
  }
}

/// Solid Ink pill badge (最快). Mirrors the results card badge vocabulary.
class _PreviewBadge extends StatelessWidget {
  const _PreviewBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.onSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodyVerySmall.copyWith(
          color: cs.surface,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PreviewSaveButton extends StatelessWidget {
  const _PreviewSaveButton({required this.saved, required this.onTap});

  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: saved ? '取消保存路線' : '保存路線',
      child: SizedBox(
        width: 40,
        height: 40,
        child: AnimatedSwitcher(
          duration: AppMotion.short,
          child: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            key: ValueKey(saved),
            size: 20,
            color: saved ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Vertical timeline of the previewed route. The left rail echoes the map
/// marker language — origin node (Ink ring), transit boundary nodes (leg-color
/// ring), destination node (Ink filled); connectors are dotted gray for walk
/// sections and solid leg-color for transit sections.
class _PreviewItinerary extends StatelessWidget {
  const _PreviewItinerary({required this.route, required this.destName});

  final PlanRoute route;
  final String destName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sections = route.sections;
    final rows = <Widget>[];
    for (final (i, s) in sections.indexed) {
      final walk = isWalk(s);
      rows.add(
        _PreviewRow(
          nodeRing: _nodeRing(i, sections, cs),
          nodeFilled: false,
          connectorColor: walk
              ? cs.outlineVariant
              : transitColor(s.transport, cs),
          dashed: walk,
          showConnector: true,
          minutes: sectionMinutes(s),
          content: walk
              ? _walkContent(context, i, s)
              : _transitContent(context, s),
        ),
      );
    }
    rows.add(
      _PreviewRow(
        nodeRing: cs.onSurface,
        nodeFilled: true,
        connectorColor: cs.outlineVariant,
        dashed: false,
        showConnector: false,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              destName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            if (formatClock(route.endTime).isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '預計 ${formatClock(route.endTime)} 抵達',
                style: AppTextStyles.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                  fontFeatures: AppTextStyles.tabularFigures,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      children: rows,
    );
  }

  // Ring color for section i's departure node: origin is Ink, a boarding node
  // takes its own leg color, an alighting-into-walk node takes the previous
  // leg's color, else Ink.
  Color _nodeRing(int i, List<PlanSection> sections, ColorScheme cs) {
    if (i == 0) return cs.onSurface;
    final s = sections[i];
    if (!isWalk(s)) return transitColor(s.transport, cs);
    final prev = sections[i - 1];
    if (!isWalk(prev)) return transitColor(prev.transport, cs);
    return cs.onSurface;
  }

  Widget _walkContent(BuildContext context, int i, PlanSection s) {
    final cs = Theme.of(context).colorScheme;
    final sections = route.sections;
    final nextBoard = i + 1 < sections.length
        ? sections[i + 1].departure.name
        : '';
    final target = _firstNonEmpty([s.arrival.name, nextBoard, destName]);
    return Text(
      '步行至 $target',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.bodyRegular.copyWith(
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
    );
  }

  Widget _transitContent(BuildContext context, PlanSection s) {
    final cs = Theme.of(context).colorScheme;
    final color = transitColor(s.transport, cs);
    final rideStops = s.intermediateStops.length + 1;
    final headsign = s.transport.headsign;
    final legLine =
        '搭 $rideStops 站${headsign.isNotEmpty ? ' · 往$headsign' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppBadge(label: sectionLabel(s), color: color),
        const SizedBox(height: 6),
        Text(
          '${s.departure.name} → ${s.arrival.name}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyRegular.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          legLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// One timeline row: the left rail (node + connector) beside the section
/// content, with right-aligned mono minutes.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.nodeRing,
    required this.nodeFilled,
    required this.connectorColor,
    required this.dashed,
    required this.showConnector,
    required this.content,
    this.minutes,
  });

  final Color nodeRing;
  final bool nodeFilled;
  final Color connectorColor;
  final bool dashed;
  final bool showConnector;
  final Widget content;
  final int? minutes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                _node(cs),
                if (showConnector)
                  Expanded(
                    child: CustomPaint(
                      size: const Size(24, double.infinity),
                      painter: _ConnectorPainter(
                        color: connectorColor,
                        dashed: dashed,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: showConnector ? 20 : 0),
              child: content,
            ),
          ),
          if (minutes != null) ...[
            const SizedBox(width: 12),
            Text(
              '$minutes 分',
              style: AppTextStyles.memo.copyWith(
                fontSize: AppTextStyles.bodyRegular.fontSize,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                fontFeatures: AppTextStyles.tabularFigures,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _node(ColorScheme cs) {
    if (nodeFilled) {
      // Destination: Ink-filled disc with a small white inner dot — the
      // heaviest node, mirroring the map's destination marker.
      return Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: nodeRing, shape: BoxShape.circle),
        child: Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: cs.surface,
        shape: BoxShape.circle,
        border: Border.all(color: nodeRing, width: 2.5),
      ),
    );
  }
}

/// Pinned primary CTA that commits the previewed route to navigation.
class _PreviewFooter extends StatelessWidget {
  const _PreviewFooter({required this.onStartNavigation});

  final VoidCallback onStartNavigation;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottomInset),
      child: SizedBox(
        width: double.infinity,
        child: AppButton(label: '開始導航', onPressed: onStartNavigation),
      ),
    );
  }
}
