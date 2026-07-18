import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_state.dart';
import 'package:wheres_the_car/features/alerts/view/alert_source_chip.dart';
import 'package:wheres_the_car/features/alerts/view/notification_sheet.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

/// Compact full-width strip shown below map close buttons.
class MapAlertStrip extends StatelessWidget {
  const MapAlertStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AlertBloc, AlertState>(
      buildWhen: (prev, curr) =>
          prev.visibleAlerts.firstOrNull?.message !=
              curr.visibleAlerts.firstOrNull?.message ||
          prev.visibleAlerts.length != curr.visibleAlerts.length,
      builder: (context, state) {
        final alerts = state.visibleAlerts;
        final alert = alerts.firstOrNull;
        if (alert == null) return const SizedBox.shrink();
        final extra = alerts.length - 1;
        final label = extra > 0
            ? '${alert.message}，還有 $extra 則通知'
            : alert.message;
        return Pressable(
          onTap: () => unawaited(showNotificationSheet(context)),
          semanticLabel: label,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const BoxDecoration(
              color: AppTheme.warningBg,
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: AppTheme.warningBorder,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              spacing: 4,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: AppTheme.warningBorder,
                ),
                Expanded(
                  child: Text(
                    alert.message,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppTheme.warningBorder,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (extra > 0)
                  Text(
                    '+$extra',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppTheme.warningBorder,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shown at top of home screen for red (severe) alerts only.
class HomeAlertBanner extends StatelessWidget {
  const HomeAlertBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AlertBloc, AlertState>(
      buildWhen: (prev, curr) =>
          prev.redAlerts.firstOrNull?.message !=
              curr.redAlerts.firstOrNull?.message ||
          prev.redAlerts.length != curr.redAlerts.length,
      builder: (context, state) {
        final alerts = state.redAlerts;
        if (alerts.isEmpty) return const SizedBox.shrink();
        return _AlertCard(alert: alerts.first, isHome: true);
      },
    );
  }
}

/// Shown in transit pages for yellow+ alerts.
class TransitAlertBanner extends StatelessWidget {
  const TransitAlertBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AlertBloc, AlertState>(
      buildWhen: (prev, curr) =>
          prev.visibleAlerts.firstOrNull?.message !=
              curr.visibleAlerts.firstOrNull?.message ||
          prev.visibleAlerts.length != curr.visibleAlerts.length,
      builder: (context, state) {
        final alerts = state.visibleAlerts;
        if (alerts.isEmpty) return const SizedBox.shrink();
        return _AlertCard(alert: alerts.first, isHome: false);
      },
    );
  }
}

class _AlertCard extends StatefulWidget {
  const _AlertCard({required this.alert, required this.isHome});

  final AlertViewModel alert;
  final bool isHome;

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AppMotion.sheet);
    final curved = CurvedAnimation(parent: _ctrl, curve: AppMotion.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(curved);
    _fade = curved;
    if (AppMotion.reduced(context)) {
      _ctrl.value = 1;
    } else {
      unawaited(_ctrl.forward());
    }
  }

  @override
  void didUpdateWidget(covariant _AlertCard old) {
    super.didUpdateWidget(old);
    // A new alert replacing the current one plays the same slide-down+fade
    // entrance the first alert gets, mirroring the swipe-up dismiss.
    if (widget.alert.message != old.alert.message) {
      if (AppMotion.reduced(context)) {
        _ctrl.value = 1;
      } else {
        unawaited(_ctrl.forward(from: 0));
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
    final alert = widget.alert;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final isRed = alert.level == AlertSeverity.red;

    // Severity carries through the container color and the source chip; the
    // former pulsing dot is gone. Yellow uses the shared warning tokens so it
    // reads as an ops notice, not a themed accent.
    final Color bgColor;
    final Color fgColor;
    if (isRed) {
      bgColor = cs.errorContainer;
      fgColor = cs.onErrorContainer;
    } else if (dark) {
      bgColor = AppTheme.warningBgDark;
      fgColor = AppTheme.warningInkDark;
    } else {
      bgColor = AppTheme.warningBg;
      fgColor = AppTheme.warningInkLight;
    }

    final time = alert.time;
    final sub = time != null
        ? '${alertRelativeTime(time, DateTime.now())} · 點擊看詳情'
        : '點擊看詳情';

    return Dismissible(
      key: ValueKey(alert.message),
      direction: DismissDirection.up,
      onDismissed: (_) =>
          context.read<AlertBloc>().add(AlertDismissed(alert.message)),
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Pressable(
            onTap: () => unawaited(showNotificationSheet(context)),
            semanticLabel: alert.title ?? alert.message,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: AlertSourceChip(source: alert.source),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.title ?? alert.message,
                          style: AppTextStyles.bodyRegular.copyWith(
                            fontSize: 13.5,
                            color: fgColor,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          style: AppTextStyles.memo.copyWith(
                            fontSize: 11,
                            color: fgColor.withValues(alpha: 0.8),
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 16, color: fgColor),
                    onPressed: () => context.read<AlertBloc>().add(
                      AlertDismissed(alert.message),
                    ),
                    tooltip: '關閉',
                    padding: EdgeInsets.zero,
                    // 16px glyph, but the hit target keeps the 44px floor.
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
