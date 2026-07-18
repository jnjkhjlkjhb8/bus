import 'package:flutter/material.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_search_bar.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';

class StationPickerSheet extends StatefulWidget {
  const StationPickerSheet({required this.stations, super.key});

  final List<String> stations;

  static Future<String?> show(BuildContext context, List<String> stations) {
    return BottomSheetShell.show<String>(
      context: context,
      initialOffset: const SheetOffset.proportionalToViewport(0.6),
      child: Expanded(child: StationPickerSheet(stations: stations)),
    );
  }

  @override
  State<StationPickerSheet> createState() => _StationPickerSheetState();
}

class _StationPickerSheetState extends State<StationPickerSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.stations.where((s) => s.contains(_query)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: AppSearchBar(
            hintText: '搜尋車站',
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) => Pressable(
              onTap: () => Navigator.of(context).pop(filtered[i]),
              semanticLabel: filtered[i],
              child: ListTile(
                title: Text(filtered[i], style: AppTextStyles.bodyLarge),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
