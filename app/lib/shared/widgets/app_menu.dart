import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';

class AppMenuItem {
  const AppMenuItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.isDestructive = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool isDestructive;
}

class AppMenuButton extends StatefulWidget {
  const AppMenuButton({
    required this.items,
    super.key,
    this.child,
    this.tooltip,
  });

  final List<AppMenuItem> items;
  final Widget? child;

  /// Accessible label / tooltip for the trigger. Defaults to AppI18n.of(context).commonMoreOptions.
  final String? tooltip;

  @override
  State<AppMenuButton> createState() => _AppMenuButtonState();
}

class _AppMenuButtonState extends State<AppMenuButton> {
  final _menuKey = GlobalKey<PopupMenuButtonState<int>>();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tooltip = widget.tooltip ?? AppI18n.of(context).commonMoreOptions;
    return Pressable(
      onTap: () => _menuKey.currentState?.showButtonMenu(),
      semanticLabel: tooltip,
      child: Tooltip(
        message: tooltip,
        child: PopupMenuButton<int>(
          key: _menuKey,
          // Own gesture handling is disabled so Pressable is the single
          // source of press feedback; showButtonMenu() is invoked directly.
          enabled: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            side: BorderSide(color: cs.outline, width: 0.5),
          ),
          color: cs.surfaceContainerHigh,
          elevation: 4,
          onSelected: (i) => widget.items[i].onTap(),
          itemBuilder: (_) => widget.items.asMap().entries.map((e) {
            final item = e.value;
            return PopupMenuItem<int>(
              value: e.key,
              height: 44,
              child: Row(
                children: [
                  if (item.icon != null) ...[
                    Icon(
                      item.icon,
                      size: 20,
                      color: item.isDestructive ? cs.error : cs.onSurface,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    item.label,
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: item.isDestructive ? cs.error : cs.onSurface,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          child:
              widget.child ??
              Icon(Icons.more_vert_rounded, color: cs.onSurface),
        ),
      ),
    );
  }
}
