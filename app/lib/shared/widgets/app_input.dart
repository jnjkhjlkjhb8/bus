import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

class AppInput extends StatelessWidget {
  const AppInput({
    required this.label,
    super.key,
    this.hint,
    this.helper,
    this.error,
    this.controller,
    this.onChanged,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
  });

  final String label;
  final String? hint;
  final String? helper;
  final String? error;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: AppTextStyles.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: error == null ? helper : null,
        errorText: error,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        border: _border(cs.outline),
        enabledBorder: _border(cs.outline),
        focusedBorder: _border(cs.primary, width: 2),
        errorBorder: _border(cs.error),
        focusedErrorBorder: _border(cs.error, width: 2),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        labelStyle: AppTextStyles.bodyRegular.copyWith(
          color: cs.onSurfaceVariant,
        ),
        helperStyle: AppTextStyles.bodySmall.copyWith(
          color: cs.onSurfaceVariant,
        ),
        errorStyle: AppTextStyles.bodySmall.copyWith(color: cs.error),
        hintStyle: AppTextStyles.bodyRegular.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
