part of '../home_screen.dart';

class _MapSkeleton extends StatelessWidget {
  const _MapSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final road = cs.outlineVariant.withValues(alpha: 0.55);
    final block = cs.surfaceContainerHighest.withValues(alpha: 0.75);

    return ColoredBox(
      color: cs.surfaceContainerLow,
      child: Stack(
        children: [
          Positioned(
            left: -40,
            top: 120,
            right: -20,
            child: Transform.rotate(
              angle: -0.18,
              child: Container(
                height: 22,
                decoration: BoxDecoration(
                  color: road,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Positioned(
            left: 40,
            top: 40,
            bottom: 80,
            child: Transform.rotate(
              angle: 0.25,
              child: Container(
                width: 18,
                decoration: BoxDecoration(
                  color: road,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Positioned(
            right: -20,
            top: 220,
            bottom: 0,
            child: Transform.rotate(
              angle: -0.35,
              child: Container(
                width: 26,
                decoration: BoxDecoration(
                  color: road,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          Positioned(
            left: 120,
            top: 78,
            child: _SkeletonBlock(color: block, width: 88, height: 58),
          ),
          Positioned(
            right: 54,
            top: 150,
            child: _SkeletonBlock(color: block, width: 112, height: 72),
          ),
          Positioned(
            left: 54,
            bottom: 250,
            child: _SkeletonBlock(color: block, width: 104, height: 64),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.color,
    required this.width,
    required this.height,
  });

  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
