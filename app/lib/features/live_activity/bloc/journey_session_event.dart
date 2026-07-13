import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';

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
class EtaTicked extends JourneySessionEvent {
  const EtaTicked(this.eta);
  final Duration? eta;
}

/// Internal: riding-mode progress advanced to [nextStopIndex].
class ProgressTicked extends JourneySessionEvent {
  const ProgressTicked(this.nextStopIndex);
  final int nextStopIndex;
}
