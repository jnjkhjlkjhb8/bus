import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_dropdown.dart';

class DropdownPage extends StatefulWidget {
  const DropdownPage({super.key});
  @override
  State<DropdownPage> createState() => _DropdownPageState();
}

class _DropdownPageState extends State<DropdownPage> {
  final _route = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _route.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Dropdown'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Select',
            child: AppDropdown<String>(
              hint: '選擇路線',
              valueListenable: _route,
              items: const [
                DropdownItem(value: '307', child: Text('307 往中壢')),
                DropdownItem(value: '308', child: Text('308 往台北')),
                DropdownItem(value: '9', child: Text('9 往林口')),
              ],
              onChanged: (v) => _route.value = v,
            ),
          ),
        ],
      ),
    );
  }
}
