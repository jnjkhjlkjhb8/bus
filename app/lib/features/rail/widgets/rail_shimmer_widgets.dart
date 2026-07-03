part of '../view/rail_screen.dart';

class _ShimmerTrainList extends StatefulWidget {
  const _ShimmerTrainList();

  @override
  State<_ShimmerTrainList> createState() => _ShimmerTrainListState();
}

class _ShimmerTrainListState extends State<_ShimmerTrainList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shimmerColor = cs.surfaceContainerHigh.withValues(alpha: 0.6);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations && _animController.isAnimating) {
      _animController.stop();
    } else if (!disableAnimations && !_animController.isAnimating) {
      unawaited(_animController.repeat(reverse: true));
    }

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) => Opacity(
        opacity: disableAnimations
            ? 0.6
            : lerpDouble(0.4, 0.9, _animController.value)!,
        child: child,
      ),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++) ...[
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 20,
                        decoration: BoxDecoration(
                          color: shimmerColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 32,
                        height: 16,
                        decoration: BoxDecoration(
                          color: shimmerColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 24,
                          decoration: BoxDecoration(
                            color: shimmerColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 32),
                      Expanded(
                        child: Container(
                          height: 24,
                          decoration: BoxDecoration(
                            color: shimmerColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
