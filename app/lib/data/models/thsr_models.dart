import 'package:equatable/equatable.dart';

/// Seat availability per section: O = available, L = limited, X = sold out.
enum ThsrSeatStatus { available, limited, soldOut, unknown }

class ThsrTimetableItem extends Equatable {
  const ThsrTimetableItem({
    required this.trainNo,
    required this.departureTime,
    required this.arrivalTime,
    required this.travelMinutes,
    required this.delayMinutes,
    required this.remark,
    this.seatStatus = ThsrSeatStatus.unknown,
  });

  final String trainNo;
  final String departureTime;
  final String arrivalTime;
  final int travelMinutes;
  final int delayMinutes;
  final String remark;
  final ThsrSeatStatus seatStatus;

  @override
  List<Object?> get props => [
    trainNo,
    departureTime,
    arrivalTime,
    travelMinutes,
    delayMinutes,
    remark,
  ];
}

class ThsrStopTime extends Equatable {
  const ThsrStopTime({
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
