import 'package:equatable/equatable.dart';

/// [ended] covers the service-over states (末班已過 / 今日未營運): the timeline
/// draws a cross instead of a stop dot.
enum TimelineStopState { none, approaching, arriving, ended }

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
    this.fareSection,
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

  /// 1-based fare-section index for two-section (兩段票) routes: 1 before the
  /// buffer zone, 2 after it; buffer stops carry the section they lead into and
  /// are flagged by [isBuffer]. Null when the route has no fare division
  /// (flat/一段票, free, or 里程計費) — the timeline then draws no section band.
  final int? fareSection;

  @override
  List<Object?> get props => [
    uid,
    name,
    primaryTime,
    secondaryTime,
    state,
    active,
    isBuffer,
    fareSection,
  ];
}
