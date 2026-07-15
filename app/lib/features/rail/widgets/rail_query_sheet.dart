import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/storage/hive_store.dart';
import 'package:wheres_the_car/features/rail/bloc/rail_event.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_card.dart';
import 'package:wheres_the_car/shared/widgets/app_date_picker.dart';
import 'package:wheres_the_car/shared/widgets/app_sliding_segment.dart';
import 'package:wheres_the_car/shared/widgets/app_time_picker.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/thsr_station_picker.dart';
import 'package:wheres_the_car/shared/widgets/tra_station_picker.dart';

const List<FontFeature> _tnum = AppTextStyles.tabularFigures;

/// Mode-pane cross-fade duration; ~200 ms sits in the app's short-motion band.
const Duration _kPaneSwitch = Duration(milliseconds: 200);

/// 高鐵品牌橘，僅用於車次晶片上的「高鐵」小標。
const Color _thsrLabelColor = Color(0xFFDB5325);

const Map<int, String> _weekdayMap = {
  DateTime.monday: '一',
  DateTime.tuesday: '二',
  DateTime.wednesday: '三',
  DateTime.thursday: '四',
  DateTime.friday: '五',
  DateTime.saturday: '六',
  DateTime.sunday: '日',
};

String _formatDateDisplay(DateTime date) {
  return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} (${_weekdayMap[date.weekday]})';
}

