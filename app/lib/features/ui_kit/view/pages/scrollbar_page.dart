import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';

class ScrollbarPage extends StatefulWidget {
  const ScrollbarPage({super.key});

  @override
  State<ScrollbarPage> createState() => _ScrollbarPageState();
}

class _ScrollbarPageState extends State<ScrollbarPage> {
  final _ctrl = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Scrollbar'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Vertical Scrollbar',
            child: SizedBox(
              height: 200,
              child: Scrollbar(
                controller: _ctrl,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _ctrl,
                  itemCount: 20,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '路線 ${i + 1}',
                      style: AppTextStyles.bodyRegular,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
