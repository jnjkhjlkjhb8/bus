import 'package:flutter/material.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/data/generated/thsr.pb.dart';
import 'package:wheres_the_car/data/generated/tra.pb.dart';
import 'package:wheres_the_car/shared/widgets/train_type_chip.dart';

/// Summary card for one backend-shaped TRA or THSR timetable result.
class RailTimetableCard extends StatelessWidget {
  const RailTimetableCard.tra({
    required tra_timetable timetable,
    this.delayMinutes = 0,
    this.onTap,
    super.key,
  }) : _traTimetable = timetable,
       _thsrTimetable = null;

  const RailTimetableCard.thsr({
    required thsa_timetable timetable,
    this.delayMinutes = 0,
    this.onTap,
    super.key,
  }) : _traTimetable = null,
       _thsrTimetable = timetable;

  final tra_timetable? _traTimetable;
  final thsa_timetable? _thsrTimetable;
  final int delayMinutes;
  final VoidCallback? onTap;

  String get _trainNo => _traTimetable?.trainNo ?? _thsrTimetable!.trainNo;
  String get _trainType => _traTimetable?.trainTypeName ?? '高鐵';
  String get _origin =>
      _traTimetable?.startingStationName ?? _thsrTimetable!.startingStationName;
  String get _destination =>
      _traTimetable?.endingStationName ?? _thsrTimetable!.endingStationName;
  String get _departureTime =>
      _clockTime(_traTimetable?.startingTime ?? _thsrTimetable!.startingTime);
  String get _arrivalTime =>
      _clockTime(_traTimetable?.endingTime ?? _thsrTimetable!.endingTime);
  String get _travelTime =>
      _traTimetable?.travelTime ?? _thsrTimetable!.travelTime;

  static String _clockTime(String value) {
    final match = RegExp(r'(?:T|^)(\d{2}:\d{2})').firstMatch(value);
    return match?.group(1) ?? value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delayed = delayMinutes > 0;
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TrainTypeChip(type: _trainType),
                  const SizedBox(width: 8),
                  Text(_trainNo, style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    delayed ? '誤點 $delayMinutes 分' : '準點',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: delayed
                          ? AppTheme.trainDelay
                          : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(_departureTime, style: theme.textTheme.titleLarge),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        Text(_travelTime, style: theme.textTheme.bodySmall),
                        Divider(color: theme.colorScheme.outlineVariant),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_arrivalTime, style: theme.textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$_origin → $_destination',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
