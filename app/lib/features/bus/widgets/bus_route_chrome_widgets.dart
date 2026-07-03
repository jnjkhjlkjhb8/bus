part of '../view/bus_route_screen.dart';

class _FloatingAppBar extends StatelessWidget {
  const _FloatingAppBar({
    required this.subRouteUid,
    required this.routeName,
    required this.dirName,
    required this.direction,
    required this.onBookmarkTapped,
  });
  final String subRouteUid;
  final String routeName;
  final String dirName;
  final int direction;
  final VoidCallback onBookmarkTapped;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            AppBarCircleButton(
              onTap: () {
                unawaited(HapticService.instance.lightTap());
                context.pop();
              },
              semanticLabel: '返回',
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RoutePill(
                routeName: routeName,
                dirName: dirName,
                direction: direction,
              ),
            ),
            const SizedBox(width: 12),
            AppBarCircleButton(
              semanticLabel: '收藏',
              onTap: onBookmarkTapped,
              child: BookmarkButton(
                routeType: 'bus',
                routeKey: subRouteUid,
                routeLabel: routeName,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePill extends StatelessWidget {
  const _RoutePill({
    required this.routeName,
    required this.dirName,
    required this.direction,
  });
  final String routeName;
  final String dirName;
  final int direction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.brightness == Brightness.light
            ? Colors.white
            : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppShadows.floating,
      ),
      child: Row(
        spacing: 6,
        children: [
          Text(
            routeName,
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: AppMotion.short,
              switchInCurve: AppMotion.easeOut,
              switchOutCurve: AppMotion.easeOut,
              transitionBuilder: (child, animation) {
                final isIncoming =
                    animation.status == AnimationStatus.forward ||
                    animation.status == AnimationStatus.completed;

                final beginOffset = direction == 1
                    ? (isIncoming ? const Offset(0, 1) : const Offset(0, -1))
                    : (isIncoming ? const Offset(0, -1) : const Offset(0, 1));

                return ClipRect(
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: beginOffset,
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  ),
                );
              },
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    ...previousChildren,
                    ?currentChild,
                  ],
                );
              },
              child: Text(
                dirName,
                key: ValueKey(dirName),
                style: AppTextStyles.bodyRegular.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
