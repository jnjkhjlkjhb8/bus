import 'package:equatable/equatable.dart';
import 'package:wheres_the_bus/features/live_activity/model/journey_models.dart';

enum JourneyPhase { idle, waiting, riding, done }

class JourneySessionState extends Equatable {
  const JourneySessionState({
    this.phase = JourneyPhase.idle,
    this.legs = const [],
    this.legIndex = 0,
    this.eta,
    this.nextStopIndex = 0,
    this.suggestBoarding = false,
    this.trackOnly = false,
    this.plate,
    this.pinnedStopsRemaining,
    this.railProgress,
    this.railNextStop,
  });

  final JourneyPhase phase;
  final List<JourneyLeg> legs;
  final int legIndex;
  final Duration? eta;
  final int nextStopIndex;
  final bool suggestBoarding;

  /// Standalone arrival-countdown session; see `JourneyStarted.trackOnly`.
  final bool trackOnly;

  /// The pinned vehicle's plate; display/reminder metadata only — the ETA
  /// stream is never filtered by plate.
  final String? plate;

  /// Live stop count between the pinned vehicle's current stop and the
  /// leg's alight stop, for a pinned (`plate != null`) trackOnly session.
  /// Null until the route-ETA stream has resolved both stops at least once.
  final int? pinnedStopsRemaining;

  /// Continuous 0..1 progress along a rail track leg, timetable + clock
  /// derived. Null for non-rail sessions.
  final double? railProgress;

  /// The rail track leg's live next-stop name. Null for non-rail sessions.
  final String? railNextStop;

  JourneyLeg? get currentLeg => legIndex < legs.length ? legs[legIndex] : null;

  bool get isLastLeg => legIndex >= legs.length - 1;

  /// A standalone rail arrival tracker: presented as the riding card (which
  /// draws the progress line) even though the internal phase stays waiting.
  bool get isRailTrack =>
      trackOnly && (currentLeg?.railSchedule.isNotEmpty ?? false);

  JourneySessionState copyWith({
    JourneyPhase? phase,
    List<JourneyLeg>? legs,
    int? legIndex,
    Duration? eta,
    bool clearEta = false,
    int? nextStopIndex,
    bool? suggestBoarding,
    bool? trackOnly,
    String? plate,
    int? pinnedStopsRemaining,
    double? railProgress,
    String? railNextStop,
  }) {
    return JourneySessionState(
      phase: phase ?? this.phase,
      legs: legs ?? this.legs,
      legIndex: legIndex ?? this.legIndex,
      eta: clearEta ? null : eta ?? this.eta,
      nextStopIndex: nextStopIndex ?? this.nextStopIndex,
      suggestBoarding: suggestBoarding ?? this.suggestBoarding,
      trackOnly: trackOnly ?? this.trackOnly,
      plate: plate ?? this.plate,
      pinnedStopsRemaining: pinnedStopsRemaining ?? this.pinnedStopsRemaining,
      railProgress: railProgress ?? this.railProgress,
      railNextStop: railNextStop ?? this.railNextStop,
    );
  }

  @override
  List<Object?> get props => [
    phase,
    legs,
    legIndex,
    eta,
    nextStopIndex,
    suggestBoarding,
    trackOnly,
    plate,
    pinnedStopsRemaining,
    railProgress,
    railNextStop,
  ];
}
