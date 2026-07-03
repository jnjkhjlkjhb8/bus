part of '../view/bus_stop_screen.dart';

class _StopSkeletonList extends StatefulWidget {
  const _StopSkeletonList();

  @override
  State<_StopSkeletonList> createState() => _StopSkeletonListState();
}

class _StopSkeletonListState extends State<_StopSkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _opacity = Tween<double>(
      begin: 0.35,
      end: 0.75,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      unawaited(_ctrl.repeat(reverse: true));
    }
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) => Opacity(
        opacity: disableAnimations ? 0.5 : _opacity.value,
        child: child,
      ),
      child: const Column(
        children: [
          _SkeletonTile(),
          _SkeletonTile(),
          _SkeletonTile(),
          _SkeletonTile(),
        ],
      ),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bar = cs.surfaceContainerHighest;
    Widget block(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: bar,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
      ),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          block(48, 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                block(140, 14),
                const SizedBox(height: 6),
                block(80, 10),
              ],
            ),
          ),
          const SizedBox(width: 12),
          block(36, 24),
        ],
      ),
    );
  }
}
