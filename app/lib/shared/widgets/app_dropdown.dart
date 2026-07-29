import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';

class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    required this.items,
    required this.valueListenable,
    required this.onChanged,
    required this.hint,
    super.key,
  });

  final List<DropdownItem<T>> items;
  final ValueNotifier<T?> valueListenable;
  final ValueChanged<T?> onChanged;
  final String hint;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = AppMotion.reduced(context);
    return DropdownButtonHideUnderline(
      child: DropdownButton2<T>(
        isExpanded: true,
        hint: Text(
          widget.hint,
          style: AppTextStyles.bodyLarge.copyWith(color: cs.onSurfaceVariant),
        ),
        items: widget.items
            .map(
              (item) => DropdownItem<T>(
                value: item.value,
                height: 44,
                child: _AppDropdownItem<T>(
                  value: item.value,
                  valueListenable: widget.valueListenable,
                  child: item.child,
                ),
              ),
            )
            .toList(),
        valueListenable: widget.valueListenable,
        onChanged: widget.onChanged,
        onMenuStateChange: (isOpen) {
          setState(() => _isOpen = isOpen);
        },
        buttonStyleData: ButtonStyleData(
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: cs.outline),
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        dropdownStyleData: DropdownStyleData(
          maxHeight: 240,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: cs.outline),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          openInterval: const Interval(0, 1, curve: AppMotion.easeOut),
        ),
        menuItemStyleData: const MenuItemStyleData(
          padding: EdgeInsets.zero,
        ),
        style: AppTextStyles.bodyRegular,
        iconStyleData: IconStyleData(
          icon: AnimatedRotation(
            turns: _isOpen ? 0.5 : 0,
            duration: reduceMotion ? Duration.zero : AppMotion.micro,
            curve: AppMotion.easeOut,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppDropdownItem<T> extends StatelessWidget {
  const _AppDropdownItem({
    required this.value,
    required this.valueListenable,
    required this.child,
  });

  final T? value;
  final ValueNotifier<T?> valueListenable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<T?>(
      valueListenable: valueListenable,
      builder: (context, selected, _) {
        final isSelected = value == selected;
        return Container(
          color: isSelected ? cs.primaryContainer : Colors.transparent,
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          width: double.infinity,
          child: DefaultTextStyle(
            style: AppTextStyles.bodyRegular.copyWith(
              color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
            ),
            child: child,
          ),
        );
      },
    );
  }
}
