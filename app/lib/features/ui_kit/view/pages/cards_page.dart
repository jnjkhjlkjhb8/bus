import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_card.dart';

class CardsPage extends StatelessWidget {
  const CardsPage({super.key});

  static const _content = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('307 往中壢', style: AppTextStyles.heading2),
      SizedBox(height: 4),
      Text('下一班：5 分鐘', style: AppTextStyles.bodyRegular),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Cards'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: const [
          ShowcaseSection(
            title: 'Elevated',
            child: AppCard(child: _content),
          ),
          ShowcaseSection(
            title: 'Filled',
            child: AppCard.filled(child: _content),
          ),
          ShowcaseSection(
            title: 'Outlined',
            child: AppCard.outlined(child: _content),
          ),
        ],
      ),
    );
  }
}
