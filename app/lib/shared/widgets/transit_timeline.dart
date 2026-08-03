/// The shared vertical route spine used by every stop list — bus route stops
/// and rail train stops alike.
///
/// The two screens show the same fact in two vehicles (a line of stops, a
/// vehicle somewhere along it), so they draw it with one vocabulary rather than
/// each inventing a layout. Everything here is achromatic: the spine carries
/// structure through weight and fill, never through a new colour.
library;

import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';

/// How a stop's node is drawn. The distinctions are informational, not
/// decorative: a terminus ends the line, an emphasised stop is one the rider
/// picked (board / alight / their own stop).
enum TimelineNodeKind { intermediate, terminus, emphasis }

/// Width of the spine gutter. Rows align their text against this, so it is the
/// one number both stop lists share.
const double kTimelineGutter = 32;

/// The spine cell for one row: the line running through it, plus this stop's
/// node. Purely decorative — the row's text carries the semantics.
class TimelineSpine extends StatelessWidget {
  const TimelineSpine({
    required this.kind,
    this.lineAbove = true,
    this.lineBelow = true,
    this.travelledAbove = false,
    this.travelledBelow = false,
    this.dimmed = false,
    super.key,
  });

  final TimelineNodeKind kind;

  /// False at the ends of the list, so the line stops at the first and last
  /// node instead of running off into the padding.
  final bool lineAbove;
  final bool lineBelow;

  /// Whether the vehicle has already covered the segment above / below this
  /// node. Covered track is solid ink, track still ahead is the outline tone —
  /// that contrast is the whole point of drawing the spine.
  final bool travelledAbove;
  final bool travelledBelow;

  /// A stop that is out of service or already passed for good; the node drops
  /// to the outline tone whatever its kind.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ahead = cs.outline;
    final done = cs.onSurface;

    // The two halves are Expanded rather than fractionally sized: the row's
    // height comes from its text, which is not known here, and a
    // FractionallySizedBox inside a Positioned would be asked to resolve a
    // fraction of an unbounded height.
    return ExcludeSemantics(
      child: SizedBox(
        width: kTimelineGutter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  Expanded(
                    child: _Segment(
                      color: lineAbove ? (travelledAbove ? done : ahead) : null,
                    ),
                  ),
                  Expanded(
                    child: _Segment(
                      color: lineBelow ? (travelledBelow ? done : ahead) : null,
                    ),
                  ),
                ],
              ),
            ),
            _Node(
              kind: kind,
              filled: travelledAbove && !dimmed,
              dimmed: dimmed,
            ),
          ],
        ),
      ),
    );
  }
}

/// One half of the spine line. A null [color] leaves the gap empty, which is
/// how the line stops at the first and last node.
class _Segment extends StatelessWidget {
  const _Segment({required this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (color == null) return const SizedBox.shrink();
    return Center(child: Container(width: 2, color: color));
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.kind, required this.filled, required this.dimmed});

  final TimelineNodeKind kind;
  final bool filled;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = dimmed ? cs.outline : cs.onSurface;

    return switch (kind) {
      // The terminus is a square: it reads as a stop-end rather than as one
      // more dot in the run, without needing a label to say so.
      TimelineNodeKind.terminus => Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      // A ring, not a fill: the rider's own stop should read as a marked
      // position on the line rather than as a heavier version of a passed one.
      TimelineNodeKind.emphasis => Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surface,
          border: Border.all(color: ink, width: 3),
        ),
      ),
      TimelineNodeKind.intermediate => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? ink : cs.surface,
          border: Border.all(color: filled ? ink : cs.outline, width: 2),
        ),
      ),
    };
  }
}

/// The "vehicle is here" divider, inserted between two stop rows.
///
/// It sits between rows rather than on one because that is what the data
/// supports: the schedule and the ETA sequence place the vehicle in a segment,
/// not at a stop. Claiming a precise point would be inventing precision.
class TimelineVehicleMarker extends StatelessWidget {
  const TimelineVehicleMarker({
    required this.semanticLabel,
    this.label,
    this.trailing,
    this.trailingIsAlert = false,
    this.badge,
    super.key,
  });

  /// What the marker means, for screen readers only — e.g. '公車在這' /
  /// '列車在此'. Always spoken, because the divider on its own says nothing
  /// out loud even when nothing is printed on it.
  final String semanticLabel;

  /// Optional text printed on the divider — the plate of the vehicle this
  /// marker stands for. Null prints nothing: the line and the arrow already
  /// say "a vehicle is in this segment", and naming a vehicle the feed did
  /// not identify would be inventing it.
  final String? label;

  /// Optional right-hand note — a delay, a plate. Null shows nothing.
  final String? trailing;

  /// Renders [trailing] in the delay tone. Off by default so a neutral note
  /// (a plate) does not read as a problem.
  final bool trailingIsAlert;

  /// A state glyph printed immediately after [label] — the seat mark on the
  /// vehicle a 下車提醒 is bound to. Bare ink, no fill: this reports what the
  /// session is following, it is not a control and not a selection, so it
  /// stays out of the ink budget the 目標站 row spends (docs/design.md:253).
  final IconData? badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      label: [semanticLabel, label, trailing].nonNulls.join('，'),
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(
            width: kTimelineGutter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Center(
                    child: Container(width: 2, color: cs.onSurface),
                  ),
                ),
                Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.onSurface,
                  ),
                  // Points down the list, the direction the vehicle is
                  // travelling in — the rows below it are the stops still
                  // ahead.
                  child: Icon(
                    Icons.arrow_downward_rounded,
                    size: 11,
                    color: cs.surface,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 6, 16, 6),
              child: Row(
                children: [
                  if (label != null) ...[
                    Text(
                      label!,
                      style: AppTextStyles.bodyVerySmall.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (badge != null) ...[
                    Icon(badge, size: 16, color: cs.onSurface),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Container(
                      height: 1,
                      color: cs.onSurface.withValues(alpha: 0.22),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      trailing!,
                      style: AppTextStyles.bodyVerySmall.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: trailingIsAlert
                            ? AppTheme.trainDelay
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small role tag beside a stop name — 上車 / 下車 / 你在這.
///
/// Solid ink is a committed state (the stop the rider picked); the outlined
/// variant is context the app inferred for them. Per the design system's Ink
/// Inversion Rule, at most one solid tag is ever on screen at a time.
class TimelineStopTag extends StatelessWidget {
  const TimelineStopTag(this.label, {this.solid = true, super.key});

  final String label;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: solid ? cs.onSurface : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
        border: solid ? null : Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodyVerySmall.copyWith(
          fontWeight: FontWeight.w700,
          color: solid ? cs.surface : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
