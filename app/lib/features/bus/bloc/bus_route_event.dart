import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';

sealed class BusRouteEvent extends Equatable {
  const BusRouteEvent();
  @override
  List<Object?> get props => [];
}

class BusRouteStarted extends BusRouteEvent {
  const BusRouteStarted();
}

class BusRouteDirectionToggled extends BusRouteEvent {
  const BusRouteDirectionToggled(this.direction);
  final int direction;
  @override
  List<Object?> get props => [direction];
}

class BusRouteEtaUpdated extends BusRouteEvent {
  const BusRouteEtaUpdated(this.etaMap);
  final Map<String, BusStopEtaViewModel> etaMap;
  @override
  List<Object?> get props => [etaMap];
}

class BusRouteDetailsUpdated extends BusRouteEvent {
  const BusRouteDetailsUpdated({this.daily, this.fare});
  final BusDailyTimetable? daily;
  final BusFareInfo? fare;
  @override
  List<Object?> get props => [daily, fare];
}

class BusRouteDecayTicked extends BusRouteEvent {
  const BusRouteDecayTicked();
}

class BusRouteReminderToggled extends BusRouteEvent {
  const BusRouteReminderToggled(this.stopUid);
  final String stopUid;
  @override
  List<Object?> get props => [stopUid];
}

class BusRouteStreamFailed extends BusRouteEvent {
  const BusRouteStreamFailed(this.error);

  final AppError error;

  @override
  List<Object?> get props => [error];
}

class BusRouteStreamRecovered extends BusRouteEvent {
  const BusRouteStreamRecovered();
}
