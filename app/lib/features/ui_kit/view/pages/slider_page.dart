import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_slider.dart';

class SliderPage extends StatefulWidget {
  const SliderPage({super.key});
  @override
  State<SliderPage> createState() => _SliderPageState();
}

class _SliderPageState extends State<SliderPage> {
  var _v1 = 0.4;
  var _v2 = 2.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Slider'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          ShowcaseSection(
            title: 'Default',
            child: AppSlider(
              value: _v1,
              onChanged: (v) => setState(() => _v1 = v),
            ),
          ),
          ShowcaseSection(
            title: 'With Value Tooltip',
            child: AppSlider(
              value: _v2,
              max: 5,
              divisions: 5,
              showValue: true,
              onChanged: (v) => setState(() => _v2 = v),
            ),
          ),
        ],
      ),
    );
  }
}
