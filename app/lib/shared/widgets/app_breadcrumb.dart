import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';

class AppBreadcrumb extends StatelessWidget {
  const AppBreadcrumb({required this.items, required this.onTap, super.key});

  final List<String> items;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: cs.onSurfaceVariant,
              ),
            GestureDetector(
              onTap: i < items.length - 1 ? () => onTap(i) : null,
              child: Text(
                items[i],
                style: AppTextStyles.bodyRegular.copyWith(
                  color: i == items.length - 1
                      ? cs.onSurface
                      : cs.onSurfaceVariant,
                  fontWeight: i == items.length - 1
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
