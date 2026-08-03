import 'package:equatable/equatable.dart';

/// Which way a station board's trains run.
///
/// The wire value is what both rail RPCs take, and the two systems name the
/// same two values differently — 台鐵 順行/逆行, 高鐵 南下/北上 — so the label is
/// resolved at the view rather than baked in here.
enum RailBoardDirection {
  forward(0),
  reverse(1);

  const RailBoardDirection(this.wire);

  final int wire;
}

/// One departure on a station board: a train leaving *this* station, with no
/// destination the rider had to pick first.
///
/// Deliberately smaller than `TraTimetableItem`: a board answers "when does the
/// next train leave and where does it go", so there is no arrival time, no
/// travel time and no fare — those belong to the O/D query, which is still one
/// tap away.
class RailStationDeparture extends Equatable {
  const RailStationDeparture({
    required this.trainNo,
    required this.trainType,
    required this.destination,
    required this.departureTime,
    required this.serviceDate,
    this.isSuspended = false,
    this.remark = '',
  });

  final String trainNo;

  /// Backend train-type label (自強, 區間, …). Empty for THSR, which runs one
  /// class of train and therefore labels its chip from the system instead.
  final String trainType;

  /// The train's own terminus — what 順行/逆行 actually means for this row.
  final String destination;

  /// `HH:mm:ss` on [serviceDate].
  final String departureTime;

  /// `yyyy-MM-dd`. Not always the date that was asked for: a board opened near
  /// midnight is topped up from the next service day, and the train screen
  /// needs the date the train actually runs on.
  final String serviceDate;

  /// 停駛 for this service date.
  final bool isSuspended;

  /// 備註 carried from the timetable.
  final String remark;

  @override
  List<Object?> get props => [
    trainNo,
    trainType,
    destination,
    departureTime,
    serviceDate,
    isSuspended,
    remark,
  ];
}
