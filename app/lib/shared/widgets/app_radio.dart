import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

class AppRadio<T> extends StatelessWidget {
  const AppRadio({
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.label,
    super.key,
  });

  final T value;
  final T? groupValue;
  final ValueChanged<T?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => onChanged(value),
      semanticLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: RadioGroup<T>(
          groupValue: groupValue,
          onChanged: onChanged,
          child: Row(
            children: [
              Radio<T>(value: value),
              const SizedBox(width: 4),
              Text(label, style: AppTextStyles.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
