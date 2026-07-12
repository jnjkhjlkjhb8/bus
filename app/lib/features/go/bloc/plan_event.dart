import 'package:wheres_the_car/data/models/plan_models.dart';

abstract class PlanEvent {
  const PlanEvent();
}

/// Hydrate saved snapshots from local storage (on bloc construction).
class SavedRoutesLoaded extends PlanEvent {
  const SavedRoutesLoaded();
}

/// Save the route if not already saved, otherwise remove it.
class RouteSaveToggled extends PlanEvent {
  const RouteSaveToggled(this.route);
  final PlanRoute route;
}

/// Load a saved snapshot as the current result so it draws on the map.
class SavedRouteOpened extends PlanEvent {
  const SavedRouteOpened(this.route);
  final PlanRoute route;
}

class PlanSearchRequested extends PlanEvent {
  const PlanSearchRequested({
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
    required this.date,
    required this.time,
    this.arriveBy = false,
    this.gc = 0.0,
    this.transitModes = const [3, 4, 5, 6, 7, 8, 9],
    this.top = 5,
    this.transferMin = 15,
    this.transferMax = 60,
    this.firstMileMode = 0,
    this.firstMileTime = 10,
    this.lastMileMode = 0,
    this.lastMileTime = 10,
  });

  final double fromLat;
  final double fromLon;
  final double toLat;
  final double toLon;
  final String date;
  final String time;
  final bool arriveBy;
  final double gc;
  final List<int> transitModes;
  final int top;
  final int transferMin;
  final int transferMax;
  final int firstMileMode;
  final int firstMileTime;
  final int lastMileMode;
  final int lastMileTime;
}

/// Select a route and enter the plan-preview phase (single itinerary shown).
/// Fired by a results card tap or a map alternate-polyline tap.
class RouteSelected extends PlanEvent {
  const RouteSelected({required this.index});
  final int index;
}

/// Leave the plan-preview phase. Returns to the results list, or — when the
/// preview was entered directly from a saved route (no results list behind it)
/// — clears the injected result and restores the pre-search planner.
class PreviewClosed extends PlanEvent {
  const PreviewClosed();
}

class NavigationStarted extends PlanEvent {
  const NavigationStarted();
}

class StopArrived extends PlanEvent {
  const StopArrived({required this.legIndex, required this.stopIndex});
  final int legIndex;
  final int stopIndex;
}

class NavigationEnded extends PlanEvent {
  const NavigationEnded();
}

/// Display-only: the current turn-by-turn walk step advanced. Does not touch
/// leg progress (owned by [StopArrived]).
class WalkStepAdvanced extends PlanEvent {
  const WalkStepAdvanced({required this.index});
  final int index;
}
