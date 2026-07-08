import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_button.dart';
import 'package:wheres_the_car/shared/widgets/app_snackbar.dart';

class SnackbarPage extends StatelessWidget {
  const SnackbarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Snackbar'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Neutral',
            child: AppButton.outlined(
              label: '顯示',
              onPressed: () => AppSnackbar.show(context, '開發者模式已啟用'),
            ),
          ),
          ShowcaseSection(
            title: 'Success',
            child: AppButton.outlined(
              label: '顯示',
              onPressed: () => AppSnackbar.show(
                context,
                '已抵達目的地',
                type: SnackType.success,
              ),
            ),
          ),
          ShowcaseSection(
            title: 'Error',
            child: AppButton.outlined(
              label: '顯示',
              onPressed: () => AppSnackbar.show(
                context,
                '無法取得目前位置',
                type: SnackType.error,
              ),
            ),
          ),
          ShowcaseSection(
            title: 'With undo action',
            child: AppButton.outlined(
              label: '顯示',
              onPressed: () => AppSnackbar.show(
                context,
                '已清除 3 則通知',
                action: '復原',
                onAction: () {},
              ),
            ),
          ),
          ShowcaseSection(
            title: 'Long text wraps',
            child: AppButton.outlined(
              label: '顯示',
              onPressed: () => AppSnackbar.show(
                context,
                '已為您開啟 自強 3000 車次訂票系統，請於外部瀏覽器完成付款',
                action: '關閉',
                onAction: () {},
              ),
            ),
          ),
        ],
      ),
    );
  }
}
