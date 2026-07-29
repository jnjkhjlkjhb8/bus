import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';

/// Empty state card — shown when a list has no data.
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    required this.message,
    super.key,
    this.icon = Icons.inbox_rounded,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error state card — shown when a BLoC is in error state.
class ErrorStateCard extends StatelessWidget {
  const ErrorStateCard({
    required this.message,
    super.key,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.all(16),
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: cs.onErrorContainer,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: cs.onErrorContainer),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(AppI18n.of(context).commonRetryShort),
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One grey block standing in for a piece of content while it loads.
///
/// Sized by the caller to the text or control it replaces: a skeleton only
/// does its job while the loaded layout lands on the geometry the skeleton
/// drew, with no reflow at the moment the data arrives.
class SkeletonBone extends StatelessWidget {
  const SkeletonBone({
    required this.height,
    super.key,
    this.width,
    this.radius = AppTheme.radiusChip,
  });

  final double height;

  /// Null fills the surrounding constraint (inside an `Expanded` or a sized
  /// column slot).
  final double? width;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// The loading pulse, applied once around a whole skeleton.
///
/// One controller per group rather than one per bone: every bone breathes in
/// phase, which reads as a single surface waiting instead of a field of parts
/// blinking against each other.
class SkeletonFade extends StatefulWidget {
  const SkeletonFade({required this.child, super.key});

  final Widget child;

  @override
  State<SkeletonFade> createState() => _SkeletonFadeState();
}

class _SkeletonFadeState extends State<SkeletonFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AppMotion.shimmerLoop);
    _opacity = Tween<double>(
      begin: 0.3,
      end: 0.7,
    ).animate(CurvedAnimation(parent: _ctrl, curve: AppMotion.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations && _ctrl.isAnimating) {
      _ctrl.stop();
    } else if (!disableAnimations && !_ctrl.isAnimating) {
      unawaited(_ctrl.repeat(reverse: true));
    }
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, child) => Opacity(
        opacity: disableAnimations ? 0.5 : _opacity.value,
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Loading shimmer placeholder for a single card row.
class ShimmerRow extends StatelessWidget {
  const ShimmerRow({super.key, this.height = 48});
  final double height;

  @override
  Widget build(BuildContext context) => SkeletonFade(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SkeletonBone(height: height, radius: AppTheme.radiusCard),
    ),
  );
}
