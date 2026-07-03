import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';

class SpacingPage extends StatelessWidget {
  const SpacingPage({super.key});

  static const _spacings = [
    ('xs', 4.0),
    ('sm', 8.0),
    ('md', 16.0),
    ('lg', 24.0),
    ('xl', 32.0),
    ('2xl', 48.0),
    ('3xl', 64.0),
  ];

  static const List<(String, double)> _radii = [
    ('radiusChip', AppTheme.radiusChip),
    ('radiusButton', AppTheme.radiusButton),
    ('radiusCard', AppTheme.radiusCard),
    ('radiusModal', AppTheme.radiusModal),
    ('radiusBottomSheet', AppTheme.radiusBottomSheet),
    ('radiusSearchBar', AppTheme.radiusSearchBar),
    ('radiusStadium', AppTheme.radiusStadium),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const DetailAppBar(title: 'Spacing & Radii'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ShowcaseSection(
            title: 'Spacing (4px grid)',
            child: Column(
              children: _spacings
                  .map(
                    (s) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text(
                              s.$1,
                              style: AppTextStyles.bodySmall.copyWith(
                                fontFamily: 'IBMPlexMono',
                              ),
                            ),
                          ),
                          Container(
                            width: s.$2,
                            height: 16,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${s.$2.toInt()}px',
                            style: AppTextStyles.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          ShowcaseSection(
            title: 'Corner Radii',
            child: Wrap(
              children: _radii
                  .map(
                    (r) => Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(
                                r.$2.clamp(0, 28),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(r.$1, style: AppTextStyles.bodyVerySmall),
                          Text(
                            '${r.$2.toInt()}px',
                            style: AppTextStyles.bodyVerySmall,
                          ),
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
