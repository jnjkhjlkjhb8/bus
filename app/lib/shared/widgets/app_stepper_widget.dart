import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';

class AppStepperWidget extends StatelessWidget {
  const AppStepperWidget({
    required this.steps,
    required this.currentStep,
    super.key,
    this.horizontal = false,
  });

  final List<String> steps;
  final int currentStep;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (horizontal) {
      return Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _StepIndicator(index: i, current: currentStep, cs: cs),
            if (i < steps.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  color: i < currentStep ? cs.primary : cs.outline,
                ),
              ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Row(
            children: [
              _StepIndicator(index: i, current: currentStep, cs: cs),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  steps[i],
                  style: AppTextStyles.bodyRegular.copyWith(
                    color: i <= currentStep
                        ? cs.onSurface
                        : cs.onSurfaceVariant,
                    fontWeight: i == currentStep
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          if (i < steps.length - 1)
            Padding(
              padding: const EdgeInsets.only(left: 11),
              child: Container(
                width: 2,
                height: 24,
                color: i < currentStep ? cs.primary : cs.outline,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.index,
    required this.current,
    required this.cs,
  });

  final int index;
  final int current;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final done = index < current;
    final active = index == current;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? cs.primary : cs.surface,
        border: done
            ? null
            : Border.all(
                color: active ? cs.primary : cs.outline,
                width: 2,
              ),
      ),
      child: Center(
        child: done
            ? Icon(Icons.check_rounded, size: 14, color: cs.onPrimary)
            : Text(
                '${index + 1}',
                style: AppTextStyles.bodySmall.copyWith(
                  color: active ? cs.primary : cs.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
