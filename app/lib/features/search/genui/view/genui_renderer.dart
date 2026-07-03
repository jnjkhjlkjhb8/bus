import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/search/genui/model/genui_node.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

class GenUiRenderer extends StatelessWidget {
  const GenUiRenderer({required this.nodes, required this.onChip, super.key});

  final List<GenUiNode> nodes;
  final ValueChanged<String> onChip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final node in nodes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _node(context, node),
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
            letterSpacing: 0.04,
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
        return _RouteCard(node: node);
      case GenUiStep():
        return _StepRow(node: node);
      case GenUiChip():
        return Pressable(
          onTap: () => onChip(node.query),
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
                  Icons.search_rounded,
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
  const _RouteCard({required this.node});
  final GenUiRoute node;

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
          Text(
            node.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
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
