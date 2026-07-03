import 'dart:async';

import 'package:flutter/material.dart';

enum AlertLevel { red, yellow }

/// Dismissible alert card for service disruptions.
/// Red (severe) / Yellow (minor delay) — no gradients, M3 container colours.
class AlertCard extends StatelessWidget {
  const AlertCard({
    required this.level,
    required this.system,
    required this.message,
    super.key,
    this.onDismiss,
    this.onExpand,
  });

  final AlertLevel level;
  final String system;
  final String message;
  final VoidCallback? onDismiss;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = level == AlertLevel.red
        ? cs.errorContainer
        : cs.tertiaryContainer;
    final fgColor = level == AlertLevel.red
        ? cs.onErrorContainer
        : cs.onTertiaryContainer;
    final icon = level == AlertLevel.red
        ? Icons.warning_rounded
        : Icons.info_rounded;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: fgColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    system,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: fgColor,
                    ),
                  ),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: fgColor),
                  ),
                ],
              ),
            ),
            if (onExpand != null)
              IconButton(
                icon: Icon(Icons.expand_more_rounded, color: fgColor),
                onPressed: onExpand,
                visualDensity: VisualDensity.compact,
              ),
            if (onDismiss != null)
              IconButton(
                icon: Icon(Icons.close_rounded, color: fgColor),
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

/// Slide-down animated wrapper.
class AnimatedAlertBanner extends StatefulWidget {
  const AnimatedAlertBanner({
    required this.child,
    required this.visible,
    super.key,
  });
  final Widget child;
  final bool visible;

  @override
  State<AnimatedAlertBanner> createState() => _AnimatedAlertBannerState();
}

class _AnimatedAlertBannerState extends State<AnimatedAlertBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    if (widget.visible) unawaited(_ctrl.forward());
  }

  @override
  void didUpdateWidget(covariant AnimatedAlertBanner old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      unawaited(widget.visible ? _ctrl.forward() : _ctrl.reverse());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SlideTransition(position: _slide, child: widget.child);
}

/// Red dot that pulses for active severe alerts.
class PulsingAlertDot extends StatefulWidget {
  const PulsingAlertDot({super.key, this.size = 8});
  final double size;

  @override
  State<PulsingAlertDot> createState() => _PulsingAlertDotState();
}

class _PulsingAlertDotState extends State<PulsingAlertDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
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
      unawaited(_ctrl.repeat());
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Opacity(
        opacity: disableAnimations ? 1.0 : (_ctrl.value < 0.5 ? 1.0 : 0.0),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    );
  }
}
