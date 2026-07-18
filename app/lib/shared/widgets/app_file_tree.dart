import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

class AppFileNode {
  const AppFileNode({
    required this.name,
    this.isFolder = false,
    this.children = const [],
  });

  final String name;
  final bool isFolder;
  final List<AppFileNode> children;
}

class AppFileTree extends StatefulWidget {
  const AppFileTree({required this.roots, super.key});

  final List<AppFileNode> roots;

  @override
  State<AppFileTree> createState() => _AppFileTreeState();
}

class _AppFileTreeState extends State<AppFileTree> {
  final Set<AppFileNode> _expanded = {};

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildNodes(widget.roots, 0),
    );
  }

  List<Widget> _buildNodes(List<AppFileNode> nodes, int depth) {
    final result = <Widget>[];
    for (final node in nodes) {
      result.add(
        _FileNodeTile(
          node: node,
          depth: depth,
          isExpanded: _expanded.contains(node),
          onTap: node.isFolder
              ? () => setState(() {
                  if (_expanded.contains(node)) {
                    _expanded.remove(node);
                  } else {
                    _expanded.add(node);
                  }
                })
              : null,
        ),
      );
      if (node.isFolder &&
          _expanded.contains(node) &&
          node.children.isNotEmpty) {
        result.addAll(_buildNodes(node.children, depth + 1));
      }
    }
    return result;
  }
}

class _FileNodeTile extends StatelessWidget {
  const _FileNodeTile({
    required this.node,
    required this.depth,
    required this.isExpanded,
    this.onTap,
  });

  final AppFileNode node;
  final int depth;
  final bool isExpanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = AppMotion.reduced(context);

    final icon = node.isFolder
        ? (isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded)
        : Icons.insert_drive_file_rounded;
    final iconColor = node.isFolder ? cs.primary : cs.onSurfaceVariant;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4),
        child: Row(
          children: [
            if (node.isFolder)
              AnimatedRotation(
                turns: isExpanded ? 0.25 : 0,
                duration: reduceMotion ? Duration.zero : AppMotion.micro,
                curve: AppMotion.easeOut,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              )
            else
              const SizedBox(width: 16),
            const SizedBox(width: 4),
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.name,
                style: AppTextStyles.bodyRegular.copyWith(color: cs.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
