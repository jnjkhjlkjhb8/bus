import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_button.dart';
import 'package:wheres_the_car/shared/widgets/app_drawer_widget.dart';

class DrawerPage extends StatefulWidget {
  const DrawerPage({super.key});

  @override
  State<DrawerPage> createState() => _DrawerPageState();
}

class _DrawerPageState extends State<DrawerPage> {
  var _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Drawer'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Open Drawer',
            child: Builder(
              builder: (ctx) => AppButton(
                label: '開啟側邊欄',
                icon: Icons.menu_rounded,
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          ),
        ],
      ),
      drawer: AppDrawerWidget(
        selectedIndex: _selected,
        onChanged: (i) {
          setState(() => _selected = i);
          Navigator.pop(context);
        },
        items: const [
          AppDrawerItem(label: '首頁', icon: Icons.home_rounded),
          AppDrawerItem(label: '地圖', icon: Icons.map_rounded),
          AppDrawerItem(label: '路線', icon: Icons.directions_rounded),
          AppDrawerItem(label: '設定', icon: Icons.settings_rounded),
        ],
      ),
    );
  }
}
