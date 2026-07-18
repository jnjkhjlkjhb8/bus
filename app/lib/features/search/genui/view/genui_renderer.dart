import 'package:flutter/material.dart';
import 'package:wheres_the_car/data/models/search_models.dart';
import 'package:wheres_the_car/features/search/genui/model/genui_node.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

class GenUiRenderer extends StatelessWidget {
  const GenUiRenderer({
    required this.nodes,
    required this.refs,
    required this.onChip,
    required this.onOpen,
    super.key,
  });

  final List<GenUiNode> nodes;
  final Map<String, SearchResult> refs;
  final ValueChanged<String> onChip;
  final ValueChanged<SearchResult> onOpen;

  SearchResult? _refOf(String? refUid) =>
      refUid == null ? null : refs[refUid];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, node) in nodes.indexed)
          _StaggerIn(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _node(context, node),
            ),
          ),
      ],
    );
  }

  Widget _node(BuildContext context, GenUiNode node) {
    final cs = Theme.of(context).colorScheme;
    switch (node) {
      case GenUiHeading():
        return Text(
          node.text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        );
      case GenUiText():
        return Text(
          node.text,
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: cs.onSurface,
          ),
        );
      case GenUiRoute():
        final ref = _refOf(node.refUid);
        final card = _RouteCard(node: node, openable: ref != null);
        if (ref == null) return card;
        return Pressable(
          onTap: () => onOpen(ref),
          semanticLabel: node.title,
          child: card,
        );
      case GenUiStep():
        return _StepRow(node: node);
      case GenUiChip():
        final ref = _refOf(node.refUid);
        return Pressable(
          onTap: () => ref != null ? onOpen(ref) : onChip(node.query),
          semanticLabel: node.label,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ref != null
                      ? Icons.arrow_outward_rounded
                      : Icons.search_rounded,
                  size: 15,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  node.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      case GenUiDivider():
        return Divider(height: 1, thickness: 0.5, color: cs.outlineVariant);
    }
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.node, required this.openable});
  final GenUiRoute node;
  final bool openable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.brightness == Brightness.light
            ? Colors.white
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  node.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (openable)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
            ],
          ),
          if (node.badges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final badge in node.badges)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (node.etaText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              node.etaText,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.node});
  final GenUiStep node;

  IconData get _icon => switch (node.kind) {
    GenUiStepKind.board => Icons.login_rounded,
    GenUiStepKind.ride => Icons.directions_transit_rounded,
    GenUiStepKind.walk => Icons.directions_walk_rounded,
    GenUiStepKind.alight => Icons.logout_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(_icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            node.text,
            style: TextStyle(fontSize: 14, height: 1.35, color: cs.onSurface),
          ),
        ),
      ],
    );
  }
}

class _StaggerIn extends StatelessWidget {
  const _StaggerIn({required this.index, required this.child});
  final int index;
  final Widget child;

  static const _step = Duration(milliseconds: 30);

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    final delay = _step * index;
    final total = AppMotion.medium + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: AppMotion.easeOut),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 4 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}
