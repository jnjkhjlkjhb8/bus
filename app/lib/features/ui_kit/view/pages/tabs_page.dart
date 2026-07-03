import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_tabs.dart';

class TabsPage extends StatefulWidget {
  const TabsPage({super.key});
  @override
  State<TabsPage> createState() => _TabsPageState();
}

class _TabsPageState extends State<TabsPage> {
  var _fixed = 0;
  var _scroll = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Tabs'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ShowcaseSection(
            title: 'Fixed',
            child: AppTabs(
              tabs: const ['地圖', '時刻表', '路線'],
              selectedIndex: _fixed,
              onChanged: (i) => setState(() => _fixed = i),
            ),
          ),
          ShowcaseSection(
            title: 'Scrollable',
            child: AppTabs(
              tabs: const ['板南線', '淡水線', '新店線', '中和線', '文湖線', '環狀線'],
              selectedIndex: _scroll,
              onChanged: (i) => setState(() => _scroll = i),
              scrollable: true,
            ),
          ),
        ],
      ),
    );
  }
}
