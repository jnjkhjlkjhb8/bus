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
import 'package:wheres_the_car/features/alerts/view/alert_source_chip.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/divider_line.dart';

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
    AppSnackbar.show(
      context,
      label,
      action: '復原',
      onAction: () => bloc.add(AlertRestored(messages)),
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
              const DividerLine(),
              if (state.error != null) const _StreamFailureStrip(),
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

class _NotificationRow extends StatefulWidget {
  const _NotificationRow({required this.alert, required this.unread});

  final AlertViewModel alert;
  final bool unread;

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  bool _expanded = false;

  void _toggle() {
    unawaited(HapticService.instance.lightTap());
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final alert = widget.alert;
    final unread = widget.unread;
    final isRed = alert.level == AlertSeverity.red;
    final dotColor = severityColor(alert.level, cs);

    // A red row is tinted end-to-end; the old colored left stripe is gone.
    final background = isRed
        ? Color.alphaBlend(cs.error.withValues(alpha: 0.05), cs.surface)
        : cs.surface;

    final titleText = alert.title ?? alert.message;
    // When there is a distinct title, [message] becomes the body; otherwise the
    // message already reads as the title and a body line would duplicate it.
    final bodyText = alert.title != null ? alert.message : null;
    final clampTarget = bodyText ?? titleText;

    final time = alert.time;
    final now = DateTime.now();

    return LayoutBuilder(
      builder: (context, constraints) {
        // The text column is narrower than the row: 20px padding each side
        // plus the trailing dot/chevron slot (12px gap + up to 18px icon).
        final textWidth = (constraints.maxWidth - 40 - 30).clamp(
          0.0,
          double.infinity,
        );
        final overflows = _overflows(
          context,
          clampTarget,
          bodyText != null ? _bodyStyle(cs) : _titleStyle(cs, unread),
          textWidth,
        );
        final canExpand = overflows || time != null;

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AlertSourceChip(source: alert.source),
                if (alert.source != null && isRed) const SizedBox(width: 8),
                if (isRed) _SeverityTag(cs: cs),
                const Spacer(),
                if (time != null)
                  Text(
                    alertRelativeTime(time, now),
                    style: AppTextStyles.memo.copyWith(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                      height: 1,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              titleText,
              maxLines: bodyText == null && !_expanded ? 2 : null,
              overflow: bodyText == null && !_expanded
                  ? TextOverflow.ellipsis
                  : TextOverflow.clip,
              style: _titleStyle(cs, unread),
            ),
            if (bodyText != null) ...[
              const SizedBox(height: 4),
              Text(
                bodyText,
                maxLines: _expanded ? null : 2,
                overflow: _expanded
                    ? TextOverflow.clip
                    : TextOverflow.ellipsis,
                style: _bodyStyle(cs),
              ),
            ],
            if (_expanded && time != null) ...[
              const SizedBox(height: 8),
              Text(
                _publishFooter(alert),
                style: AppTextStyles.memo.copyWith(
                  fontSize: 11.5,
                  color: cs.outline,
                  height: 1,
                ),
              ),
            ],
          ],
        );

        return Semantics(
          button: canExpand,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canExpand ? _toggle : null,
            child: AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppMotion.short,
              curve: AppMotion.easeOut,
              alignment: Alignment.topCenter,
              child: Container(
                color: background,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: content),
                    if (unread) ...[
                      const SizedBox(width: 12),
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ] else if (canExpand) ...[
                      const SizedBox(width: 12),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: cs.outline,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  TextStyle _titleStyle(ColorScheme cs, bool unread) =>
      AppTextStyles.bodyRegular.copyWith(
        fontSize: 15,
        color: cs.onSurface,
        fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
        height: 1.4,
      );

  TextStyle _bodyStyle(ColorScheme cs) => AppTextStyles.bodyRegular.copyWith(
    fontSize: 13.5,
    color: cs.onSurfaceVariant,
    height: 1.5,
  );

  /// 「發布 HH:mm」, plus the operator code when the source carries one.
  String _publishFooter(AlertViewModel alert) {
    final t = alert.time!;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final code = alert.source?.code ?? '';
    final suffix = code.isEmpty ? '' : ' · $code';
    return '發布 $hh:$mm$suffix';
  }

  /// Whether [text] in [style] would exceed two lines at [maxWidth].
  bool _overflows(
    BuildContext context,
    String text,
    TextStyle style,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 2,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }
}

/// Inline 「服務中斷」 tag next to the source chip on red rows.
class _SeverityTag extends StatelessWidget {
  const _SeverityTag({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Text(
        '服務中斷',
        style: TextStyle(
          fontFamily: 'IBMPlexSans',
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          height: 1,
          color: cs.error,
        ),
      ),
    );
  }
}

/// Shown under the header while an alert stream is reconnecting.
class _StreamFailureStrip extends StatelessWidget {
  const _StreamFailureStrip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final (background, ink) = dark
        ? (AppTheme.warningBgDark, AppTheme.warningInkDark)
        : (AppTheme.warningBg, AppTheme.warningInkLight);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '即時警報連線中斷，重新連線中⋯',
              style: AppTextStyles.bodySmall.copyWith(
                fontSize: 12.5,
                color: ink,
              ),
            ),
          ),
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
