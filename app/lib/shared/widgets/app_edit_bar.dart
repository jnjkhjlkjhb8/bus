import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

enum AppEditAction { bold, italic, underline, link, bulletList, quote }

extension _AppEditActionExt on AppEditAction {
  IconData get icon => switch (this) {
    AppEditAction.bold => Icons.format_bold_rounded,
    AppEditAction.italic => Icons.format_italic_rounded,
    AppEditAction.underline => Icons.format_underlined_rounded,
    AppEditAction.link => Icons.link_rounded,
    AppEditAction.bulletList => Icons.format_list_bulleted_rounded,
    AppEditAction.quote => Icons.format_quote_rounded,
  };
}

class AppEditBar extends StatelessWidget {
  const AppEditBar({
    required this.activeActions,
    required this.onToggle,
    super.key,
  });

  final Set<AppEditAction> activeActions;
  final ValueChanged<AppEditAction> onToggle;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: AppEditAction.values.map((action) {
          final active = activeActions.contains(action);
          return _EditBarBtn(
            icon: action.icon,
            active: active,
            onTap: () => onToggle(action),
          );
        }).toList(),
      ),
    );
  }
}

class _EditBarBtn extends StatefulWidget {
  const _EditBarBtn({
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_EditBarBtn> createState() => _EditBarBtnState();
}

class _EditBarBtnState extends State<_EditBarBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? AppMotion.pressedScale : 1.0,
        duration: AppMotion.press,
        curve: AppMotion.easeOut,
        child: AnimatedContainer(
          duration: AppMotion.short,
          curve: AppMotion.easeOut,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: widget.active ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          ),
          child: Icon(
            widget.icon,
            size: 20,
            color: widget.active ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
