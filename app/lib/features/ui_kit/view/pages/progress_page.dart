import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_progress_bar.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Progress Bar'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: const [
          ShowcaseSection(
            title: 'Determinate',
            child: Column(
              children: [
                AppProgressBar(value: 0),
                SizedBox(height: 12),
                AppProgressBar(value: 0.4),
                SizedBox(height: 12),
                AppProgressBar(value: 1),
              ],
            ),
          ),
          ShowcaseSection(
            title: 'Indeterminate',
            child: AppProgressBar(),
          ),
        ],
      ),
    );
  }
}
