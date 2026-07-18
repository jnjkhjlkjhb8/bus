import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/shared/widgets/app_button.dart';
import 'package:wheres_the_car/shared/widgets/app_dialog.dart';
import 'package:wheres_the_car/shared/widgets/clock_dial.dart';

const _thsrStations = [
  '南港',
  '台北',
  '板橋',
  '桃園',
  '新竹',
  '苗栗',
  '台中',
  '彰化',
  '雲林',
  '嘉義',
  '台南',
  '左營',
];

Future<String?> showTHSRStationPicker(BuildContext context) {
  return showAppModal<String>(
    context: context,
    barrierLabel: '選擇車站',
    builder: (_) => const _THSRPickerDialog(),
  );
}

class _THSRPickerDialog extends StatefulWidget {
  const _THSRPickerDialog();

  @override
  State<_THSRPickerDialog> createState() => _THSRPickerDialogState();
}

class _THSRPickerDialogState extends State<_THSRPickerDialog> {
  int _selectedIndex = 1;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusModal),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '選擇車站',
              style: AppTextStyles.bodyRegular.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ClockDial(
                items: _thsrStations,
                selectedIndex: _selectedIndex,
                onSelected: (i) => setState(() => _selectedIndex = i),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton.text(
                  label: '取消',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                AppButton.text(
                  label: '確定',
                  onPressed: () =>
                      Navigator.of(context).pop(_thsrStations[_selectedIndex]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
