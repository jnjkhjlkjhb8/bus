import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

enum AlertLevel { red, yellow }

/// Alert card for service disruptions.
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    // Yellow relies on the shared warning tokens: the app's ColorScheme never
    // defines a tertiary swatch, so `cs.tertiaryContainer` falls back to grey
    // and the severity distinction is lost.
    final Color bgColor;
    final Color fgColor;
    if (level == AlertLevel.red) {
      bgColor = cs.errorContainer;
      fgColor = cs.onErrorContainer;
    } else if (dark) {
      bgColor = AppTheme.warningBgDark;
      fgColor = AppTheme.warningInkDark;
    } else {
      bgColor = AppTheme.warningBg;
      fgColor = AppTheme.warningInkLight;
    }
    final icon = level == AlertLevel.red
        ? Icons.warning_rounded
        : Icons.info_rounded;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
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
                tooltip: '展開',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            if (onDismiss != null)
              IconButton(
                icon: Icon(Icons.close_rounded, color: fgColor),
                onPressed: onDismiss,
                tooltip: '關閉',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
      duration: AppMotion.sheet,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: AppMotion.easeOut));
    if (widget.visible) unawaited(_ctrl.forward());
  }

  @override
  void didUpdateWidget(covariant AnimatedAlertBanner old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      if (AppMotion.reduced(context)) {
        _ctrl.value = widget.visible ? 1 : 0;
      } else {
        unawaited(widget.visible ? _ctrl.forward() : _ctrl.reverse());
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) {
      return widget.visible ? widget.child : const SizedBox.shrink();
    }
    return SlideTransition(position: _slide, child: widget.child);
  }
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
        // Sine-eased breathing instead of a hard on/off cut, which read as a
        // strobe. Reduce-motion keeps the static fully-opaque fallback.
        opacity: disableAnimations
            ? 1.0
            : 0.4 + 0.6 * (0.5 + 0.5 * math.sin(2 * math.pi * _ctrl.value)),
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
