part of '../view/go_screen.dart';

class _PlannerHeader extends StatelessWidget {
  const _PlannerHeader({
    required this.origin,
    required this.dest,
    required this.onEditOrigin,
    required this.onEditDest,
    required this.onSwap,
  });

  final PlannedPlace? origin;
  final PlannedPlace? dest;
  final VoidCallback onEditOrigin;
  final VoidCallback onEditDest;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                      const DividerLine(),
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
    required this.initialOffset,
    required this.state,
    required this.hasDestination,
    required this.timeMode,
    required this.timeAt,
    required this.onSelect,
    required this.onRetry,
    required this.onAdjustOptions,
    required this.onAdjustTime,
    required this.onToggleSave,
    super.key,
  });

  final SheetController controller;
  final SheetOffset initialOffset;
  final PlanState state;
  final bool hasDestination;
  final _TimeMode timeMode;
  final DateTime timeAt;
  final void Function(PlanRoute) onSelect;
  final VoidCallback onRetry;
  final VoidCallback onAdjustOptions;
  final VoidCallback onAdjustTime;
  final void Function(PlanRoute) onToggleSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SheetViewport(
      child: SheetExitGestureDetector(
        onExit: () => context.pop(),
        child: Sheet(
          controller: controller,
          initialOffset: initialOffset,
          snapGrid: AppSheetSnap.grid,
          scrollConfiguration: const SheetScrollConfiguration(),
          decoration: MaterialSheetDecoration(
            size: SheetSize.stretch,
            color: cs.surfaceContainerLow,
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
                    // The depart/arrive time chip only makes sense once a
                    // destination has been queried; the saved-routes box has no
                    // time context.
                    if (hasDestination) ...[
                      _TimeChip(
                        mode: timeMode,
                        at: timeAt,
                        onTap: onAdjustTime,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _OptionsButton(onTap: onAdjustOptions),
                  ],
                ),
              ),
              const DividerLine(),
              Expanded(
                child: _PlannerBody(
                  state: state,
                  onSelect: onSelect,
                  onRetry: onRetry,
                  onToggleSave: onToggleSave,
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
    // The departure time now lives in the header time chip, so the subtitle
    // just reports the result count.
    final sub = state.status == PlanStatus.success && count > 0
        ? '$count 個建議'
        : '規劃中';
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
    required this.onSelect,
    required this.onRetry,
    required this.onToggleSave,
  });

  final PlanState state;
  final void Function(PlanRoute) onSelect;
  final VoidCallback onRetry;
  final void Function(PlanRoute) onToggleSave;

  @override
  Widget build(BuildContext context) {
    // The empty/saved-routes state now lives on the plan-entry page; this body
    // is only built once a destination exists, so it starts at the query state.
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
            isSaved: state.savedKeys.contains(routes[i].savedKey),
            onTap: () => onSelect(routes[i]),
            onToggleSave: () => onToggleSave(routes[i]),
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

/// Names the stance the cost/time weight currently expresses. The weight is a
/// solver input with no meaning to a rider, so the readout reports the choice
/// the slider's end labels promise instead of the raw number.
String _gcLabel(double gc) => switch (gc) {
  <= 0.1 => '省錢',
  < 0.4 => '偏省錢',
  <= 0.6 => '平衡',
  < 0.9 => '偏省時',
  _ => '省時',
};

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
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
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
                  _sectionRow('時間 / 價格偏好', _gcLabel(_o.gc), cs),
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
                  AppRangeSlider(
                    values: RangeValues(
                      _o.transferMin.toDouble(),
                      _o.transferMax.toDouble(),
                    ),
                    max: 60,
                    divisions: 12,
                    onChanged: (v) => setState(
                      () => _o = _o.copyWith(
                        transferMin: v.start.round(),
                        transferMax: v.end.round(),
                      ),
                    ),
                  ),
                  _endLabels('0 分', '60 分', cs),
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

/// Plan-entry phase: the map-less landing surface. Origin/destination fields on
/// top (each opens the search page), a shared shortcut list below (current
/// location, saved places, recent searches) filling the screen. Picking a
/// shortcut sets the destination and starts planning.
class _PlannerEntry extends StatelessWidget {
  const _PlannerEntry({
    required this.origin,
    required this.dest,
    required this.savedRoutes,
    required this.onEditOrigin,
    required this.onEditDest,
    required this.onSwap,
    required this.onPickDestination,
    required this.onOpenSaved,
    required this.onToggleSave,
    required this.onBack,
    super.key,
  });

  final PlannedPlace? origin;
  final PlannedPlace? dest;
  final List<PlanRoute> savedRoutes;
  final VoidCallback onEditOrigin;
  final VoidCallback onEditDest;
  final VoidCallback onSwap;
  final ValueChanged<PlannedPlace> onPickDestination;
  final void Function(PlanRoute) onOpenSaved;
  final void Function(PlanRoute) onToggleSave;
  final VoidCallback onBack;

  // 路線箱: the saved-route cards, shown below the shortcut list when the user
  // has any. Kept out of PlaceSearchView (which only knows places) by passing
  // it in as the list footer.
  Widget? _savedRoutesFooter(BuildContext context) {
    if (savedRoutes.isEmpty) return null;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 8, color: cs.surfaceContainerHigh),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(
            '路線箱',
            style: AppTextStyles.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            children: [
              for (final route in savedRoutes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RouteOptionCard(
                    route: route,
                    highlighted: false,
                    isSaved: true,
                    onTap: () => onOpenSaved(route),
                    onToggleSave: () => onToggleSave(route),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Pressable(
                    onTap: onBack,
                    semanticLabel: '返回',
                    child: SizedBox(
                      width: 40,
                      height: 52,
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 22,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _PlannerHeader(
                      origin: origin,
                      dest: dest,
                      onEditOrigin: onEditOrigin,
                      onEditDest: onEditDest,
                      onSwap: onSwap,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: PlaceSearchView(
              emptyHint: '搜尋地點，為你規劃最快路線',
              footer: _savedRoutesFooter(context),
              onPicked: onPickDestination,
            ),
          ),
        ],
      ),
    );
  }
}

/// Results-header chip that reads out the current departure/arrival stance and
/// opens the time selector.
class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.mode, required this.at, required this.onTap});

  final _TimeMode mode;
  final DateTime at;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${two(at.month)}/${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
    final suffix = switch (mode) {
      _TimeMode.leaveNow => null,
      _TimeMode.departAt => ' 出發',
      _TimeMode.arriveBy => ' 抵達',
    };
    final sansStyle = AppTextStyles.bodySmall.copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w600,
    );
    return Pressable(
      onTap: onTap,
      semanticLabel: '選擇出發時間',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 16, color: cs.onSurface),
            const SizedBox(width: 6),
            if (suffix == null)
              Text('立即出發', style: sansStyle)
            else ...[
              Text(
                stamp,
                style: AppTextStyles.memo.copyWith(
                  fontSize: sansStyle.fontSize,
                  fontWeight: sansStyle.fontWeight,
                  color: sansStyle.color,
                  fontFeatures: AppTextStyles.tabularFigures,
                ),
              ),
              Text(suffix, style: sansStyle),
            ],
          ],
        ),
      ),
    );
  }
}

