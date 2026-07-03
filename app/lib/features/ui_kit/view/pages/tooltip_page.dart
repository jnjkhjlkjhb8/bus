import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_button.dart';
import 'package:wheres_the_car/shared/widgets/app_tooltip.dart';

class TooltipPage extends StatelessWidget {
  const TooltipPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Tooltip'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'IconButton',
            child: Row(
              children: [
                AppTooltip(
                  message: '資訊',
                  child: IconButton(
                    icon: const Icon(Icons.info_rounded),
                    onPressed: () {},
                  ),
                ),
                const SizedBox(width: 8),
                AppTooltip(
                  message: '說明',
                  child: IconButton(
                    icon: const Icon(Icons.help_rounded),
                    onPressed: () {},
                  ),
                ),
              ],
            ),
          ),
          const ShowcaseSection(
            title: 'Text Label',
            child: AppTooltip(
              message: '長按查看提示',
              child: Text('長按我'),
            ),
          ),
          ShowcaseSection(
            title: 'AppButton',
            child: AppTooltip(
              message: '提交表單',
              child: AppButton(
                label: '送出',
                onPressed: () {},
              ),
            ),
          ),
        ],
      ),
    );
  }
}
