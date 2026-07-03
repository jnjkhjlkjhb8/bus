import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_button.dart';

class ButtonsPage extends StatelessWidget {
  const ButtonsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Buttons'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Filled',
            child: Column(
              children: [
                AppButton(
                  label: '查詢路線',
                  icon: Icons.search_rounded,
                  onPressed: () {},
                ),
                const SizedBox(height: 8),
                const AppButton(label: '已停用'),
              ],
            ),
          ),
          ShowcaseSection(
            title: 'Outlined',
            child: Column(
              children: [
                AppButton.outlined(label: '取消', onPressed: () {}),
                const SizedBox(height: 8),
                AppButton.outlined(
                  label: '分享',
                  icon: Icons.share_rounded,
                  onPressed: () {},
                ),
              ],
            ),
          ),
          ShowcaseSection(
            title: 'Text',
            child: AppButton.text(label: '了解更多', onPressed: () {}),
          ),
          ShowcaseSection(
            title: 'Destructive',
            child: AppButton.destructive(
              label: '刪除',
              icon: Icons.delete_rounded,
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}
