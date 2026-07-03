import 'package:flutter/material.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

/// Plays a tiny fade-and-rise entrance animation for list content.
class AnimatedListItem extends StatelessWidget {
  const AnimatedListItem({
    required this.child,
    super.key,
    this.index = 0,
    this.enabled = true,
  });

  final Widget child;

  /// The item's position, used for a subtle stagger.
  final int index;

  /// Whether the entrance animation should run.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(
        milliseconds: AppMotion.short.inMilliseconds + index * 20,
      ),
      curve: AppMotion.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 8),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
