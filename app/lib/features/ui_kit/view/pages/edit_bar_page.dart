import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_edit_bar.dart';

class EditBarPage extends StatefulWidget {
  const EditBarPage({super.key});
  @override
  State<EditBarPage> createState() => _EditBarPageState();
}

class _EditBarPageState extends State<EditBarPage> {
  final _active = <AppEditAction>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Edit Bar'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Text Format Toolbar',
            child: AppEditBar(
              activeActions: _active,
              onToggle: (a) => setState(() {
                _active.contains(a) ? _active.remove(a) : _active.add(a);
              }),
            ),
          ),
        ],
      ),
    );
  }
}
