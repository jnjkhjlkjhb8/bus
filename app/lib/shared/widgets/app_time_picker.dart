import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/shared/widgets/app_button.dart';

class AppTimePicker {
  AppTimePicker._();

  static Future<TimeOfDay?> show(
    BuildContext context,
    TimeOfDay initial,
  ) async {
    var picked = initial;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusBottomSheet),
        ),
      ),
      builder: (ctx) {
        final now = DateTime.now();
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AppButton.text(
                      label: '取消',
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                    const Text('選擇時間', style: AppTextStyles.heading2),
                    AppButton.text(
                      label: '完成',
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
                SizedBox(
                  height: 216,
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: true,
                    initialDateTime: DateTime(
                      now.year,
                      now.month,
                      now.day,
                      initial.hour,
                      initial.minute,
                    ),
                    onDateTimeChanged: (dt) =>
                        picked = TimeOfDay.fromDateTime(dt),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return confirmed == true ? picked : null;
  }
}
