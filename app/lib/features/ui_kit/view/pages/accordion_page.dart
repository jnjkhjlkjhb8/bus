import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_accordion.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';

class AccordionPage extends StatelessWidget {
  const AccordionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Accordion'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: const [
          ShowcaseSection(
            title: 'Expandable Sections',
            child: Column(
              children: [
                AppAccordion(
                  title: '服務說明',
                  initiallyExpanded: true,
                  child: Text(
                    '我車呢提供公車、捷運、台鐵即時資訊，以及路線規劃功能。',
                    style: AppTextStyles.bodyRegular,
                  ),
                ),
                SizedBox(height: 8),
                AppAccordion(
                  title: '隱私政策',
                  child: Text(
                    '本應用程式不收集個人識別資訊，位置資料僅用於地圖顯示。',
                    style: AppTextStyles.bodyRegular,
                  ),
                ),
                SizedBox(height: 8),
                AppAccordion(
                  title: '版本記錄',
                  child: Text(
                    'v1.0.0 — 初始發布\nv1.0.1 — 修正路線顯示問題',
                    style: AppTextStyles.bodyRegular,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
