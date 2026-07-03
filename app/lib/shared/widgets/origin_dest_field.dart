import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

class OriginDestField extends StatelessWidget {
  const OriginDestField({
    required this.origin,
    required this.destination,
    required this.onOriginTap,
    required this.onDestTap,
    this.onSwap,
    super.key,
  });

  final String origin;
  final String destination;
  final VoidCallback onOriginTap;
  final VoidCallback onDestTap;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Row(label: '出發車站', value: origin, onTap: onOriginTap),
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 16,
                color: cs.outlineVariant,
              ),
              _Row(label: '抵達車站', value: destination, onTap: onDestTap),
            ],
          ),
        ),
        if (onSwap != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Pressable(
              onTap: onSwap,
              semanticLabel: '交換起訖站',
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Icon(
                  Icons.swap_vert_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: '$label $value',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 64, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTextStyles.heading2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
