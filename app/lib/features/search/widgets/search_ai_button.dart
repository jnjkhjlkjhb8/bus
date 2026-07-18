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
    duration: AppMotion.medium,
  );
  bool _pressed = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    unawaited(HapticService.instance.selectionClick());
    if (!AppMotion.reduced(context)) unawaited(_c.forward(from: 0));
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = AppMotion.reduced(context);
    return Semantics(
      button: true,
      label: '對話框',
      child: GestureDetector(
        onTap: _handleTap,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? AppMotion.pressedScale : 1,
          duration: reduceMotion ? Duration.zero : AppMotion.press,
          curve: AppMotion.easeOut,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final t = reduceMotion
                  ? 1.0
                  : AppMotion.easeOut.transform(_c.value);
              final pop = reduceMotion ? 0.0 : 1 - (2 * t - 1).abs();
              return SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (!reduceMotion)
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
                      child: reduceMotion
                          ? child
                          : Transform.rotate(angle: t * 0.6, child: child),
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
      ),
    );
  }
}
