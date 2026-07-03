import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_table.dart';

class TablePage extends StatelessWidget {
  const TablePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Table'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: const [
          ShowcaseSection(
            title: 'Bus Schedule',
            child: SizedBox(
              height: 280,
              child: AppTable(
                columns: ['站名', '預計到站', '狀態'],
                rows: [
                  ['台北車站', '14:30', '進站中'],
                  ['中山站', '14:38', '5 分鐘'],
                  ['南京站', '14:44', '11 分鐘'],
                  ['民權站', '14:51', '18 分鐘'],
                  ['松山站', '14:58', '25 分鐘'],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
