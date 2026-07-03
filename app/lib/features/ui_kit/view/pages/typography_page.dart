import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';

class TypographyPage extends StatelessWidget {
  const TypographyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Typography'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: const [
          ShowcaseSection(
            title: 'IBM Plex Sans',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Heading 1 — 24px 700', style: AppTextStyles.heading1),
                  SizedBox(height: 8),
                  Text('Heading 2 — 18px 600', style: AppTextStyles.heading2),
                  SizedBox(height: 8),
                  Text('Body Large — 16px 400', style: AppTextStyles.bodyLarge),
                  SizedBox(height: 8),
                  Text(
                    'Body Regular — 14px 400',
                    style: AppTextStyles.bodyRegular,
                  ),
                  SizedBox(height: 8),
                  Text('Body Small — 12px 400', style: AppTextStyles.bodySmall),
                  SizedBox(height: 8),
                  Text(
                    'Body Very Small — 8px 400',
                    style: AppTextStyles.bodyVerySmall,
                  ),
                ],
              ),
            ),
          ),
          ShowcaseSection(
            title: 'IBM Plex Mono',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Memo — 13px 400  14:32  1.0.0',
                style: AppTextStyles.memo,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
