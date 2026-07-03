import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';

class ShadowsPage extends StatelessWidget {
  const ShadowsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Shadows'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: const [
          ShowcaseSection(
            title: 'Elevation Tokens',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _ShadowCard('card', AppShadows.card, 'offset (0,2) blur 8'),
                  SizedBox(height: 24),
                  _ShadowCard(
                    'floating',
                    AppShadows.floating,
                    'offset (0,4) blur 16',
                  ),
                  SizedBox(height: 24),
                  _ShadowCard(
                    'bottomSheet',
                    AppShadows.bottomSheet,
                    'dual shadow',
                  ),
                  SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShadowCard extends StatelessWidget {
  const _ShadowCard(this.name, this.shadows, this.description);
  final String name;
  final List<BoxShadow> shadows;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        boxShadow: shadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: AppTextStyles.bodyRegular),
          Text(description, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}
