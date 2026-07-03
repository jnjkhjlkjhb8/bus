import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_radio.dart';

class RadioPage extends StatefulWidget {
  const RadioPage({super.key});
  @override
  State<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends State<RadioPage> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Radio'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Single Select',
            child: Column(
              children: [
                AppRadio<int>(
                  value: 0,
                  groupValue: _selected,
                  onChanged: (v) => setState(() => _selected = v),
                  label: '公車',
                ),
                AppRadio<int>(
                  value: 1,
                  groupValue: _selected,
                  onChanged: (v) => setState(() => _selected = v),
                  label: '捷運',
                ),
                AppRadio<int>(
                  value: 2,
                  groupValue: _selected,
                  onChanged: (v) => setState(() => _selected = v),
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
