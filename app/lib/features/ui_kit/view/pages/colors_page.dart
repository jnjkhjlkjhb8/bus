import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';

class ColorsPage extends StatelessWidget {
  const ColorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const DetailAppBar(title: 'Colors'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ShowcaseSection(
            title: 'M3 Scheme (seed #6750A4)',
            child: Wrap(
              children: [
                _Swatch('primary', cs.primary),
                _Swatch('onPrimary', cs.onPrimary, text: cs.primary),
                _Swatch('primaryContainer', cs.primaryContainer),
                _Swatch('surface', cs.surface),
                _Swatch('surfaceContainerLow', cs.surfaceContainerLow),
                _Swatch('surfaceContainerHighest', cs.surfaceContainerHighest),
                _Swatch('onSurface', cs.onSurface, text: cs.surface),
                _Swatch(
                  'onSurfaceVariant',
                  cs.onSurfaceVariant,
                  text: cs.surface,
                ),
                _Swatch('outline', cs.outline, text: cs.surface),
                _Swatch('error', cs.error, text: Colors.white),
                _Swatch('errorContainer', cs.errorContainer),
              ],
            ),
          ),
          const ShowcaseSection(
            title: 'TRA Train Types',
            child: Wrap(
              children: [
                _Swatch('train3000', AppTheme.train3000, text: Colors.white),
                _Swatch('trainSelfstrong', AppTheme.trainSelfstrong),
                _Swatch(
                  'trainRangecar',
                  AppTheme.trainRangecar,
                  text: Colors.white,
                ),
                _Swatch('trainRangefast', AppTheme.trainRangefast),
                _Swatch('trainTaroko', AppTheme.trainTaroko),
                _Swatch('trainOrangelight', AppTheme.trainOrangelight),
                _Swatch('trainThsr', AppTheme.trainThsr, text: Colors.white),
              ],
            ),
          ),
          const ShowcaseSection(
            title: 'MRT Lines',
            child: Wrap(
              children: [
                _Swatch('mrtBL', AppTheme.mrtBL, text: Colors.white),
                _Swatch('mrtR', AppTheme.mrtR, text: Colors.white),
                _Swatch('mrtG', AppTheme.mrtG, text: Colors.white),
                _Swatch('mrtO', AppTheme.mrtO),
                _Swatch('mrtBR', AppTheme.mrtBR),
                _Swatch('mrtY', AppTheme.mrtY),
                _Swatch('mrtAM', AppTheme.mrtAM, text: Colors.white),
                _Swatch('mrtTG', AppTheme.mrtTG),
                _Swatch('mrtKG', AppTheme.mrtKG),
                _Swatch('mrtKR', AppTheme.mrtKR, text: Colors.white),
                _Swatch('mrtKO', AppTheme.mrtKO),
              ],
            ),
          ),
          const ShowcaseSection(
            title: 'Status & Semantic',
            child: Wrap(
              children: [
                _Swatch('ferryBlue', AppTheme.ferryBlue, text: Colors.white),
                _Swatch('statusArriving', AppTheme.statusArriving),
                _Swatch('warningBg', AppTheme.warningBg),
                _Swatch(
                  'warningBorder',
                  AppTheme.warningBorder,
                  text: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.color, {this.text});
  final String name;
  final Color color;
  final Color? text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      margin: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 4),
          Text(name, style: AppTextStyles.bodyVerySmall),
        ],
      ),
    );
  }
}
