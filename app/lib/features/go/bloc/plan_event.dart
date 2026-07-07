abstract class PlanEvent {
  const PlanEvent();
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

class RouteSelected extends PlanEvent {
  const RouteSelected({required this.index});
  final int index;
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
