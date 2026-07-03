import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_state.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';

Color severityColor(AlertSeverity level, ColorScheme cs) =>
    level == AlertSeverity.red ? cs.error : AppTheme.etaApproaching;

Future<void> showNotificationSheet(BuildContext context) async {
  unawaited(HapticService.instance.lightTap());
  final bloc = context.read<AlertBloc>();
  final unreadAtOpen = bloc.state.unreadAlerts.map((a) => a.message).toSet();
  bloc.add(const AlertAllRead());
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider.value(
      value: bloc,
      child: _NotificationSheet(unreadAtOpen: unreadAtOpen),
    ),
  );
}

class _NotificationSheet extends StatelessWidget {
  const _NotificationSheet({required this.unreadAtOpen});

  final Set<String> unreadAtOpen;

  void _dismiss(BuildContext context, AlertViewModel alert) {
    unawaited(HapticService.instance.lightTap());
    context.read<AlertBloc>().add(AlertDismissed(alert.message));
    _showUndo(context, [alert.message], '已清除通知');
  }

  void _clearAll(BuildContext context, List<AlertViewModel> alerts) {
    unawaited(HapticService.instance.lightTap());
    final messages = alerts.map((a) => a.message).toList();
    context.read<AlertBloc>().add(AlertAllDismissed(messages));
    _showUndo(context, messages, '已清除 ${messages.length} 則通知');
  }

  void _showUndo(BuildContext context, List<String> messages, String label) {
    final bloc = context.read<AlertBloc>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label),
        action: SnackBarAction(
          label: '復原',
          onPressed: () => bloc.add(AlertRestored(messages)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    return Container(
      height: media.size.height * 0.72,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusBottomSheet),
        ),
      ),
      child: BlocBuilder<AlertBloc, AlertState>(
        builder: (context, state) {
          final alerts = state.visibleAlerts.reversed.toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetDragHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    Text(
                      '通知',
                      style: AppTextStyles.heading2.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    if (alerts.isNotEmpty)
                      Pressable(
                        onTap: () => _clearAll(context, alerts),
                        semanticLabel: '清除全部通知',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            '清除全部',
                            style: AppTextStyles.bodyRegular.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(
                child: alerts.isEmpty
                    ? const _NotificationEmpty()
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: alerts.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          indent: 20,
                          endIndent: 20,
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                        itemBuilder: (context, i) {
                          final alert = alerts[i];
                          return Dismissible(
                            key: ValueKey(alert.message),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) => _dismiss(context, alert),
                            background: _DismissBackground(),
                            child: _NotificationRow(
                              alert: alert,
                              unread: unreadAtOpen.contains(alert.message),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.alert, required this.unread});

  final AlertViewModel alert;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = severityColor(alert.level, cs);
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 36,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              alert.message,
              style: AppTextStyles.bodyRegular.copyWith(
                color: cs.onSurface,
                fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                height: 1.4,
              ),
            ),
          ),
          if (unread) ...[
            const SizedBox(width: 12),
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );
  }
}

class _DismissBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      child: Icon(
        Icons.delete_outline_rounded,
        size: 22,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}

class UnreadBadge extends StatelessWidget {
  const UnreadBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: cs.error,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: cs.surface, width: 2),
      ),
      child: Center(
        child: Text(
          count > 9 ? '9+' : '$count',
          style: AppTextStyles.bodyVerySmall.copyWith(
            color: cs.onError,
            fontWeight: FontWeight.bold,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _NotificationEmpty extends StatelessWidget {
  const _NotificationEmpty();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 44,
            color: cs.outline,
          ),
          const SizedBox(height: 14),
          Text(
            '目前沒有通知',
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '路線或班次有異常時會通知你',
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
