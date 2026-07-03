import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_checkbox.dart';

class CheckboxPage extends StatefulWidget {
  const CheckboxPage({super.key});
  @override
  State<CheckboxPage> createState() => _CheckboxPageState();
}

class _CheckboxPageState extends State<CheckboxPage> {
  var _bus = true;
  var _mrt = false;
  var _rail = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Checkbox'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Multi Select',
            child: Column(
              children: [
                AppCheckbox(
                  value: _bus,
                  onChanged: (v) => setState(() => _bus = v ?? _bus),
                  label: '公車',
                ),
                AppCheckbox(
                  value: _mrt,
                  onChanged: (v) => setState(() => _mrt = v ?? _mrt),
                  label: '捷運',
                ),
                AppCheckbox(
                  value: _rail,
                  onChanged: (v) => setState(() => _rail = v ?? _rail),
                  label: '台鐵',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
