import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_state.dart';

/// Compact full-width strip shown below map close buttons.
class MapAlertStrip extends StatelessWidget {
  const MapAlertStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AlertBloc, AlertState>(
      buildWhen: (prev, curr) =>
          prev.visibleAlerts.length != curr.visibleAlerts.length,
      builder: (context, state) {
        final alert = state.visibleAlerts.firstOrNull;
        if (alert == null) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: const BoxDecoration(
            color: AppTheme.warningBg,
            border: Border.symmetric(
              horizontal: BorderSide(color: AppTheme.warningBorder, width: 0.5),
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
            ],
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
      buildWhen: (prev, curr) => prev.redAlerts.length != curr.redAlerts.length,
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
          prev.visibleAlerts.length != curr.visibleAlerts.length,
      builder: (context, state) {
        final alerts = state.visibleAlerts;
        if (alerts.isEmpty) return const SizedBox.shrink();
        return _AlertCard(alert: alerts.first, isHome: false);
      },
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.isHome});

  final AlertViewModel alert;
  final bool isHome;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRed = alert.level == AlertSeverity.red;
    final bgColor = isRed ? cs.errorContainer : cs.tertiaryContainer;
    final fgColor = isRed ? cs.onErrorContainer : cs.onTertiaryContainer;

    return Dismissible(
      key: ValueKey(alert.message),
      direction: DismissDirection.up,
      onDismissed: (_) =>
          context.read<AlertBloc>().add(AlertDismissed(alert.message)),
      child: AnimatedSlide(
        offset: Offset.zero,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          child: Row(
            children: [
              _AlertDot(isRed: isRed, color: fgColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  alert.message,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: fgColor,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 16, color: fgColor),
                onPressed: () => context.read<AlertBloc>().add(
                  AlertDismissed(alert.message),
                ),
                tooltip: '關閉',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertDot extends StatefulWidget {
  const _AlertDot({required this.isRed, required this.color});
  final bool isRed;
  final Color color;

  @override
  State<_AlertDot> createState() => _AlertDotState();
}

class _AlertDotState extends State<_AlertDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isRed) {
      _opacity = Tween<double>(begin: 0.4, end: 1).animate(_pulse);
    } else {
      _opacity = const AlwaysStoppedAnimation(1);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.isRed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _pulse.stop();
      } else {
        unawaited(_pulse.repeat(reverse: true));
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
