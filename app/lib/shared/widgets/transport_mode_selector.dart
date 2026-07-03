import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

enum SelectorStyle { multiSelect, slidingBlock }

class TransportModeSelector extends StatelessWidget {
  const TransportModeSelector({
    required this.options,
    required this.style,
    this.selectedIndices = const {},
    this.onMultiChanged,
    this.selectedIndex = 0,
    this.onSingleChanged,
    super.key,
  });

  final List<String> options;
  final SelectorStyle style;
  final Set<int> selectedIndices;
  final ValueChanged<Set<int>>? onMultiChanged;
  final int selectedIndex;
  final ValueChanged<int>? onSingleChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.all(8),
      child: style == SelectorStyle.multiSelect
          ? _MultiSelectRow(
              options: options,
              selectedIndices: selectedIndices,
              onChanged: onMultiChanged,
            )
          : _SlidingBlockRow(
              options: options,
              selectedIndex: selectedIndex,
              onChanged: onSingleChanged,
            ),
    );
  }
}

class _MultiSelectRow extends StatelessWidget {
  const _MultiSelectRow({
    required this.options,
    required this.selectedIndices,
    this.onChanged,
  });

  final List<String> options;
  final Set<int> selectedIndices;
  final ValueChanged<Set<int>>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(options.length, (i) {
        final selected = selectedIndices.contains(i);
        return Expanded(
          child: GestureDetector(
            onTap: () {
              final next = Set<int>.from(selectedIndices);
              if (selected) {
                next.remove(i);
              } else {
                next.add(i);
              }
              onChanged?.call(next);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? cs.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusChip),
              ),
              alignment: Alignment.center,
              child: Text(
                options[i],
                style: AppTextStyles.bodyRegular.copyWith(
                  color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _SlidingBlockRow extends StatelessWidget {
  const _SlidingBlockRow({
    required this.options,
    required this.selectedIndex,
    this.onChanged,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / options.length;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              left: selectedIndex * itemWidth,
              top: 0,
              bottom: 0,
              width: itemWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusChip),
                ),
              ),
            ),
            Row(
              children: List.generate(options.length, (i) {
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged?.call(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        options[i],
                        style: AppTextStyles.bodyRegular.copyWith(
                          color: i == selectedIndex
                              ? cs.onPrimary
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        );
      },
    );
  }
}
