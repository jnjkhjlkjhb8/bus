import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';

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

class _EditBarBtn extends StatelessWidget {
  const _EditBarBtn({
    required this.icon,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.short,
        curve: AppMotion.easeOut,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
        child: Icon(
          icon,
          size: 20,
          color: active ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
