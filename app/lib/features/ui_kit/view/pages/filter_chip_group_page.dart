import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/filter_chip_group.dart';

class FilterChipGroupPage extends StatefulWidget {
  const FilterChipGroupPage({super.key});
  @override
  State<FilterChipGroupPage> createState() => _FilterChipGroupPageState();
}

class _FilterChipGroupPageState extends State<FilterChipGroupPage> {
  final _selected = <int>{0, 2};

  static const _options = {0: '公車', 1: '公共自行車', 2: '捷運', 3: '雙鐵'};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Filter Chip Group'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Multi-select',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilterChipGroup<int>(
                options: _options,
                selected: _selected,
                onToggle: (k) => setState(() {
                  _selected.contains(k)
                      ? _selected.remove(k)
                      : _selected.add(k);
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
