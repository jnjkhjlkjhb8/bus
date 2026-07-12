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

    // A recessed groove holding a raised, lighter thumb. The track is a
    // translucent black overlay, not an opaque surface token, so it darkens
    // whatever hosts the control — scaffold or bottom sheet alike. An opaque
    // track keyed to a fixed surface collides with the sheet colour in dark
    // mode (surfaceContainerLow == the sheet), which erases the track entirely.
    final isDark = cs.brightness == Brightness.dark;
    final trackColor = Colors.black.withValues(alpha: isDark ? 0.30 : 0.05);
    final thumbColor = isDark
        ? cs.surfaceContainerHighest
        : cs.surfaceContainerLow;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: trackColor,
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
                      color: thumbColor,
                      borderRadius: BorderRadius.circular(7),
                      // Light: a hairline defines the white thumb when it sits
                      // on an equally white sheet. Dark needs no edge — the
                      // lighter thumb already separates from the groove.
                      border: isDark
                          ? null
                          : Border.all(
                              color: Colors.black.withValues(alpha: .04),
                              width: .5,
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? .25 : .05,
                          ),
                          blurRadius: isDark ? 2 : 4,
                          offset: Offset(0, isDark ? 1 : 2),
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
