import 'package:flutter/material.dart';

/// Two-thumb range slider. Mirrors `AppSlider` but for a [RangeValues] min/max
/// selection (e.g. a transfer-time window). Labels appear while dragging when
/// [divisions] is set.
class AppRangeSlider extends StatelessWidget {
  const AppRangeSlider({
    required this.values,
    required this.onChanged,
    super.key,
    this.min = 0,
    this.max = 1,
    this.divisions,
  });

  final RangeValues values;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<RangeValues>? onChanged;

  @override
  Widget build(BuildContext context) {
    final start = values.start.clamp(min, max);
    final end = values.end.clamp(start, max);
    return RangeSlider(
      values: RangeValues(start, end),
      min: min,
      max: max,
      divisions: divisions,
      labels: divisions == null
          ? null
          : RangeLabels(start.round().toString(), end.round().toString()),
      onChanged: onChanged,
    );
  }
}
