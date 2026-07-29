import 'package:wheres_the_bus/features/live_activity/model/journey_models.dart';

abstract class JourneySessionEvent {
  const JourneySessionEvent();
}

class JourneyStarted extends JourneySessionEvent {
  const JourneyStarted({
    required this.legs,
    this.trackOnly = false,
    this.plate,
  });
  final List<JourneyLeg> legs;

  /// A standalone arrival-countdown session (bus stop / rail departure
  /// tracking): the session never rides and ends itself once the tracked
  /// vehicle has arrived and left.
  final bool trackOnly;

  /// The pinned vehicle's plate, display/reminder metadata only — the ETA
  /// stream stays next-bus-per-stop and is never filtered by plate.
  final String? plate;
}

class BoardConfirmed extends JourneySessionEvent {
  const BoardConfirmed();
}

class AlightConfirmed extends JourneySessionEvent {
  const AlightConfirmed();
}

class JourneyCancelled extends JourneySessionEvent {
  const JourneyCancelled();
}

/// Internal: new ETA value for the current waiting leg (null = unknown).
///
/// [generation] is the journey generation this event was produced under
/// (see the journey session bloc's class doc). A stream subscription
/// belonging to a cancelled or superseded journey can still have an event
/// in flight when the next journey starts; the bloc compares [generation]
/// against its current one and drops anything that doesn't match, so a
/// late event never mixes into a different journey's state.
class EtaTicked extends JourneySessionEvent {
  const EtaTicked(this.eta, {required this.generation});
  final Duration? eta;
  final int generation;
}

/// Internal: riding-mode progress advanced to [nextStopIndex]. See
/// [EtaTicked.generation].
class ProgressTicked extends JourneySessionEvent {
  const ProgressTicked(this.nextStopIndex, {required this.generation});
  final int nextStopIndex;
  final int generation;
}

/// Internal: the pinned vehicle's live stop-distance from the alight stop,
/// recomputed from a fresh route-ETA frame (null = not yet resolvable). See
/// [EtaTicked.generation].
class PinnedStopsUpdated extends JourneySessionEvent {
  const PinnedStopsUpdated(this.stopsRemaining, {required this.generation});
  final int? stopsRemaining;
  final int generation;
}

/// Internal: a fresh rail tracking frame (schedule + live TRA delay derived).
/// Carries everything the rail riding card needs. See [EtaTicked.generation].
class RailTrackTicked extends JourneySessionEvent {
  const RailTrackTicked({
    required this.eta,
    required this.remainingStops,
    required this.progress,
    required this.nextStop,
    required this.generation,
  });
  final Duration eta;
  final int remainingStops;
  final double progress;
  final String nextStop;
  final int generation;
}
