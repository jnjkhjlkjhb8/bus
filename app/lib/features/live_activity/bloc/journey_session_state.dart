import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

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

  JourneyLeg? get currentLeg =>
      legIndex < legs.length ? legs[legIndex] : null;

  bool get isLastLeg => legIndex >= legs.length - 1;

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
  ];
}
