import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_quantity_selector.dart';

class QuantityPage extends StatefulWidget {
  const QuantityPage({super.key});

  @override
  State<QuantityPage> createState() => _QuantityPageState();
}

class _QuantityPageState extends State<QuantityPage> {
  var _count = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Quantity Selector'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Default (min 0, max 99)',
            child: AppQuantitySelector(
              value: _count,
              onChanged: (v) => setState(() => _count = v),
            ),
          ),
        ],
      ),
    );
  }
}
