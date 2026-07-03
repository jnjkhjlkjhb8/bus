import 'package:equatable/equatable.dart';

enum TimelineStopState { none, approaching, arriving }

class TimelineStop extends Equatable {
  const TimelineStop({
    required this.uid,
    required this.name,
    this.primaryTime,
    this.primaryLabel,
    this.secondaryTime,
    this.secondaryLabel,
    this.state = TimelineStopState.none,
    this.active = false,
    this.lat,
    this.lon,
    this.isBuffer = false,
  });

  final String uid;
  final String name;
  final String? primaryTime;
  final String? primaryLabel;
  final String? secondaryTime;
  final String? secondaryLabel;
  final TimelineStopState state;
  final bool active;
  final double? lat;
  final double? lon;
  final bool isBuffer;

  @override
  List<Object?> get props => [
    uid,
    name,
    primaryTime,
    secondaryTime,
    state,
    active,
    isBuffer,
  ];
}
