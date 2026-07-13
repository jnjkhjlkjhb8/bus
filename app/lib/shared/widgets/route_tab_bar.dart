import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';

class RouteTabBar extends StatelessWidget implements PreferredSizeWidget {
  const RouteTabBar({
    required this.controller,
    required this.tabs,
    this.raised = false,
    super.key,
  });

  final TabController controller;
  final List<String> tabs;

  /// When true the bar sits on [ColorScheme.surfaceContainerLow] (used inside
  /// sheets) instead of [ColorScheme.surface]. Resolved against the live theme
  /// on every build so it tracks light/dark switches — passing a pre-resolved
  /// colour from a route builder that only runs once would leave it stale.
  final bool raised;

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: raised ? cs.surfaceContainerLow : cs.surface,
      child: TabBar(
        controller: controller,
        tabs: [for (final t in tabs) Tab(text: t)],
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicatorColor: cs.primary,
        dividerColor: cs.outlineVariant,
        labelStyle: AppTextStyles.bodyRegular.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppTextStyles.bodyRegular,
      ),
    );
  }
}
