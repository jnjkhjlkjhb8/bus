part of '../view/metro_screen.dart';

class _SystemPill extends StatefulWidget {
  const _SystemPill();

  @override
  State<_SystemPill> createState() => _SystemPillState();
}

class _SystemPillState extends State<_SystemPill> {
  static const _others = ['高雄捷運', '桃園機捷', '高雄輕軌'];
  bool _isPickerOpen = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surface = cs.brightness == Brightness.light
        ? Colors.white
        : cs.surfaceContainerHigh;
    return Semantics(
      label: '切換捷運系統',
      button: true,
      child: GestureDetector(
        onTap: () => _showPicker(context),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            boxShadow: AppShadows.floating,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Text(
                '台北捷運',
                style: AppTextStyles.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              AnimatedRotation(
                turns: _isPickerOpen ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final box = context.findRenderObject()! as RenderBox;
    final pos = box.localToGlobal(Offset.zero);

    setState(() => _isPickerOpen = true);

    unawaited(
      showMenu<String>(
        context: context,
        color: cs.surfaceContainerLow,
        constraints: BoxConstraints(
          minWidth: box.size.width,
          maxWidth: box.size.width,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        position: RelativeRect.fromLTRB(
          pos.dx,
          pos.dy + box.size.height + 4,
          pos.dx + box.size.width,
          0,
        ),
        items: _others
            .map(
              (s) => PopupMenuItem(
                value: s,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  s,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
            .toList(),
      ).then((value) {
        if (mounted) {
          setState(() => _isPickerOpen = false);
        }
        if (value != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$value 尚未支援'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }),
    );
  }
}
