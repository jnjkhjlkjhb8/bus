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
  });

  final SheetController controller;
  final PlanState state;
  final bool hasDestination;
  final void Function(PlanRoute) onSelect;
  final VoidCallback onRetry;
  final VoidCallback onPickDestination;

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
                child: _SheetTitle(state: state),
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
