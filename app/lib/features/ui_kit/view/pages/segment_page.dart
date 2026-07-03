import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_segmented_control.dart';
import 'package:wheres_the_car/shared/widgets/app_sliding_segment.dart';

class SegmentPage extends StatefulWidget {
  const SegmentPage({super.key});
  @override
  State<SegmentPage> createState() => _SegmentPageState();
}

class _SegmentPageState extends State<SegmentPage> {
  var _selected = 0;
  var _sliding = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Segment'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Segmented Control',
            child: AppSegmentedControl<int>(
              options: const {0: '地圖', 1: '時刻表'},
              value: _selected,
              onChanged: (i) => setState(() => _selected = i),
            ),
          ),
          ShowcaseSection(
            title: 'Sliding Segment',
            child: AppSlidingSegment<int>(
              options: const {0: '地圖', 1: '時刻表'},
              value: _sliding,
              onChanged: (i) => setState(() => _sliding = i),
            ),
          ),
        ],
      ),
    );
  }
}
