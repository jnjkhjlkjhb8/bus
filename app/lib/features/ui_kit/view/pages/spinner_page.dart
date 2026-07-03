import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_spinner.dart';
import 'package:wheres_the_car/shared/widgets/state_cards.dart';

class SpinnerPage extends StatelessWidget {
  const SpinnerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const DetailAppBar(title: 'Spinner'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const ShowcaseSection(
            title: 'Sizes',
            child: Row(
              children: [
                AppSpinner(size: 16),
                SizedBox(width: 16),
                AppSpinner(),
                SizedBox(width: 16),
                AppSpinner(size: 40),
              ],
            ),
          ),
          ShowcaseSection(
            title: 'Colors',
            child: Row(
              children: [
                const AppSpinner(),
                const SizedBox(width: 16),
                AppSpinner(color: cs.tertiary),
              ],
            ),
          ),
          const ShowcaseSection(
            title: 'Shimmer',
            child: Column(
              children: [
                ShimmerRow(),
                ShimmerRow(height: 64),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
