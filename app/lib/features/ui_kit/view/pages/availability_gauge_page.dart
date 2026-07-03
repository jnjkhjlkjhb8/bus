import 'package:flutter/material.dart';
import 'package:wheres_the_car/features/ui_kit/view/widgets/showcase_section.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/availability_gauge.dart';

class AvailabilityGaugePage extends StatelessWidget {
  const AvailabilityGaugePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DetailAppBar(title: 'Availability Gauge'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: const [
          ShowcaseSection(
            title: 'Balanced',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AvailabilityGauge(available: 12, docks: 9),
            ),
          ),
          ShowcaseSection(
            title: 'Low bikes (scarce side highlighted)',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AvailabilityGauge(available: 2, docks: 18),
            ),
          ),
          ShowcaseSection(
            title: 'No bikes',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AvailabilityGauge(available: 0, docks: 20),
            ),
          ),
          ShowcaseSection(
            title: 'Docks full',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AvailabilityGauge(available: 20, docks: 0),
            ),
          ),
        ],
      ),
    );
  }
}
