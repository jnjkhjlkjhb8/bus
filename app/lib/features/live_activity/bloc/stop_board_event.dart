import 'package:wheres_the_car/data/models/bus_models.dart';

abstract class StopBoardEvent {
  const StopBoardEvent();
}

/// Starts (or retargets) the stop-board Live Activity at [stopKey] in
/// [city], displayed under [stopName].
class StopBoardStarted extends StopBoardEvent {
  const StopBoardStarted(this.city, this.stopKey, this.stopName);
  final String city;
  final String stopKey;
  final String stopName;
}

class StopBoardStopped extends StopBoardEvent {
  const StopBoardStopped();
}

/// Internal: a fresh arrivals frame from the station-ETA stream.
class BoardArrivalsReceived extends StopBoardEvent {
  const BoardArrivalsReceived(this.arrivals);
  final List<BusStopArrival> arrivals;
}
