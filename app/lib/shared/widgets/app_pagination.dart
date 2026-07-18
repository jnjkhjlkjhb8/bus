import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

class AppPagination extends StatelessWidget {
  const AppPagination({
    required this.page,
    required this.total,
    required this.onChanged,
    super.key,
  });

  final int page;
  final int total;
  final ValueChanged<int> onChanged;

  List<Object> _buildPageItems() {
    if (total <= 5) {
      return List<int>.generate(total, (i) => i + 1);
    }
    final items = <Object>[];
    if (page <= 3) {
      items.addAll([1, 2, 3, 4, 5]);
      if (total > 5) {
        items
          ..add('...')
          ..add(total);
      }
    } else if (page >= total - 2) {
      items
        ..add(1)
        ..add('...');
      for (var i = total - 4; i <= total; i++) {
        items.add(i);
      }
    } else {
      items
        ..add(1)
        ..add('...')
        ..add(page - 1)
        ..add(page)
        ..add(page + 1)
        ..add('...')
        ..add(total);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pageItems = _buildPageItems();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavBtn(
          icon: Icons.chevron_left_rounded,
          onPressed: page > 1 ? () => onChanged(page - 1) : null,
        ),
        const SizedBox(width: 4),
        for (final item in pageItems)
          if (item is int)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _PageBtn(
                pageNum: item,
                active: item == page,
                onTap: () => onChanged(item),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: Text(
                    '...',
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        const SizedBox(width: 4),
        _NavBtn(
          icon: Icons.chevron_right_rounded,
          onPressed: page < total ? () => onChanged(page + 1) : null,
        ),
      ],
    );
  }
}

class _PageBtn extends StatelessWidget {
  const _PageBtn({
    required this.pageNum,
    required this.active,
    required this.onTap,
  });

  final int pageNum;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: active ? null : onTap,
      semanticLabel: '第 $pageNum 頁',
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          ),
          child: Text(
            '$pageNum',
            style: AppTextStyles.bodyRegular.copyWith(
              color: active ? cs.onPrimary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onPressed,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Icon(
            icon,
            size: 20,
            color: onPressed != null
                ? cs.onSurface
                : cs.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
