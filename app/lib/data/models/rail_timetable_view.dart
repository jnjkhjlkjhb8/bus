import 'package:equatable/equatable.dart';

/// One TRA or THSR timetable result, reshaped to exactly the fields the
/// summary card renders. A validated domain type: the backend proto stops at
/// the decoder and never reaches shared widgets.
///
/// [travelTime] is kept as the source's display string (e.g. "1:30") rather
/// than parsed minutes because the card shows it verbatim; the parsed-minutes
/// domain models (TraTimetableItem/ThsrTimetableItem) serve list rendering.
class RailTimetableView extends Equatable {
  const RailTimetableView({
    required this.trainNo,
    required this.trainType,
    required this.originName,
    required this.destinationName,
    required this.departureTime,
    required this.arrivalTime,
    required this.travelTime,
  });

  final String trainNo;
  final String trainType;
  final String originName;
  final String destinationName;
  final String departureTime;
  final String arrivalTime;
  final String travelTime;

  @override
  List<Object?> get props => [
    trainNo,
    trainType,
    originName,
    destinationName,
    departureTime,
    arrivalTime,
    travelTime,
  ];
}
