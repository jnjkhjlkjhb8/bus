import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';

/// The train classes the app gives a chip of its own.
///
/// An identity, not a label: the backend spells one class several ways
/// ('區間'/'區間車', '自強(EMU3000)'/'新自強'), and callers need to compare
/// classes without going through display text that changes with the locale.
enum TrainType {
  newTzeChiang,
  localExpress,
  local,
  puyuma,
  taroko,
  tzeChiang,
  chuKuang,
  thsr,
  other;

  /// Matches on substrings, not exact strings: the backend labels a class as
  /// '區間'/'區間車', '自強'/'自強號', or '自強(EMU3000)' interchangeably, and every
  /// variant has to collapse to the same case. Order matters — the more
  /// specific variant (區間快, EMU3000) must be tested before its base type,
  /// and '新自強' is tested alongside the EMU3000 spellings so an
  /// already-canonical label doesn't fall through to '自強' and downgrade.
  static TrainType of(String type) {
    final t = type.trim();
    if (t.contains('EMU3000') || t.contains('3000') || t.contains('新自強')) {
      return TrainType.newTzeChiang;
    }
    if (t.contains('區間快')) return TrainType.localExpress;
    if (t.contains('區間')) return TrainType.local;
    if (t.contains('普悠瑪')) return TrainType.puyuma;
    if (t.contains('太魯閣')) return TrainType.taroko;
    if (t.contains('自強')) return TrainType.tzeChiang;
    if (t.contains('莒光')) return TrainType.chuKuang;
    if (t.contains('高鐵')) return TrainType.thsr;
    return TrainType.other;
  }

  /// The canonical display name. [raw] is echoed back for [other], which is
  /// whatever the backend called a class the app has no chip for.
  String labelOf(AppI18n i18n, String raw) => switch (this) {
    TrainType.newTzeChiang => i18n.trainTypeNewTzeChiang,
    TrainType.localExpress => i18n.trainTypeLocalExpress,
    TrainType.local => i18n.trainTypeLocal,
    TrainType.puyuma => i18n.trainTypePuyuma,
    TrainType.taroko => i18n.trainTypeTaroko,
    TrainType.tzeChiang => i18n.trainTypeTzeChiang,
    TrainType.chuKuang => i18n.trainTypeChuKuang,
    TrainType.thsr => i18n.modeThsr,
    TrainType.other => raw.trim(),
  };

  /// The chip label for a dense row, which drops the 車/號 suffix the full
  /// name carries: the stem is what tells the classes apart, and the suffix is
  /// what pushes the chip wide enough to squeeze the columns beside it.
  String compactLabelOf(AppI18n i18n, String raw) => switch (this) {
    TrainType.newTzeChiang => i18n.trainTypeNewTzeChiangShort,
    TrainType.localExpress => i18n.trainTypeLocalExpressShort,
    TrainType.local => i18n.trainTypeLocalShort,
    TrainType.tzeChiang => i18n.trainTypeTzeChiangShort,
    TrainType.chuKuang => i18n.trainTypeChuKuangShort,
    _ => labelOf(i18n, raw),
  };

  Color get color => switch (this) {
    TrainType.newTzeChiang => AppTheme.train3000,
    TrainType.localExpress => AppTheme.trainRangefast,
    TrainType.local => AppTheme.trainRangecar,
    TrainType.puyuma => AppTheme.trainDelay,
    TrainType.taroko => AppTheme.trainTaroko,
    TrainType.tzeChiang => AppTheme.trainSelfstrong,
    TrainType.chuKuang => AppTheme.trainOrangelight,
    TrainType.thsr => AppTheme.trainThsr,
    TrainType.other => Colors.grey,
  };
}

/// Color-coded chip for a train type label.
class TrainTypeChip extends StatelessWidget {
  const TrainTypeChip({required this.type, super.key, this.compact = false});

  /// Backend train type label to display.
  final String type;

  /// Drops the chip to the shortened label and a smaller box, for dense rows
  /// where the full name would squeeze the columns beside it.
  final bool compact;

  /// The canonical display name for a backend train type label, for callers
  /// that show the type as text rather than as a chip. Goes through the same
  /// [TrainType] table as the chip, so a screen's title can't drift from the
  /// chip beside it.
  static String canonicalLabel(AppI18n i18n, String type) =>
      TrainType.of(type).labelOf(i18n, type);

  // A fixed luminance threshold (the ~0.18 crossover between white and ink
  // contrast) misclassifies the saturated operator oranges/reds (自強,
  // 太魯閣, 高鐵): their luminance sits well above that crossover, yet white
  // still can't reach the 4.5:1 small-text minimum against them. Comparing
  // the two actual contrast ratios instead of thresholding luminance holds
  // for every background, including ones added later.
  static Color _labelColorFor(Color background) {
    final bgLuminance = background.computeLuminance();
    double contrastWith(Color foreground) {
      final fgLuminance = foreground.computeLuminance();
      final lighter = math.max(bgLuminance, fgLuminance);
      final darker = math.min(bgLuminance, fgLuminance);
      return (lighter + 0.05) / (darker + 0.05);
    }

    return contrastWith(AppTheme.inkLight) >= contrastWith(Colors.white)
        ? AppTheme.inkLight
        : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final trainType = TrainType.of(type);
    final color = trainType.color;
    final labelColor = _labelColorFor(color);
    return Container(
      // Compact drops the fixed height as well as the label: at large text
      // scales a 20px box would clip the glyphs it is meant to shrink around,
      // so the padding sets the size and the text decides the rest. It does
      // take a minimum width, so that a three-glyph label (區間快, 太魯閣) does
      // not widen the chip and shove the train number out of the column the
      // rows above it established.
      height: compact ? null : 28,
      constraints: compact
          ? BoxConstraints(
              minWidth: MediaQuery.textScalerOf(context).scale(46),
            )
          : null,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 12,
        vertical: compact ? 2 : 0,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.25,
        ),
      ),
      child: Text(
        compact
            ? trainType.compactLabelOf(i18n, type)
            : trainType.labelOf(i18n, type),
        style: (compact ? AppTextStyles.bodyVerySmall : AppTextStyles.bodySmall)
            .copyWith(
              color: labelColor,
              fontWeight: FontWeight.w600,
              height: compact ? 1.2 : null,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
