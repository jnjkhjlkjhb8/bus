import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_date_picker.dart';

class DatePickerPage extends StatefulWidget {
  const DatePickerPage({super.key});

  @override
  State<DatePickerPage> createState() => _DatePickerPageState();
}

class _DatePickerPageState extends State<DatePickerPage> {
  DateTime? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Date Picker'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: '選擇日期',
            child: Column(
              children: [
                AppDatePicker(
                  selectedDay: _selected,
                  onDaySelected: (d) => setState(() => _selected = d),
                ),
                if (_selected != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '已選：${DateFormat('yyyy/MM/dd').format(_selected!)}',
                    style: AppTextStyles.bodyRegular,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
