import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';

class AppRadio<T> extends StatefulWidget {
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
  State<AppRadio<T>> createState() => _AppRadioState<T>();
}

class _AppRadioState<T> extends State<AppRadio<T>> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () => widget.onChanged(widget.value),
      child: AnimatedScale(
        scale: _pressed ? AppMotion.pressedScale : 1.0,
        duration: AppMotion.press,
        curve: AppMotion.easeOut,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: RadioGroup<T>(
            groupValue: widget.groupValue,
            onChanged: widget.onChanged,
            child: Row(
              children: [
                Radio<T>(value: widget.value),
                const SizedBox(width: 4),
                Text(widget.label, style: AppTextStyles.bodyLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
