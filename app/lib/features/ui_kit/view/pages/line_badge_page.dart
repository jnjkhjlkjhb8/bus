import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/line_badge.dart';

class LineBadgePage extends StatelessWidget {
  const LineBadgePage({super.key});

  static const _lines = <(String, Color)>[
    ('BL', AppTheme.mrtBL),
    ('R', AppTheme.mrtR),
    ('G', AppTheme.mrtG),
    ('O', AppTheme.mrtO),
    ('BR', AppTheme.mrtBR),
    ('Y', AppTheme.mrtY),
    ('AM', AppTheme.mrtAM),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Line Badge'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Taipei Metro lines (25dp)',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (code, color) in _lines)
                    LineBadge(
                      label: code,
                      color: color,
                      svgAsset: LineBadge.trtcAsset(code),
                    ),
                ],
              ),
            ),
          ),
          ShowcaseSection(
            title: 'Sizes (BL)',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                spacing: 12,
                children: [
                  for (final s in const [25.0, 28.0, 32.0])
                    LineBadge(
                      label: 'BL',
                      color: AppTheme.mrtBL,
                      svgAsset: LineBadge.trtcAsset('BL'),
                      size: s,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
