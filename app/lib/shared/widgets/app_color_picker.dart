import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

class AppColorPicker extends StatelessWidget {
  const AppColorPicker({
    required this.color,
    required this.onChanged,
    super.key,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return ColorPicker(
      color: color,
      onColorChanged: onChanged,
      spacing: 8,
      runSpacing: 8,
      borderRadius: AppTheme.radiusButton,
      enableShadesSelection: false,
      pickersEnabled: const {
        ColorPickerType.both: false,
        ColorPickerType.primary: false,
        ColorPickerType.accent: false,
        ColorPickerType.bw: false,
        ColorPickerType.custom: false,
        ColorPickerType.customSecondary: false,
        ColorPickerType.wheel: true,
      },
    );
  }
}
