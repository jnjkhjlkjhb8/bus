import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';

class AppTabs extends StatelessWidget {
  const AppTabs({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    super.key,
    this.scrollable = false,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: tabs.length,
      initialIndex: selectedIndex,
      child: TabBar(
        isScrollable: scrollable,
        onTap: onChanged,
        indicatorColor: cs.primary,
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: AppTextStyles.bodyRegular.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppTextStyles.bodyRegular,
        tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: tabs.map((t) => Tab(height: 44, text: t)).toList(),
      ),
    );
  }
}
