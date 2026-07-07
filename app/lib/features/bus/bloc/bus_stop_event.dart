import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/repositories/bus_stop_eta_repository.dart';

sealed class BusStopEvent extends Equatable {
  const BusStopEvent();
  @override
  List<Object?> get props => [];
}

class BusStopStarted extends BusStopEvent {
  const BusStopStarted();
}

class BusStopRetryRequested extends BusStopEvent {
  const BusStopRetryRequested();
}

class BusStopArrivalsUpdated extends BusStopEvent {
  const BusStopArrivalsUpdated(this.arrivals);
  final List<BusStopArrival> arrivals;
  @override
  List<Object?> get props => [arrivals];
}

class BusStopDecayTicked extends BusStopEvent {
  const BusStopDecayTicked();
}

class BusStopFailed extends BusStopEvent {
  const BusStopFailed(this.error);

  final AppError error;

  @override
  List<Object?> get props => [error];
}
