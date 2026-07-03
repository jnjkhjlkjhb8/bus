import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/transport_icon.dart';

class IconsPage extends StatelessWidget {
  const IconsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Icons'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ShowcaseSection(
            title: 'Transport Icons',
            child: Wrap(
              children: TransportType.values
                  .map(
                    (t) => Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          TransportIcon(type: t, size: 32),
                          const SizedBox(height: 4),
                          Text(t.name, style: AppTextStyles.bodyVerySmall),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
