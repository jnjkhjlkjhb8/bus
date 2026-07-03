import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_switch.dart';

class SwitchPage extends StatefulWidget {
  const SwitchPage({super.key});
  @override
  State<SwitchPage> createState() => _SwitchPageState();
}

class _SwitchPageState extends State<SwitchPage> {
  var _a = true;
  var _b = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Switch'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Standalone',
            child: Row(
              children: [
                AppSwitch(value: _a, onChanged: (v) => setState(() => _a = v)),
                const SizedBox(width: 16),
                AppSwitch(value: _b, onChanged: (v) => setState(() => _b = v)),
              ],
            ),
          ),
          ShowcaseSection(
            title: 'With Label',
            child: Column(
              children: [
                AppSwitch(
                  value: _a,
                  onChanged: (v) => setState(() => _a = v),
                  label: '即時動態',
                ),
                const SizedBox(height: 8),
                AppSwitch(
                  value: _b,
                  onChanged: (v) => setState(() => _b = v),
                  label: '震動回饋',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
