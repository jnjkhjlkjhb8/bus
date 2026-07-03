import 'package:flutter/material.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

class AppSlidingSegment<T> extends StatelessWidget {
  const AppSlidingSegment({
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  }) : assert(options.length == 2, 'Exactly two options are required.');

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final keys = options.keys.toList();
    final selectedIndex = keys.indexOf(value);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pillWidth = (constraints.maxWidth - 8) / 2;
          return SizedBox(
            height: 36,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: reduceMotion ? Duration.zero : AppMotion.medium,
                  curve: AppMotion.easeOut,
                  left: selectedIndex == 0 ? 0 : pillWidth + 4,
                  top: 0,
                  bottom: 0,
                  width: pillWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withValues(alpha: .04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: options.entries.map((entry) {
                    final selected = entry.key == value;
                    return Expanded(
                      child: Semantics(
                        button: true,
                        selected: selected,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onChanged(entry.key),
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : AppMotion.medium,
                              curve: AppMotion.easeOut,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                              ),
                              child: Text(entry.value),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
