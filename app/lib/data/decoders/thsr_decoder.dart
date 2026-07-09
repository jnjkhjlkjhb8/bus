import 'package:wheres_the_car/data/generated/thsr.pb.dart';
import 'package:wheres_the_car/data/models/rail_timetable_view.dart';
import 'package:wheres_the_car/data/models/thsr_models.dart';

class ThsrDecoder {
  const ThsrDecoder._();
  static const ThsrDecoder instance = ThsrDecoder._();

  /// Reshapes one THSR timetable entry into the card-facing view model. THSR
  /// has a single service class, so the type label is fixed rather than
  /// carried on the wire.
  RailTimetableView decodeTimetableCard(thsa_timetable t) => RailTimetableView(
    trainNo: t.trainNo,
    trainType: '高鐵',
    originName: t.startingStationName,
    destinationName: t.endingStationName,
    departureTime: t.startingTime,
    arrivalTime: t.endingTime,
    travelTime: t.travelTime,
  );

  List<ThsrTimetableItem> decodeTimetable(thsr_timetables timetables) {
    return timetables.items
        .map(
          (t) => ThsrTimetableItem(
            trainNo: t.trainNo,
            departureTime: t.startingTime,
            arrivalTime: t.endingTime,
            travelMinutes: _parseTravelMinutes(t.travelTime),
            delayMinutes: 0,
            remark: t.note,
          ),
        )
        .toList();
  }

  ThsrFare decodeFare(thsa_fare f) =>
      ThsrFare(fareClass: f.fareClass, price: f.price);

  List<ThsrStopTime> decodeStopTimes(thsr_stoptimes stoptimes) {
    return stoptimes.items
        .map(
          (s) => ThsrStopTime(
            stationName: s.stationName,
            arrivalTime: s.arrivalTime,
            departureTime: s.departureTime,
            sequence: s.stopSequence,
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
