part of '../view/search_screen.dart';

class _AiButton extends StatefulWidget {
  const _AiButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AiButton> createState() => _AiButtonState();
}

class _AiButtonState extends State<_AiButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _handleTap() {
    unawaited(HapticService.instance.selectionClick());
    unawaited(_c.forward(from: 0));
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '對話框',
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final t = AppMotion.easeOut.transform(_c.value);
            final pop = 1 - (2 * t - 1).abs();
            return SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Opacity(
                    opacity: (1 - t) * 0.5,
                    child: Container(
                      width: 40 + 24 * t,
                      height: 40 + 24 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.primary, width: 1.5),
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 1 + 0.18 * pop,
                    child: Transform.rotate(angle: t * 0.6, child: child),
                  ),
                ],
              ),
            );
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primary, cs.tertiary],
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.32),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 19,
              color: cs.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
