part of '../view/go_screen.dart';

class _PlannerHeader extends StatelessWidget {
  const _PlannerHeader({
    required this.origin,
    required this.dest,
    required this.onBack,
    required this.onEditOrigin,
    required this.onEditDest,
    required this.onSwap,
  });

  final PlannedPlace? origin;
  final PlannedPlace? dest;
  final VoidCallback onBack;
  final VoidCallback onEditOrigin;
  final VoidCallback onEditDest;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppBarCircleButton(
          onTap: onBack,
          semanticLabel: '返回',
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: cs.brightness == Brightness.light
                  ? Colors.white
                  : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              boxShadow: AppShadows.floating,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.radio_button_checked_rounded,
                      size: 13,
                      color: cs.outline,
                    ),
                    Container(width: 1.5, height: 18, color: cs.outlineVariant),
                    Icon(
                      Icons.location_on_rounded,
                      size: 16,
                      color: cs.primary,
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FieldRow(
                        place: origin,
                        hint: '選擇出發地',
                        onTap: onEditOrigin,
                      ),
                      Divider(height: 1, color: cs.outlineVariant),
                      _FieldRow(
                        place: dest,
                        hint: '選擇目的地',
                        onTap: onEditDest,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Pressable(
                  onTap: onSwap,
                  semanticLabel: '對調起訖點',
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.swap_vert_rounded,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.place,
    required this.hint,
    required this.onTap,
  });

  final PlannedPlace? place;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filled = place != null;
    return Pressable(
      onTap: onTap,
      semanticLabel: filled ? place!.name : hint,
      child: SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  filled ? place!.name : hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: filled ? cs.onSurface : cs.onSurfaceVariant,
                    fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (filled && place!.isCurrentLocation)
                Icon(Icons.my_location_rounded, size: 16, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlannerSheet extends StatelessWidget {
  const _PlannerSheet({
    required this.controller,
    required this.state,
    required this.hasDestination,
    required this.onSelect,
    required this.onRetry,
    required this.onPickDestination,
    required this.onAdjustOptions,
  });

  final SheetController controller;
  final PlanState state;
  final bool hasDestination;
  final void Function(PlanRoute) onSelect;
  final VoidCallback onRetry;
  final VoidCallback onPickDestination;
  final VoidCallback onAdjustOptions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SheetViewport(
      child: SheetExitGestureDetector(
        onExit: () => context.pop(),
        child: Sheet(
          controller: controller,
          initialOffset: const SheetOffset.proportionalToViewport(0.5),
          snapGrid: const SheetSnapGrid(
            snaps: [
              SheetOffset.proportionalToViewport(0.28),
              SheetOffset.proportionalToViewport(0.5),
              SheetOffset.proportionalToViewport(1),
            ],
          ),
          scrollConfiguration: const SheetScrollConfiguration(),
          decoration: MaterialSheetDecoration(
            size: SheetSize.stretch,
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusBottomSheet),
            ),
            clipBehavior: Clip.antiAlias,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetDragHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Row(
                  children: [
                    Expanded(child: _SheetTitle(state: state)),
                    _OptionsButton(onTap: onAdjustOptions),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(
                child: _PlannerBody(
                  state: state,
                  hasDestination: hasDestination,
                  onSelect: onSelect,
                  onRetry: onRetry,
                  onPickDestination: onPickDestination,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.state});

  final PlanState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = state.result?.routes.length ?? 0;
    final now = TimeOfDay.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final sub = state.status == PlanStatus.success && count > 0
        ? '$count 個建議 · 出發 ${two(now.hour)}:${two(now.minute)}'
        : '出發：現在';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '建議路線',
          style: AppTextStyles.heading2.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 3),
        Text(
          sub,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _PlannerBody extends StatelessWidget {
  const _PlannerBody({
    required this.state,
    required this.hasDestination,
    required this.onSelect,
    required this.onRetry,
    required this.onPickDestination,
  });

  final PlanState state;
  final bool hasDestination;
  final void Function(PlanRoute) onSelect;
  final VoidCallback onRetry;
  final VoidCallback onPickDestination;

  @override
  Widget build(BuildContext context) {
    if (!hasDestination && state.status == PlanStatus.initial) {
      return _GoMessage(
        icon: Icons.flag_outlined,
        title: '選擇目的地開始規劃',
        hint: '搜尋地點或站名，為你找出最快路線',
        actionLabel: '選擇目的地',
        onAction: onPickDestination,
      );
    }
    switch (state.status) {
      case PlanStatus.initial:
      case PlanStatus.loading:
        return const _RouteSkeleton();
      case PlanStatus.failure:
        return _GoMessage(
          icon: Icons.cloud_off_rounded,
          title: '無法取得路線',
          hint: '請確認網路後再試一次',
          actionLabel: '重試',
          onAction: onRetry,
        );
      case PlanStatus.success:
        final routes = state.result?.routes ?? const <PlanRoute>[];
        if (routes.isEmpty) {
          return const _GoMessage(
            icon: Icons.alt_route_rounded,
            title: '找不到合適路線',
            hint: '試試調整出發地或目的地',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: routes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => RouteOptionCard(
            route: routes[i],
            highlighted: i == 0,
            badge: i == 0 ? '最快' : null,
            onTap: () => onSelect(routes[i]),
          ),
        );
    }
  }
}

class _RouteSkeleton extends StatelessWidget {
  const _RouteSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(72, 22),
                const SizedBox(height: 12),
                bar(200, 16),
                const SizedBox(height: 10),
                bar(120, 12),
              ],
            ),
          ),
      ],
    );
  }
}

/// Trailing control in the sheet header. Opens the routing-options sheet.
class _OptionsButton extends StatelessWidget {
  const _OptionsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: '路線選項',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 18, color: cs.onSurface),
            const SizedBox(width: 6),
            Text(
              '選項',
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// TDX transit-mode ids the planner exposes (excludes 20:航空).
const _kTransitModes = <int, String>{
  3: '高鐵',
  4: '台鐵',
  5: '公車',
  6: '捷運',
  7: '輕軌',
  8: '渡輪',
  9: '纜車',
};
// TDX first/last-mile mode ids.
const _kMileModes = <int, String>{0: '走路', 1: '腳踏車', 2: '開車', 3: '共享單車'};

/// Options sheet for all TDX MaaS routing parameters. Returns the edited
/// [PlanOptions] on 套用, or null on dismiss.
Future<PlanOptions?> showOptionsSheet(
  BuildContext context, {
  required PlanOptions current,
}) {
  return showModalBottomSheet<PlanOptions>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OptionsSheet(initial: current),
  );
}

class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({required this.initial});

  final PlanOptions initial;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late PlanOptions _o = widget.initial;

  void _toggleMode(int id) {
    final modes = _o.transitModes.toList();
    if (modes.contains(id)) {
      if (modes.length == 1) return; // keep at least one mode selected
      modes.remove(id);
    } else {
      modes.add(id);
    }
    modes.sort();
    setState(() => _o = _o.copyWith(transitModes: modes));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusBottomSheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '路線選項',
                  style: AppTextStyles.heading2.copyWith(color: cs.onSurface),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                children: [
                  _sectionRow(
                    '時間 / 價格偏好',
                    'gc ${_o.gc.toStringAsFixed(1)}',
                    cs,
                  ),
                  AppSlider(
                    value: _o.gc,
                    divisions: 10,
                    onChanged: (v) => setState(() => _o = _o.copyWith(gc: v)),
                  ),
                  _endLabels('省錢', '省時', cs),
                  const SizedBox(height: 12),
                  _rowControl(
                    '路線數量',
                    AppQuantitySelector(
                      value: _o.top,
                      min: 1,
                      max: 10,
                      onChanged: (v) =>
                          setState(() => _o = _o.copyWith(top: v)),
                    ),
                    cs,
                  ),
                  const SizedBox(height: 12),
                  _sectionRow('搭乘運具', '', cs),
                  const SizedBox(height: 8),
                  FilterChipGroup<int>(
                    options: _kTransitModes,
                    selected: _o.transitModes.toSet(),
                    onToggle: _toggleMode,
                  ),
                  const SizedBox(height: 16),
                  _sectionRow(
                    '轉乘時間',
                    '${_o.transferMin} - ${_o.transferMax} 分',
                    cs,
                  ),
                  const SizedBox(height: 8),
                  _rowControl(
                    '最短（分鐘）',
                    AppQuantitySelector(
                      value: _o.transferMin,
                      max: 60,
                      onChanged: (v) => setState(
                        () => _o = _o.copyWith(
                          transferMin: v > _o.transferMax ? _o.transferMax : v,
                        ),
                      ),
                    ),
                    cs,
                  ),
                  _rowControl(
                    '最長（分鐘）',
                    AppQuantitySelector(
                      value: _o.transferMax,
                      max: 60,
                      onChanged: (v) => setState(
                        () => _o = _o.copyWith(
                          transferMax: v < _o.transferMin ? _o.transferMin : v,
                        ),
                      ),
                    ),
                    cs,
                  ),
                  const SizedBox(height: 12),
                  _mileSection(
                    '第一哩路（分鐘）',
                    _o.firstMileMode,
                    _o.firstMileTime,
                    (m) => setState(() => _o = _o.copyWith(firstMileMode: m)),
                    (t) => setState(() => _o = _o.copyWith(firstMileTime: t)),
                    cs,
                  ),
                  const SizedBox(height: 12),
                  _mileSection(
                    '最後一哩路（分鐘）',
                    _o.lastMileMode,
                    _o.lastMileTime,
                    (m) => setState(() => _o = _o.copyWith(lastMileMode: m)),
                    (t) => setState(() => _o = _o.copyWith(lastMileTime: t)),
                    cs,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: '套用',
                  onPressed: () => Navigator.of(context).pop(_o),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionRow(String title, String value, ColorScheme cs) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: AppTextStyles.bodyLarge.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (value.isNotEmpty)
        Text(
          value,
          style: AppTextStyles.bodySmall.copyWith(
            color: cs.onSurfaceVariant,
            fontFeatures: AppTextStyles.tabularFigures,
          ),
        ),
    ],
  );

  Widget _rowControl(String title, Widget control, ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.bodyLarge.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        control,
      ],
    ),
  );

  Widget _endLabels(String left, String right, ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          left,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
        Text(
          right,
          style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    ),
  );

  Widget _mileSection(
    String title,
    int mode,
    int time,
    ValueChanged<int> onMode,
    ValueChanged<int> onTime,
    ColorScheme cs,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _rowControl(
        title,
        AppQuantitySelector(
          value: time,
          min: 1,
          max: 60,
          onChanged: onTime,
        ),
        cs,
      ),
      const SizedBox(height: 8),
      FilterChipGroup<int>(
        options: _kMileModes,
        selected: {mode},
        onToggle: onMode,
      ),
    ],
  );
}

class _GoMessage extends StatelessWidget {
  const _GoMessage({
    required this.icon,
    required this.title,
    required this.hint,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              Pressable(
                onTap: onAction,
                semanticLabel: actionLabel,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  ),
                  child: Text(
                    actionLabel!,
                    style: AppTextStyles.bodyRegular.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
