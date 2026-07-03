import 'package:flutter/material.dart';
import 'package:wheres_the_car/data/models/timeline_stop.dart';
import 'package:wheres_the_car/features/bus/widgets/wheel.dart';

class IpodWheelSheet extends StatelessWidget {
  const IpodWheelSheet({
    required this.stops,
    required this.stationOffsets,
    required this.selectedIndex,
    required this.onStationSelected,
    super.key,
    this.scrollController,
  });

  final List<TimelineStop> stops;
  final List<double> stationOffsets;
  final int selectedIndex;
  final ValueChanged<int> onStationSelected;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Wheel(
          stops: stops,
          stationOffsets: stationOffsets,
          selectedIndex: selectedIndex,
          onStationSelected: onStationSelected,
          scrollController: scrollController,
        ),
      ),
    );
  }
}
