import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';

class AppChatBubble extends StatefulWidget {
  const AppChatBubble({
    required this.text,
    required this.isSent,
    super.key,
    this.time,
    this.isLastInGroup = true,
  });

  final String text;
  final bool isSent;
  final String? time;
  final bool isLastInGroup;

  @override
  State<AppChatBubble> createState() => _AppChatBubbleState();
}

class _AppChatBubbleState extends State<AppChatBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.short,
    );
    _fade = CurvedAnimation(parent: _controller, curve: AppMotion.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: AppMotion.easeOut));
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
    } else {
      unawaited(_controller.forward());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = widget.isSent ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = widget.isSent ? cs.onPrimaryContainer : cs.onSurface;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: EdgeInsets.only(
            left: widget.isSent ? 64 : 0,
            right: widget.isSent ? 0 : 64,
            bottom: widget.isLastInGroup ? 8 : 2,
          ),
          child: Align(
            alignment: widget.isSent
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppTheme.radiusCard),
                  topRight: const Radius.circular(AppTheme.radiusCard),
                  bottomLeft: Radius.circular(
                    widget.isSent || !widget.isLastInGroup
                        ? AppTheme.radiusCard
                        : 4,
                  ),
                  bottomRight: Radius.circular(
                    !widget.isSent || !widget.isLastInGroup
                        ? AppTheme.radiusCard
                        : 4,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: widget.isSent
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.text,
                    style: AppTextStyles.bodyRegular.copyWith(color: fg),
                  ),
                  if (widget.time != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.time!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: fg.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
