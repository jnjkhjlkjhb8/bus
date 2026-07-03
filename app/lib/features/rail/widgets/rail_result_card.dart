import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';

const List<FontFeature> _tnum = AppTextStyles.tabularFigures;

class RailResultCard extends StatelessWidget {
  const RailResultCard({
    required this.trainType,
    required this.trainTypeColor,
    required this.trainNo,
    required this.departTime,
    required this.arrivalTime,
    required this.travelMinutes,
    required this.departStation,
    required this.arrivalStation,
    this.delayMinutes = 0,
    this.price,
    this.remark,
    this.onBook,
    this.onTap,
    this.highlighted = false,
    super.key,
  });

  final String trainType;
  final Color trainTypeColor;
  final String trainNo;
  final String departTime;
  final String arrivalTime;
  final int travelMinutes;
  final String departStation;
  final String arrivalStation;
  final int delayMinutes;
  final int? price;
  final String? remark;
  final VoidCallback? onBook;
  final VoidCallback? onTap;
  final bool highlighted;

  String get _duration {
    final h = travelMinutes ~/ 60;
    final m = travelMinutes % 60;
    return h > 0 ? '$h小時${m.toString().padLeft(2, '0')}分' : '$m分';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final delayed = delayMinutes > 0;
    final hasRemark = remark != null && remark!.isNotEmpty;

    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: highlighted ? cs.primaryContainer : cs.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          boxShadow: highlighted ? null : AppShadows.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _TrainTypeBadge(label: trainType, color: trainTypeColor),
                      const SizedBox(width: 8),
                      Text(
                        trainNo,
                        style: AppTextStyles.bodyRegular.copyWith(
                          fontFeatures: _tnum,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (price != null)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: r'NT$',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            TextSpan(
                              text: '$price',
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontFeatures: _tnum,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (price != null && onBook != null)
                      const SizedBox(width: 12),
                    if (onBook != null) _BookButton(onTap: onBook!),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  departTime,
                  style: AppTextStyles.memo.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFeatures: _tnum,
                    color: cs.onSurface,
                  ),
                ),
                Expanded(child: _JourneyConnector(duration: _duration)),
                Text(
                  arrivalTime,
                  style: AppTextStyles.memo.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFeatures: _tnum,
                    color: delayed ? cs.error : cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    departStation,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        arrivalStation,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                      ),
                      if (delayed) ...[
                        const SizedBox(height: 4),
                        _DelayPill(minutes: delayMinutes),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (hasRemark) ...[
              const SizedBox(height: 10),
              Divider(height: 1, thickness: 0.5, color: cs.outlineVariant),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '備註　',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      remark!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Color _badgeTextColor(Color bg) {
  final l = bg.computeLuminance();
  final whiteContrast = 1.05 / (l + 0.05);
  final blackContrast = (l + 0.05) / 0.05;
  return blackContrast >= whiteContrast ? Colors.black : Colors.white;
}

class _TrainTypeBadge extends StatelessWidget {
  const _TrainTypeBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusChip),
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(
          color: _badgeTextColor(color),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DelayPill extends StatelessWidget {
  const _DelayPill({required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusStadium),
      ),
      child: Text(
        '誤點 $minutes 分',
        style: AppTextStyles.bodySmall.copyWith(
          fontFeatures: _tnum,
          color: cs.onErrorContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BookButton extends StatelessWidget {
  const _BookButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: '訂購車票',
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
        child: Text(
          '訂購',
          style: AppTextStyles.bodyRegular.copyWith(
            color: cs.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _JourneyConnector extends StatelessWidget {
  const _JourneyConnector({required this.duration});
  final String duration;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            duration,
            style: AppTextStyles.bodySmall.copyWith(
              fontFeatures: _tnum,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 16,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.outlineVariant, width: 3.5),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.outlineVariant, width: 3.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
