import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_menu.dart';

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Menu'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Context Menu',
            child: Row(
              children: [
                AppMenuButton(
                  items: [
                    AppMenuItem(
                      label: '加入收藏',
                      icon: Icons.favorite_border_rounded,
                      onTap: () {},
                    ),
                    AppMenuItem(
                      label: '分享路線',
                      icon: Icons.share_rounded,
                      onTap: () {},
                    ),
                    AppMenuItem(
                      label: '刪除',
                      icon: Icons.delete_rounded,
                      onTap: () {},
                      isDestructive: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
