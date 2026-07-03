import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_button.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';

class BottomSheetPage extends StatelessWidget {
  const BottomSheetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Bottom Sheet'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Draggable Sheet',
            child: AppButton(
              label: '開啟 Bottom Sheet',
              onPressed: () => BottomSheetShell.show<void>(
                context: context,
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('路線資訊', style: AppTextStyles.heading1),
                      SizedBox(height: 8),
                      Text('307 往中壢｜萬芳醫院站', style: AppTextStyles.bodyRegular),
                      SizedBox(height: 16),
                      Text('預計抵達：5 分鐘', style: AppTextStyles.bodyLarge),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
