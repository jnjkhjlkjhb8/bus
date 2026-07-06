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
  });

  final JourneyPhase phase;
  final List<JourneyLeg> legs;
  final int legIndex;
  final Duration? eta;
  final int nextStopIndex;
  final bool suggestBoarding;

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
  }) {
    return JourneySessionState(
      phase: phase ?? this.phase,
      legs: legs ?? this.legs,
      legIndex: legIndex ?? this.legIndex,
      eta: clearEta ? null : eta ?? this.eta,
      nextStopIndex: nextStopIndex ?? this.nextStopIndex,
      suggestBoarding: suggestBoarding ?? this.suggestBoarding,
    );
  }

  @override
  List<Object?> get props =>
      [phase, legs, legIndex, eta, nextStopIndex, suggestBoarding];
}
