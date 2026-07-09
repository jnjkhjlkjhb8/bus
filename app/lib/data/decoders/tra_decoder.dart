import 'package:wheres_the_car/data/generated/tra.pb.dart';
import 'package:wheres_the_car/data/models/rail_timetable_view.dart';
import 'package:wheres_the_car/data/models/tra_models.dart';

class TraDecoder {
  const TraDecoder._();
  static const TraDecoder instance = TraDecoder._();

  /// Reshapes one timetable entry into the card-facing view model, preserving
  /// the origin/destination station names and the display travel-time string
  /// that the parsed-minutes [TraTimetableItem] does not carry.
  RailTimetableView decodeTimetableCard(tra_timetable t) => RailTimetableView(
    trainNo: t.trainNo,
    trainType: t.trainTypeName,
    originName: t.startingStationName,
    destinationName: t.endingStationName,
    departureTime: t.startingTime,
    arrivalTime: t.endingTime,
    travelTime: t.travelTime,
  );

  List<TraLiveBoardItem> decodeLiveBoard(tra_LiveBoards board) {
    return board.items
        .map(
          (t) => TraLiveBoardItem(
            trainNo: t.trainNo,
            direction: t.direction ? '北上' : '南下',
            trainType: t.trainTypeName,
            destStation: t.endingStationName,
            departureTime: t.scheduledDepartureTime,
            delayMinutes: t.delay,
          ),
        )
        .toList();
  }

  TraFare decodeFare(TraFareItem f) =>
      TraFare(ticketType: f.ticketType, price: f.price);

  /// delay is a map of trainNo to delayMinutes
  Map<String, int> decodeDelayMap(tra_delays delays) => delays.delay;

  List<TraStopTime> decodeStops(tra_stoptimes stoptimes) {
    return stoptimes.items
        .map(
          (s) => TraStopTime(
            stationName: s.stationName,
            arrivalTime: s.arrivalTime,
            departureTime: s.departureTime,
            sequence: s.stopSequence,
          ),
        )
        .toList();
  }

  List<TraTimetableItem> decodeTimetable(tra_timetables timetables) {
    return timetables.items
        .map(
          (t) => TraTimetableItem(
            trainNo: t.trainNo,
            trainType: t.trainTypeName,
            departureTime: t.startingTime,
            arrivalTime: t.endingTime,
            travelMinutes: _parseTravelMinutes(t.travelTime),
            delayMinutes: 0,
            hasBike: false,
            hasDiningCar: false,
            isDisabledFriendly: false,
            hasBreastfeeding: false,
            remark: t.note,
          ),
        )
        .toList();
  }

  int _parseTravelMinutes(String travel) {
    if (travel.contains(':')) {
      final parts = travel.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        return h * 60 + m;
      }
    }
    return int.tryParse(travel.replaceAll('分', '')) ?? 0;
  }
}
