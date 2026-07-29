import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';

class AppTable extends StatelessWidget {
  const AppTable({
    required this.columns,
    required this.rows,
    this.onSort,
    super.key,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final void Function({required int col, required bool asc})? onSort;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: DataTable2(
        columnSpacing: 12,
        horizontalMargin: 16,
        headingRowHeight: 44,
        dataRowHeight: 48,
        minWidth: 300,
        headingRowColor: WidgetStateProperty.all(cs.surfaceContainerHighest),
        dataRowColor: WidgetStateProperty.resolveWith((states) => null),
        headingTextStyle: AppTextStyles.bodySmall.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
        dataTextStyle: AppTextStyles.bodyRegular.copyWith(
          color: cs.onSurface,
        ),
        border: TableBorder(
          horizontalInside: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
        columns: columns
            .map(
              (c) => DataColumn2(
                label: Text(c),
                size: ColumnSize.S,
                onSort: onSort != null
                    ? (col, asc) => onSort!(col: col, asc: asc)
                    : null,
              ),
            )
            .toList(),
        rows: List.generate(rows.length, (i) {
          final bg = i.isEven ? cs.surfaceContainerLowest : cs.surface;
          return DataRow2(
            color: WidgetStateProperty.all(bg),
            cells: rows[i].map((c) => DataCell(Text(c))).toList(),
          );
        }),
      ),
    );
  }
}
