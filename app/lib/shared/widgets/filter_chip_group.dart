import 'package:flutter/material.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

class FilterChipGroup<T> extends StatelessWidget {
  const FilterChipGroup({
    required this.options,
    required this.selected,
    required this.onToggle,
    super.key,
  });

  final Map<T, String> options;
  final Set<T> selected;
  final ValueChanged<T> onToggle;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          for (final entry in options.entries)
            _Chip(
              label: entry.value,
              selected: selected.contains(entry.key),
              onTap: () => onToggle(entry.key),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Pressable(
      onTap: onTap,
      semanticLabel: selected ? '$label，已選取' : label,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : AppMotion.short,
        curve: AppMotion.easeOut,
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        // Selection reads from a hairline accent border and a check, not a
        // filled accent block: these groups default to everything selected,
        // and a row of solid accent would outweigh the screen's primary action.
        decoration: BoxDecoration(
          color: selected ? cs.surfaceContainerHighest : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The check keeps its slot when unselected so toggling a chip
            // never reflows the row around it.
            Opacity(
              opacity: selected ? 1 : 0,
              child: Icon(Icons.check_rounded, size: 14, color: cs.onSurface),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
