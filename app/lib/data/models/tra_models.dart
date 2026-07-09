import 'package:equatable/equatable.dart';

class TraLiveBoardItem extends Equatable {
  const TraLiveBoardItem({
    required this.trainNo,
    required this.direction,
    required this.trainType,
    required this.destStation,
    required this.departureTime,
    required this.delayMinutes,
  });

  final String trainNo;
  final String direction;
  final String trainType;
  final String destStation;

  final String departureTime;
  final int delayMinutes;

  /// Departure-board ordering: earliest scheduled departure first. Shared by
  /// RailBloc's full board and the home-sheet TraStationBloc so the two live
  /// views of the same stream can't drift apart in sort policy.
  static int byDeparture(TraLiveBoardItem a, TraLiveBoardItem b) =>
      a.departureTime.compareTo(b.departureTime);

  @override
  List<Object?> get props => [
    trainNo,
    direction,
    trainType,
    destStation,
    departureTime,
    delayMinutes,
  ];
}

class TraDelayItem extends Equatable {
  const TraDelayItem({required this.trainNo, required this.delayMinutes});
  final String trainNo;
  final int delayMinutes;
  @override
  List<Object?> get props => [trainNo, delayMinutes];
}

class TraStopTime extends Equatable {
  const TraStopTime({
    required this.stationName,
    required this.arrivalTime,
    required this.departureTime,
    required this.sequence,
  });
  final String stationName;
  final String arrivalTime;
  final String departureTime;
  final int sequence;
  @override
  List<Object?> get props => [
    stationName,
    arrivalTime,
    departureTime,
    sequence,
  ];
}

class TraFare extends Equatable {
  const TraFare({required this.ticketType, required this.price});

  final String ticketType;
  final int price;

  @override
  List<Object?> get props => [ticketType, price];
}

class TraTimetableItem extends Equatable {
  const TraTimetableItem({
    required this.trainNo,
    required this.trainType,
    required this.departureTime,
    required this.arrivalTime,
    required this.travelMinutes,
    required this.delayMinutes,
    required this.hasBike,
    required this.hasDiningCar,
    required this.isDisabledFriendly,
    required this.hasBreastfeeding,
    required this.remark,
  });

  final String trainNo;
  final String trainType;
  final String departureTime;
  final String arrivalTime;
  final int travelMinutes;
  final int delayMinutes;
  final bool hasBike;
  final bool hasDiningCar;
  final bool isDisabledFriendly;
  final bool hasBreastfeeding;
  final String remark;

  @override
  List<Object?> get props => [
    trainNo,
    trainType,
    departureTime,
    arrivalTime,
    travelMinutes,
    delayMinutes,
  ];
}
