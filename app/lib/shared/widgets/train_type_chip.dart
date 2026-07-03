import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

/// Color-coded chip for a train type label.
class TrainTypeChip extends StatelessWidget {
  const TrainTypeChip({required this.type, super.key});

  /// Backend train type label to display.
  final String type;

  static Color _colorFor(String type) {
    final normalized = type.trim();
    if (normalized.contains('EMU3000')) {
      return AppTheme.train3000;
    }
    switch (normalized) {
      case '自強號':
        return AppTheme.trainSelfstrong;
      case '區間車':
        return AppTheme.trainRangecar;
      case '區間快':
        return AppTheme.trainRangefast;
      case '太魯閣':
        return AppTheme.trainTaroko;
      case '莒光號':
        return AppTheme.trainOrangelight;
      case '高鐵':
        return AppTheme.trainThsr;
      case '普悠瑪':
        return AppTheme.trainDelay;
      default:
        return Colors.grey;
    }
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
