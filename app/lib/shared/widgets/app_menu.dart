import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

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

class AppMenuButton extends StatelessWidget {
  const AppMenuButton({required this.items, super.key, this.child});

  final List<AppMenuItem> items;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<int>(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: BorderSide(color: cs.outline, width: 0.5),
      ),
      color: cs.surface,
      elevation: 4,
      onSelected: (i) => items[i].onTap(),
      itemBuilder: (_) => items.asMap().entries.map((e) {
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
      child: child ?? Icon(Icons.more_vert_rounded, color: cs.onSurface),
    );
  }
}