String _formatTime(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _defaultOrigin(RailSystem system) =>
    system == RailSystem.thsr ? '南港' : '台北';

String _defaultDest(RailSystem system) =>
    system == RailSystem.thsr ? '左營' : '花蓮';

/// Which form the query sheet is showing.
enum RailQueryMode { od, train }

/// Optional seed for the sheet: pre-fills the origin (and, when known, dest and
/// date) so opening from a station detail — or re-opening after a home-sheet
/// hand-off — shows the query that is actually in effect.
class RailQueryPreset {
  const RailQueryPreset({
    required this.system,
    this.originName,
    this.originId,
    this.destName,
    this.destId,
    this.date,
    this.isDeparture = true,
  });

  final RailSystem system;
  final String? originName;
  final String? originId;
  final String? destName;
  final String? destId;
  final DateTime? date;
  final bool isDeparture;
}

/// A completed query, handed back to the host via `onSubmit`.
sealed class RailQuerySubmission {
  const RailQuerySubmission();

  RailSystem get system;
}

final class RailOdQuerySubmission extends RailQuerySubmission {
  const RailOdQuerySubmission({
    required this.system,
    required this.originName,
    required this.destName,
    required this.date,
    required this.isDeparture,
    this.originId,
    this.destId,
  });

  @override
  final RailSystem system;
  final String originName;
  final String? originId;
  final String destName;
  final String? destId;
  // [date] carries the selected time-of-day too; it bounds the results (the
  // backend request itself stays date-only).
  final DateTime date;
  // true: [date]'s time is a "depart at/after"; false: an "arrive at/before".
  final bool isDeparture;
}

final class RailTrainQuerySubmission extends RailQuerySubmission {
  const RailTrainQuerySubmission({
    required this.system,
    required this.trainNo,
    required this.date,
  });

  @override
  final RailSystem system;
  final String trainNo;
  final DateTime date;
}

/// Self-contained rail timetable query form. Owns all form state and works
/// inside both a smooth_sheets `Sheet` (rail screen) and a `PagedSheetRoute`
/// (home sheet); it relies on the enclosing sheet for scroll/drag, so its own
/// list never scrolls.
class RailQuerySheetContent extends StatefulWidget {
  const RailQuerySheetContent({
    required this.onSubmit,
    this.preset,
    this.onSystemChanged,
    this.onBack,
    super.key,
  });

  final RailQueryPreset? preset;
  final ValueChanged<RailQuerySubmission> onSubmit;
  final ValueChanged<RailSystem>? onSystemChanged;

  /// When set, a leading `<` back button shows next to the title. Used in the
  /// home sheet, where this form is a route pushed onto the sheet's nested
  /// navigator and needs a way back to the nearby list; the rail screen omits
  /// it (it has its own top-bar back and must not pop its route from here).
  final VoidCallback? onBack;

  @override
  State<RailQuerySheetContent> createState() => _RailQuerySheetContentState();
}

class _RailQuerySheetContentState extends State<RailQuerySheetContent> {
  RailQueryMode _mode = RailQueryMode.od;
  late RailSystem _system;
  late String _originName;
  String _originId = '';
  late String _destName;
  String _destId = '';
  late DateTime _selectedDate;
  bool _isDepartureTime = true;
  TimeOfDay _selectedTime = TimeOfDay.now();

  final _trainController = TextEditingController();
  List<Map<String, dynamic>> _recentQueries = const [];

  /// True once an O/D query has been submitted this session — swapping O/D then
  /// re-runs the query immediately, matching the old sheet's behaviour.
  bool _hasSubmittedOd = false;

  @override
  void initState() {
    super.initState();
    final preset = widget.preset;
    _system = preset?.system ?? RailSystem.tra;
    _originName = preset?.originName ?? _defaultOrigin(_system);
    _originId = preset?.originId ?? '';
    _destName = preset?.destName ?? _defaultDest(_system);
    // If the preset station is itself the default destination, fall back to the
    // default origin so the O/D pair is real.
    if (_originName == _destName) _destName = _defaultOrigin(_system);
    _destId = preset?.destId ?? '';
    _selectedDate = preset?.date ?? DateTime.now();
    // Seed the time picker from the preset so a re-opened sheet shows the time
    // that produced the current results (the date carries it).
    if (preset?.date != null) {
      _selectedTime = TimeOfDay.fromDateTime(preset!.date!);
    }
    _isDepartureTime = preset?.isDeparture ?? true;
    _recentQueries = HiveStore.recentTrainQueries;
    _trainController.addListener(_onTrainTextChanged);
  }

  @override
  void dispose() {
    _trainController
      ..removeListener(_onTrainTextChanged)
      ..dispose();
    super.dispose();
  }

  void _onTrainTextChanged() => setState(() {});

  void _setMode(RailQueryMode mode) {
    if (mode == _mode) return;
    unawaited(HapticService.instance.lightTap());
    setState(() => _mode = mode);
  }

  void _switchSystem(RailSystem system) {
    if (system == _system) return;
    unawaited(HapticService.instance.lightTap());
    setState(() {
      _system = system;
      _originName = _defaultOrigin(system);
      _destName = _defaultDest(system);
      _originId = '';
      _destId = '';
      _hasSubmittedOd = false;
    });
    widget.onSystemChanged?.call(system);
  }

  void _swap() {
    unawaited(HapticService.instance.lightTap());
    setState(() {
      final tmpName = _originName;
      final tmpId = _originId;
      _originName = _destName;
      _originId = _destId;
      _destName = tmpName;
      _destId = tmpId;
    });
    if (_hasSubmittedOd) _submitOd();
  }

  Future<String?> _showStationPicker() => _system == RailSystem.thsr
      ? showTHSRStationPicker(context)
      : showTRAStationPicker(context);

  Future<void> _pickOrigin() async {
    unawaited(HapticService.instance.lightTap());
    final name = await _showStationPicker();
    if (name != null && mounted) {
      setState(() {
        _originName = name;
        _originId = '';
      });
    }
  }

  Future<void> _pickDest() async {
    unawaited(HapticService.instance.lightTap());
    final name = await _showStationPicker();
    if (name != null && mounted) {
      setState(() {
        _destName = name;
        _destId = '';
      });
    }
  }

  Future<void> _pickDate() async {
    unawaited(HapticService.instance.lightTap());
    final cs = Theme.of(context).colorScheme;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusBottomSheet),
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
                  selectedDay: _selectedDate,
                  onDaySelected: (date) => Navigator.pop(context, date),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  void _submitOd() {
    _hasSubmittedOd = true;
    widget.onSubmit(
      RailOdQuerySubmission(
        system: _system,
        originName: _originName,
        originId: _originId.isEmpty ? null : _originId,
        destName: _destName,
        destId: _destId.isEmpty ? null : _destId,
        // Fold the selected time into the date so it rides every downstream
        // path (results filter, home hand-off) without extra plumbing.
        date: DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          _selectedTime.hour,
          _selectedTime.minute,
        ),
        isDeparture: _isDepartureTime,
      ),
    );
  }

  void _submitTrain() {
    final trainNo = _trainController.text.trim();
    if (trainNo.isEmpty) return;
    unawaited(HapticService.instance.lightTap());
    widget.onSubmit(
      RailTrainQuerySubmission(
        system: _system,
        trainNo: trainNo,
        date: _selectedDate,
      ),
    );
    unawaited(
      HiveStore.addRecentTrainQuery(
        _system == RailSystem.thsr ? 'thsr' : 'tra',
        trainNo,
      ),
    );
    setState(() => _recentQueries = HiveStore.recentTrainQueries);
  }

  void _fillFromRecent(String system, String trainNo) {
    unawaited(HapticService.instance.lightTap());
    final chipSystem = system == 'thsr' ? RailSystem.thsr : RailSystem.tra;
    final systemChanged = chipSystem != _system;
    setState(() {
      _system = chipSystem;
      _trainController.text = trainNo;
    });
    // Only notify on a real switch: the host clears loaded results on system
    // change, which would be gratuitous when the chip matches the current one.
    if (systemChanged) widget.onSystemChanged?.call(chipSystem);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final pane = _mode == RailQueryMode.od
        ? _buildOdPane(cs)
        : _buildTrainPane(cs);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const SheetDragHandle(),
        const SizedBox(height: 8),
        Row(
          children: [
            if (widget.onBack != null)
              Pressable(
                onTap: () {
                  unawaited(HapticService.instance.lightTap());
                  widget.onBack!();
                },
                semanticLabel: '返回',
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    color: cs.onSurface,
                  ),
                ),
              ),
            Text(
              '列車時刻查詢',
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 22,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppSlidingSegment<RailQueryMode>(
          options: const {
            RailQueryMode.od: '起訖查詢',
            RailQueryMode.train: '車次查詢',
          },
          value: _mode,
          onChanged: _setMode,
        ),
        const SizedBox(height: 12),
        AppSlidingSegment<RailSystem>(
          options: const {RailSystem.tra: '台鐵', RailSystem.thsr: '高鐵'},
          value: _system,
          onChanged: _switchSystem,
        ),
        const SizedBox(height: 16),
        if (reduceMotion)
          KeyedSubtree(key: ValueKey(_mode), child: pane)
        else
          AnimatedSize(
            duration: _kPaneSwitch,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: _kPaneSwitch,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              child: KeyedSubtree(key: ValueKey(_mode), child: pane),
            ),
          ),
      ],
    );
  }

  Widget _buildOdPane(ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppCard.outlined(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: _pickOrigin,
                      child: _FieldColumn(
                        label: '起點站',
                        value: _originName,
                        crossAxisAlignment: CrossAxisAlignment.start,
                      ),
                    ),
                  ),
                  Pressable(
                    onTap: _swap,
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
                      onTap: _pickDest,
                      child: _FieldColumn(
                        label: '終點站',
                        value: _destName,
                        crossAxisAlignment: CrossAxisAlignment.end,
                      ),
                    ),
                  ),
                ],
              ),
              _cardDivider(cs),
              Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: _pickDate,
                      child: _FieldColumn(
                        label: '日期',
                        value: _formatDateDisplay(_selectedDate),
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                        if (picked != null && mounted) {
                          setState(() => _selectedTime = picked);
                        }
                      },
                      child: _FieldColumn(
                        label: '時間',
                        value: _formatTime(_selectedTime),
                        crossAxisAlignment: CrossAxisAlignment.end,
                        monospace: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppSlidingSegment<bool>(
          options: const {true: '出發時間', false: '抵達時間'},
          value: _isDepartureTime,
          onChanged: (value) {
            unawaited(HapticService.instance.lightTap());
            setState(() => _isDepartureTime = value);
          },
        ),
        const SizedBox(height: 16),
        _SubmitButton(
          enabled: true,
          onTap: () {
            unawaited(HapticService.instance.lightTap());
            _submitOd();
          },
        ),
      ],
    );
  }

  Widget _buildTrainPane(ColorScheme cs) {
    final trainNoEntered = _trainController.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard.outlined(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '車次號碼',
                style: AppTextStyles.bodyVerySmall.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _trainController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: AppTextStyles.memo.copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  fontFeatures: _tnum,
                  color: cs.onSurface,
                ),
                cursorColor: cs.primary,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: '例:152',
                  hintStyle: AppTextStyles.memo.copyWith(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    fontFeatures: _tnum,
                    color: cs.outline,
                  ),
                ),
              ),
              _cardDivider(cs),
              Pressable(
                onTap: _pickDate,
                child: _FieldColumn(
                  label: '日期',
                  value: _formatDateDisplay(_selectedDate),
                  crossAxisAlignment: CrossAxisAlignment.start,
                ),
              ),
            ],
          ),
        ),
        if (_recentQueries.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '最近查詢',
            style: AppTextStyles.bodyVerySmall.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final query in _recentQueries)
                _RecentTrainChip(
                  system: (query['system'] as String?) ?? 'tra',
                  trainNo: (query['trainNo'] as String?) ?? '',
                  onTap: _fillFromRecent,
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _SubmitButton(enabled: trainNoEntered, onTap: _submitTrain),
      ],
    );
  }

  Widget _cardDivider(ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Divider(
      color: cs.outlineVariant.withValues(alpha: 0.4),
      height: 1,
    ),
  );
}

class _FieldColumn extends StatelessWidget {
  const _FieldColumn({
    required this.label,
    required this.value,
    required this.crossAxisAlignment,
    this.monospace = false,
  });

  final String label;
  final String value;
  final CrossAxisAlignment crossAxisAlignment;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyVerySmall.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: cs.onSurface,
            fontFeatures: monospace ? _tnum : null,
          ),
        ),
      ],
    );
  }
}

class _RecentTrainChip extends StatelessWidget {
  const _RecentTrainChip({
    required this.system,
    required this.trainNo,
    required this.onTap,
  });

  final String system;
  final String trainNo;
  final void Function(String system, String trainNo) onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isThsr = system == 'thsr';
    return Pressable(
      onTap: () => onTap(system, trainNo),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(AppTheme.radiusStadium),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isThsr ? '高鐵' : '台鐵',
              style: AppTextStyles.bodySmall.copyWith(
                color: isThsr ? _thsrLabelColor : cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              trainNo,
              style: AppTextStyles.memo.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
                fontFeatures: _tnum,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: enabled ? onTap : null,
      semanticLabel: '查詢',
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: enabled ? cs.primary : cs.outline,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          '查詢',
          style: TextStyle(
            color: enabled ? cs.onPrimary : cs.surface,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