const _weekdayLabels = <int, String>{
  DateTime.monday: '一',
  DateTime.tuesday: '二',
  DateTime.wednesday: '三',
  DateTime.thursday: '四',
  DateTime.friday: '五',
  DateTime.saturday: '六',
  DateTime.sunday: '日',
};

/// Departure/arrival time selector, mirroring the rail query's
/// date + time + stance idiom. Returns the chosen `(mode, at)` on 套用, or null
/// on dismiss.
Future<({_TimeMode mode, DateTime at})?> _showTimeModeSheet(
  BuildContext context, {
  required _TimeMode mode,
  required DateTime at,
}) {
  return showModalBottomSheet<({_TimeMode mode, DateTime at})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TimeModeSheet(mode: mode, at: at),
  );
}

class _TimeModeSheet extends StatefulWidget {
  const _TimeModeSheet({required this.mode, required this.at});

  final _TimeMode mode;
  final DateTime at;

  @override
  State<_TimeModeSheet> createState() => _TimeModeSheetState();
}

class _TimeModeSheetState extends State<_TimeModeSheet> {
  late _TimeMode _mode = widget.mode;
  late DateTime _at = widget.at;

  Future<void> _pickDate() async {
    final cs = Theme.of(context).colorScheme;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusBottomSheet),
        ),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetDragHandle(),
              const SizedBox(height: 8),
              AppDatePicker(
                selectedDay: _at,
                onDaySelected: (date) => Navigator.pop(context, date),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      // Preserve the chosen time-of-day when only the date changes.
      setState(() {
        _at = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _at.hour,
          _at.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await AppTimePicker.show(
      context,
      TimeOfDay(hour: _at.hour, minute: _at.minute),
    );
    if (picked != null && mounted) {
      setState(() {
        _at = DateTime(
          _at.year,
          _at.month,
          _at.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String two(int v) => v.toString().padLeft(2, '0');
    final timed = _mode != _TimeMode.leaveNow;
    return Container(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetDragHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                '出發時間',
                style: AppTextStyles.heading2.copyWith(color: cs.onSurface),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AppSegmentedControl<_TimeMode>(
                options: const {
                  _TimeMode.leaveNow: '立即出發',
                  _TimeMode.departAt: '出發時間',
                  _TimeMode.arriveBy: '抵達時間',
                },
                value: _mode,
                onChanged: (v) {
                  unawaited(HapticService.instance.lightTap());
                  setState(() => _mode = v);
                },
              ),
            ),
            if (timed) ...[
              const SizedBox(height: 8),
              _TimeRow(
                icon: Icons.event_rounded,
                label: '日期',
                value:
                    '${two(_at.month)}/${two(_at.day)}'
                    '（${_weekdayLabels[_at.weekday]}）',
                onTap: _pickDate,
              ),
              _TimeRow(
                icon: Icons.schedule_rounded,
                label: '時間',
                value: '${two(_at.hour)}:${two(_at.minute)}',
                onTap: _pickTime,
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: '套用',
                  onPressed: () =>
                      Navigator.of(context).pop((mode: _mode, at: _at)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      semanticLabel: '$label $value',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTextStyles.bodyLarge.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              ),
              child: Text(
                value,
                style: AppTextStyles.memo.copyWith(color: cs.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
