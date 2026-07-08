import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

/// Color-coded chip for a train type label.
class TrainTypeChip extends StatelessWidget {
  const TrainTypeChip({required this.type, super.key});

  /// Backend train type label to display.
  final String type;

  // Match on substrings, not exact strings: the backend labels a type as
  // '區間'/'區間車', '自強'/'自強號', or '自強(EMU3000)' interchangeably, and an
  // exact switch dropped every variant to grey. Order matters — the more
  // specific variant (區間快, EMU3000) must be tested before its base type.
  static Color _colorFor(String type) {
    final t = type.trim();
    if (t.contains('EMU3000') || t.contains('3000')) return AppTheme.train3000;
    if (t.contains('區間快')) return AppTheme.trainRangefast;
    if (t.contains('區間')) return AppTheme.trainRangecar;
    if (t.contains('普悠瑪')) return AppTheme.trainDelay;
    if (t.contains('太魯閣')) return AppTheme.trainTaroko;
    if (t.contains('自強')) return AppTheme.trainSelfstrong;
    if (t.contains('莒光')) return AppTheme.trainOrangelight;
    if (t.contains('高鐵')) return AppTheme.trainThsr;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _colorFor(type),
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.25,
        ),
      ),
      child: Text(
        type,
        style: AppTextStyles.bodySmall.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
