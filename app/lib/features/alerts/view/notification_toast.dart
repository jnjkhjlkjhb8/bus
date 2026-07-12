import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wheres_the_car/app/router/app_router.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_state.dart';
import 'package:wheres_the_car/features/alerts/view/alert_source_chip.dart';
import 'package:wheres_the_car/features/alerts/view/notification_sheet.dart';

class NotificationToastHost extends StatefulWidget {
  const NotificationToastHost({required this.child, super.key});

  final Widget child;

  @override
  State<NotificationToastHost> createState() => _NotificationToastHostState();
}

class _NotificationToastHostState extends State<NotificationToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  AlertViewModel? _current;
  final Set<String> _shown = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      reverseDuration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _present(AlertViewModel alert) {
    _timer?.cancel();
    setState(() => _current = alert);
    unawaited(_controller.forward(from: 0));
    _timer = Timer(const Duration(seconds: 5), _hide);
  }

  Future<void> _hide() async {
    _timer?.cancel();
    if (!mounted || _current == null) return;
    await _controller.reverse();
    if (!mounted) return;
    setState(() => _current = null);
  }

  void _openInbox() {
    final ctx = AppRouter.rootNavigatorKey.currentContext;
    unawaited(_hide());
    if (ctx != null) unawaited(showNotificationSheet(ctx));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AlertBloc, AlertState>(
      listenWhen: (_, c) => c.redAlerts.any((a) => !_shown.contains(a.message)),
      listener: (context, state) {
        final fresh = state.redAlerts
            .where((a) => !_shown.contains(a.message))
            .toList();
        if (fresh.isEmpty) return;
        final latest = fresh.last;
        _shown.add(latest.message);
        _present(latest);
      },
      child: Stack(
        children: [
          widget.child,
          if (_current != null)
            _ToastLayer(
              controller: _controller,
              alert: _current!,
              onTap: _openInbox,
              onDismiss: _hide,
            ),
        ],
      ),
    );
  }
}

class _ToastLayer extends StatelessWidget {
  const _ToastLayer({
    required this.controller,
    required this.alert,
    required this.onTap,
    required this.onDismiss,
  });

  final AnimationController controller;
  final AlertViewModel alert;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Scoped aspects so keyboard/inset changes don't rebuild the toast.
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(controller.value);
          return Opacity(
            opacity: reduce ? (controller.value > 0 ? 1 : 0) : t,
            child: Transform.translate(
              offset: reduce ? Offset.zero : Offset(0, (1 - t) * -16),
              child: Transform.scale(
                scale: reduce ? 1 : 0.94 + 0.06 * t,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          );
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: GestureDetector(
              onTap: onTap,
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < 0) onDismiss();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: cs.brightness == Brightness.light
                      ? Colors.white
                      : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  boxShadow: AppShadows.floating,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: AlertSourceChip(source: alert.source),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alert.title ?? alert.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyRegular.copyWith(
                              fontSize: 13.5,
                              color: cs.onSurface,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '剛剛 · 服務中斷',
                            style: AppTextStyles.memo.copyWith(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: cs.outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
