import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_file_tree.dart';

class FileTreePage extends StatelessWidget {
  const FileTreePage({super.key});

  static const _roots = [
    AppFileNode(
      name: 'lib',
      isFolder: true,
      children: [
        AppFileNode(
          name: 'shared',
          isFolder: true,
          children: [
            AppFileNode(
              name: 'widgets',
              isFolder: true,
              children: [
                AppFileNode(name: 'app_button.dart'),
                AppFileNode(name: 'app_input.dart'),
                AppFileNode(name: 'app_card.dart'),
              ],
            ),
          ],
        ),
        AppFileNode(
          name: 'features',
          isFolder: true,
          children: [
            AppFileNode(name: 'home', isFolder: true),
            AppFileNode(name: 'ui_kit', isFolder: true),
          ],
        ),
        AppFileNode(name: 'main.dart'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'File Tree'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: const [
          ShowcaseSection(
            title: 'Directory Structure',
            child: AppFileTree(roots: _roots),
          ),
        ],
      ),
    );
  }
}
