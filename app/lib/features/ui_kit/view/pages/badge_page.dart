import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_badge.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';

class BadgePage extends StatelessWidget {
  const BadgePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Badge'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: const [
          ShowcaseSection(
            title: 'Dot',
            child: AppBadge(),
          ),
          ShowcaseSection(
            title: 'Filled Count',
            child: Row(
              children: [
                AppBadge(label: '3'),
                SizedBox(width: 8),
                AppBadge(label: '99+'),
                SizedBox(width: 8),
                AppBadge(label: '新'),
              ],
            ),
          ),
          ShowcaseSection(
            title: 'Outlined',
            child: Row(
              children: [
                AppBadge.outlined(label: 'Beta'),
                SizedBox(width: 8),
                AppBadge.outlined(label: '即時'),
              ],
            ),
          ),
          ShowcaseSection(
            title: 'Data Color',
            child: Row(
              children: [
                AppBadge(label: '自強', color: Color(0xFF1B5E20)),
                SizedBox(width: 8),
                AppBadge(label: '區間', color: Color(0xFFFFC107)),
                SizedBox(width: 8),
                AppBadge(label: '676', color: Color(0xFFE65100)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
