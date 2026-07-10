import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

class AppBarCircleButton extends StatelessWidget {
  const AppBarCircleButton({
    required this.child,
    this.onTap,
    this.semanticLabel,
    super.key,
  });
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            decoration: AppTheme.floatingControl(cs, shape: BoxShape.circle),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class MapCloseButton extends StatelessWidget {
  const MapCloseButton({this.onPressed, super.key});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBarCircleButton(
      onTap: onPressed ?? () => context.pop(),
      semanticLabel: '關閉',
      child: Icon(Icons.close_rounded, size: 20, color: cs.onSurface),
    );
  }
}

class DetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DetailAppBar({
    this.title,
    this.subtitle,
    this.onBack,
    this.actions,
    this.titleTrailing = false,
    this.centerTitle = false,
    super.key,
  });
  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final bool titleTrailing;
  final bool centerTitle;

  static const double _barHeight = 56;

  @override
  Size get preferredSize => const Size.fromHeight(_barHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: _barHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
            child: NavigationToolbar(
              leading: _BackButton(
                onTap:
                    onBack ??
                    () => Navigator.of(context, rootNavigator: true).maybePop(),
              ),
              middle: title != null
                  ? _Title(
                      title!,
                      subtitle,
                      textAlign: centerTitle
                          ? TextAlign.center
                          : TextAlign.left,
                    )
                  : null,
              trailing: actions != null && actions!.isNotEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions!,
                    )
                  : null,
              centerMiddle: centerTitle,
              middleSpacing: 8,
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: '返回',
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: cs.onSurface,
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.title, this.subtitle, {this.textAlign});
  final String title;
  final String? subtitle;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final align = textAlign ?? TextAlign.start;
    if (subtitle != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: align == TextAlign.center
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              height: 1.2,
            ),
            textAlign: align,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle!,
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.2,
            ),
            textAlign: align,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
    return Text(
      title,
      style: AppTextStyles.bodyLarge.copyWith(
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      textAlign: align,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class PlannerAppBar extends StatelessWidget {
  const PlannerAppBar({
    required this.destName,
    this.isFavorite = false,
    this.onBack,
    this.onBookmark,
    this.actions,
    super.key,
  });
  final String destName;
  final bool isFavorite;
  final VoidCallback? onBack;
  final VoidCallback? onBookmark;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _BackButton(onTap: onBack ?? () => context.pop()),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.radio_button_checked_rounded,
                size: 14,
                color: cs.outline,
              ),
              Container(width: 1.5, height: 20, color: cs.outlineVariant),
              Icon(Icons.location_on_rounded, size: 18, color: cs.primary),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '您的位置',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                Divider(height: 8, color: cs.outlineVariant),
                Text(
                  destName,
                  style: AppTextStyles.bodyRegular.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Semantics(
                  label: isFavorite ? '取消收藏' : '加入收藏',
                  button: true,
                  child: IconButton(
                    icon: Icon(
                      isFavorite
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 20,
                      color: cs.onSurface,
                    ),
                    onPressed: onBookmark,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (actions != null)
                for (final action in actions!)
                  SizedBox(width: 44, height: 44, child: action),
            ],
          ),
        ],
      ),
    );
  }
}
