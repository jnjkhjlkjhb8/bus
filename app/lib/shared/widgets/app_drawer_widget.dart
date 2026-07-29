import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';

class AppDrawerItem {
  const AppDrawerItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class AppDrawerWidget extends StatelessWidget {
  const AppDrawerWidget({
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    super.key,
    this.header,
  });

  final List<AppDrawerItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Drawer(
      width: 280,
      backgroundColor: cs.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (header != null) ...[
              header!,
              const SizedBox(height: 8),
            ],
            ...items.asMap().entries.map((e) {
              final active = e.key == selectedIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: Pressable(
                  onTap: () => onChanged(e.key),
                  semanticLabel: e.value.label,
                  child: ListTile(
                    leading: Icon(
                      e.value.icon,
                      size: 20,
                      color: active
                          ? cs.onSecondaryContainer
                          : cs.onSurfaceVariant,
                    ),
                    title: Text(
                      e.value.label,
                      style: AppTextStyles.bodyRegular.copyWith(
                        color: active
                            ? cs.onSecondaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                    selected: active,
                    selectedTileColor: cs.secondaryContainer,
                    tileColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusStadium,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
