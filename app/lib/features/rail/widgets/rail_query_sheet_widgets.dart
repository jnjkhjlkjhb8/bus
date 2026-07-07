part of '../view/rail_screen.dart';

class _QuerySheetContent extends StatefulWidget {
  const _QuerySheetContent({
    required this.system,
    required this.origin,
    required this.destination,
    required this.selectedDate,
    required this.onSystemChanged,
    required this.onSwap,
    required this.onOriginTap,
    required this.onDestTap,
    required this.onDateChanged,
    required this.onSearch,
  });

  final RailSystem system;
  final String origin;
  final String destination;
  final DateTime selectedDate;
  final ValueChanged<RailSystem> onSystemChanged;
  final VoidCallback onSwap;
  final VoidCallback onOriginTap;
  final VoidCallback onDestTap;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback onSearch;

  @override
  State<_QuerySheetContent> createState() => _QuerySheetContentState();
}

class _QuerySheetContentState extends State<_QuerySheetContent> {
  bool _isDepartureTime = true;
  TimeOfDay _selectedTime = TimeOfDay.now();

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const SheetDragHandle(),
        const SizedBox(height: 8),

        Text(
          '列車時刻查詢',
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 22,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 16),

        AppSlidingSegment<RailSystem>(
          options: const {RailSystem.tra: '台鐵', RailSystem.thsr: '高鐵'},
          value: widget.system,
          onChanged: widget.onSystemChanged,
        ),
        const SizedBox(height: 16),

        AppCard.outlined(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: widget.onOriginTap,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '起點站',
                            style: AppTextStyles.bodyVerySmall.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.origin,
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Pressable(
                    onTap: widget.onSwap,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.swap_horiz_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Pressable(
                      onTap: widget.onDestTap,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '終點站',
                            style: AppTextStyles.bodyVerySmall.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.destination,
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  height: 1,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: () async {
                        unawaited(HapticService.instance.lightTap());
                        final picked =
                            await showModalBottomSheet<DateTime>(
                              context: context,
                              backgroundColor: cs.surface,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(
                                    AppTheme.radiusBottomSheet,
                                  ),
                                ),
                              ),
                              builder: (context) {
                                return SafeArea(
                                  top: false,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SheetDragHandle(),
                                        const SizedBox(height: 8),
                                        AppDatePicker(
                                          selectedDay: widget.selectedDate,
                                          onDaySelected: (date) {
                                            Navigator.pop(context, date);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                        if (picked != null) {
                          widget.onDateChanged(picked);
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '日期',
                            style: AppTextStyles.bodyVerySmall.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatDateDisplay(widget.selectedDate),
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Pressable(
                      onTap: () async {
                        unawaited(HapticService.instance.lightTap());
                        final picked = await AppTimePicker.show(
                          context,
                          _selectedTime,
                        );
                        if (picked != null) {
                          setState(() {
                            _selectedTime = picked;
                          });
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '時間',
                            style: AppTextStyles.bodyVerySmall.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatTime(_selectedTime),
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: cs.onSurface,
                              fontFeatures: _tnum,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Container(
          height: 40,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth / 2;
                  return AnimatedAlign(
                    alignment: _isDepartureTime
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOutCubic,
                    child: Container(
                      width: width,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: cs.brightness == Brightness.light
                            ? Colors.white
                            : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: AppShadows.floating,
                      ),
                    ),
                  );
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        unawaited(HapticService.instance.lightTap());
                        setState(() {
                          _isDepartureTime = true;
                        });
                      },
                      child: Center(
                        child: Text(
                          '出發時間',
                          style: TextStyle(
                            color: _isDepartureTime
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                            fontWeight: _isDepartureTime
                                ? FontWeight.w600
                                : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        unawaited(HapticService.instance.lightTap());
                        setState(() {
                          _isDepartureTime = false;
                        });
                      },
                      child: Center(
                        child: Text(
                          '抵達時間',
                          style: TextStyle(
                            color: !_isDepartureTime
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                            fontWeight: !_isDepartureTime
                                ? FontWeight.w600
                                : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Pressable(
          onTap: widget.onSearch,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '查詢',
              style: TextStyle(
                color: cs.onPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
