import 'package:equatable/equatable.dart';
import 'package:wheres_the_bus/data/models/fare_type.dart';

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

  /// TDX ticket type, which encodes 票種 and 車種 together: a 票種 prefix
  /// (成 / 孩 / 敬 / 愛) followed by a 車種 suffix (自 / 莒 / 復 / 普), e.g. 成自
  /// or 敬復.
  final String ticketType;
  final int price;

  @override
  List<Object?> get props => [ticketType, price];
}

/// The 車種 suffix TDX prices a train of [trainTypeName] on.
///
/// A TRA fare is per train class, not per O/D pair: 桃園→臺北 costs 63 on a
/// 區間車 and 99 on a 自強. TDX prices 區間車 on the 復興 (復) tier and groups
/// 太魯閣/普悠瑪/EMU3000 with 自強 (自). 普快 is matched before 普悠瑪 because
/// both start with 普.
String traTrainClassSuffix(String trainTypeName) {
  if (trainTypeName.contains('普快')) return '普';
  if (trainTypeName.contains('區間') || trainTypeName.contains('復興')) {
    return '復';
  }
  if (trainTypeName.contains('莒光')) return '莒';
  return '自';
}

/// The fare for a train of [trainTypeName] at the rider's [type], or null when
/// the pair prices no ticket of that train class at all.
///
/// Walks `FareType.traPrefixes` so a rider on a concession ticket gets their
/// own price where TDX publishes one and the full fare — reported as such
/// through `ResolvedFare.matched` — where it does not.
ResolvedFare? traFareFor(
  List<TraFare> fares,
  String trainTypeName,
  FareType type,
) {
  final suffix = traTrainClassSuffix(trainTypeName);
  for (final prefix in type.traPrefixes) {
    for (final fare in fares) {
      if (fare.ticketType == '$prefix$suffix' && fare.price > 0) {
        return (
          price: fare.price,
          matched: type.matchedWhen(isFullFare: prefix == '成'),
        );
      }
    }
  }
  return null;
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
    this.runsDaily = false,
    this.isAddedService = false,
    this.isSuspended = false,
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

  /// 每日行駛 — the train runs every day rather than on selected days only.
  final bool runsDaily;

  /// 加班車 — an extra service added on top of the published timetable.
  final bool isAddedService;

  /// 停駛 — cancelled for this service date. A state, not an amenity: the row
  /// renders struck through rather than carrying a service mark.
  final bool isSuspended;

  @override
  List<Object?> get props => [
    trainNo,
    trainType,
    departureTime,
    arrivalTime,
    travelMinutes,
    delayMinutes,
    hasBike,
    hasDiningCar,
    isDisabledFriendly,
    hasBreastfeeding,
    remark,
    runsDaily,
    isAddedService,
    isSuspended,
  ];
}
