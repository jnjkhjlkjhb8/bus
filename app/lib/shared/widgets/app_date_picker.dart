import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';

class AppDatePicker extends StatelessWidget {
  const AppDatePicker({
    required this.selectedDay,
    required this.onDaySelected,
    super.key,
  });

  final DateTime? selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final focused = selectedDay ?? now;
    return TableCalendar<Object>(
      firstDay: DateTime(now.year - 1),
      lastDay: DateTime(now.year + 1),
      focusedDay: focused,
      availableCalendarFormats: const {CalendarFormat.month: ''},
      selectedDayPredicate: (d) =>
          selectedDay != null && isSameDay(d, selectedDay),
      onDaySelected: (selected, _) => onDaySelected(selected),
      calendarStyle: CalendarStyle(
        selectedDecoration: BoxDecoration(
          color: cs.primary,
          shape: BoxShape.circle,
        ),
        selectedTextStyle: AppTextStyles.bodySmall.copyWith(
          color: cs.onPrimary,
        ),
        todayDecoration: BoxDecoration(
          color: cs.primaryContainer,
          shape: BoxShape.circle,
        ),
        todayTextStyle: AppTextStyles.bodySmall.copyWith(
          color: cs.onPrimaryContainer,
        ),
        defaultTextStyle: AppTextStyles.bodySmall,
        weekendTextStyle: AppTextStyles.bodySmall.copyWith(color: cs.error),
        outsideTextStyle: AppTextStyles.bodySmall.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: AppTextStyles.bodyRegular.copyWith(
          fontWeight: FontWeight.w600,
        ),
        leftChevronIcon: Icon(Icons.chevron_left_rounded, color: cs.onSurface),
        rightChevronIcon: Icon(
          Icons.chevron_right_rounded,
          color: cs.onSurface,
        ),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: AppTextStyles.bodySmall.copyWith(
          color: cs.onSurfaceVariant,
        ),
        weekendStyle: AppTextStyles.bodySmall.copyWith(color: cs.error),
      ),
    );
  }
}
