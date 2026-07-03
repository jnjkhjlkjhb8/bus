import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_button.dart';
import 'package:wheres_the_car/shared/widgets/app_dialog.dart';

class ModalPage extends StatelessWidget {
  const ModalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Modal'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Confirmation Dialog',
            child: AppButton(
              label: '刪除路線',
              icon: Icons.delete_rounded,
              onPressed: () => AppDialog.show<void>(
                context,
                title: '確認刪除',
                content: '此操作無法復原，確定要刪除這條路線嗎？',
                actions: [
                  AppButton.text(
                    label: '取消',
                    onPressed: () => Navigator.pop(context),
                  ),
                  AppButton.destructive(
                    label: '刪除',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
          ShowcaseSection(
            title: 'Info Dialog',
            child: AppButton.outlined(
              label: '查看說明',
              onPressed: () => AppDialog.show<void>(
                context,
                title: '關於即時動態',
                content: '即時動態資料每 30 秒自動更新，來源為 TDX 即時公車資料。',
                actions: [
                  AppButton(
                    label: '了解',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
          ShowcaseSection(
            title: 'Destructive Dialog',
            child: AppButton.destructive(
              label: '清除快取',
              icon: Icons.warning_rounded,
              onPressed: () => AppDialog.show<void>(
                context,
                title: '清除所有快取',
                content: '此操作將清除本機所有快取資料，確定繼續？',
                actions: [
                  AppButton.text(
                    label: '取消',
                    onPressed: () => Navigator.pop(context),
                  ),
                  AppButton.destructive(
                    label: '清除',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
