part of '../view/metro_screen.dart';

/// Floating time/fare toggle mirroring the system pill's card styling. Drives
/// [_MapMode], which controls the labels shown on every station across the map.
class _MapModeChip extends StatelessWidget {
  const _MapModeChip({
    required this.mode,
    required this.onChanged,
    super.key,
  });

  final _MapMode mode;
  final ValueChanged<_MapMode> onChanged;

  static const _labels = <_MapMode, String>{
    _MapMode.time: '時間',
    _MapMode.fare: '票價',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: AppTheme.floatingControl(
        cs,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in _labels.entries)
            _segment(cs, reduceMotion, entry.key, entry.value),
        ],
      ),
    );
  }

  Widget _segment(
    ColorScheme cs,
    bool reduceMotion,
    _MapMode value,
    String label,
  ) {
    final selected = value == mode;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : AppMotion.medium,
          curve: AppMotion.easeOut,
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? cs.onSurface : Colors.transparent,
            borderRadius: const BorderRadius.all(Radius.circular(999)),
          ),
          child: AnimatedDefaultTextStyle(
            duration: reduceMotion ? Duration.zero : AppMotion.medium,
            curve: AppMotion.easeOut,
            style: AppTextStyles.bodyRegular.copyWith(
              fontWeight: FontWeight.w600,
              color: selected ? cs.surface : cs.onSurfaceVariant,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

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
          AppSnackbar.show(context, '$value 尚未支援');
        }
      }),
    );
  }
}
