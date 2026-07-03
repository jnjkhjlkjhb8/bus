import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_button.dart';
import 'package:wheres_the_car/shared/widgets/app_time_picker.dart';

class TimePickerPage extends StatefulWidget {
  const TimePickerPage({super.key});
  @override
  State<TimePickerPage> createState() => _TimePickerPageState();
}

class _TimePickerPageState extends State<TimePickerPage> {
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 30);

  String get _label {
    final h = _time.hour.toString().padLeft(2, '0');
    final m = _time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Time Picker'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'iOS-style time wheel',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('已選 $_label', style: AppTextStyles.heading2),
                  const Spacer(),
                  AppButton(
                    label: '選擇時間',
                    onPressed: () async {
                      final picked = await AppTimePicker.show(context, _time);
                      if (picked != null) setState(() => _time = picked);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
