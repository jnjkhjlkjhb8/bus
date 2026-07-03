part of '../view/rail_screen.dart';

class _TrainCard extends StatefulWidget {
  const _TrainCard({
    required this.type,
    required this.number,
    required this.delay,
    required this.depart,
    required this.arrive,
    required this.duration,
    required this.origin,
    required this.destination,
  });

  final String type;
  final String number;
  final int delay;
  final String depart;
  final String arrive;
  final String duration;
  final String origin;
  final String destination;

  @override
  State<_TrainCard> createState() => _TrainCardState();
}

class _TrainCardState extends State<_TrainCard> {
  int _getPrice() {
    if (widget.type.contains('自強') || widget.type.contains('普悠瑪')) {
      return 443;
    } else if (widget.type.contains('區間快')) {
      return 340;
    } else {
      return 285;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Pressable(
      onTap: () {
        unawaited(HapticService.instance.lightTap());
        unawaited(
          Navigator.push(
            context,
            PageRouteBuilder<void>(
              pageBuilder: (_, _, _) => RailTrainScreen(
                type: widget.type,
                trainNo: widget.number,
              ),
              transitionsBuilder: (_, animation, _, child) => SlideTransition(
                position: animation.drive(
                  Tween(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeOut)),
                ),
                child: child,
              ),
            ),
          ),
        );
      },
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TrainTypeChip(type: widget.type),
                    const SizedBox(width: 8),
                    Text(
                      widget.number,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.delay > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '+${widget.delay}分',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'NT\$ ${_getPrice()}',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Pressable(
                      onTap: () {
                        unawaited(HapticService.instance.lightTap());
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '已為您開啟 ${widget.type} ${widget.number} 車次訂票系統',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '訂購',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 75,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.depart,
                        style: AppTextStyles.memo.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                          fontFeatures: AppTextStyles.tabularFigures,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.duration,
                        style: AppTextStyles.bodyVerySmall.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.arrive,
                        style: AppTextStyles.memo.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                          fontFeatures: AppTextStyles.tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 64,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 6,
                              height: double.infinity,
                              decoration: BoxDecoration(
                                color: cs.outlineVariant,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            Align(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: cs.outlineVariant,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: cs.outlineVariant,
                                    width: 3.5,
                                  ),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: cs.outlineVariant,
                                    width: 3.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 64,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                widget.origin,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                widget.destination,
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              color: cs.outlineVariant.withValues(alpha: 0.5),
              height: 1,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '備註：',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
