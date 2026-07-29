import 'package:wheres_the_bus/data/generated/thsr.pb.dart';
import 'package:wheres_the_bus/data/models/rail_station_board.dart';
import 'package:wheres_the_bus/data/models/rail_timetable_view.dart';
import 'package:wheres_the_bus/data/models/thsr_models.dart';

class ThsrDecoder {
  const ThsrDecoder._();
  static const ThsrDecoder instance = ThsrDecoder._();

  /// One station's next departures. The train type is left empty rather than
  /// filled with '高鐵': THSR runs a single class, so a chip repeating the
  /// system on every row of a THSR board would say nothing.
  List<RailStationDeparture> decodeStationBoard(thsr_station_board board) =>
      board.items
          .map(
            (d) => RailStationDeparture(
              trainNo: d.trainNo,
              trainType: '',
              destination: d.destinationStationName,
              departureTime: d.departureTime,
              serviceDate: d.trainDate,
              remark: d.note,
            ),
          )
          .toList();

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
            isOvernight: t.overnight,
          ),
        )
        .toList();
  }

  /// One fare per fare class × cabin class — see [thsrFareFor].
  List<ThsrFare> decodeFares(thsa_fares fares) => fares.items
      .map(
        (f) => ThsrFare(
          fareClass: f.fareClass,
          cabinClass: f.cabinClas,
          price: f.price,
        ),
      )
      .toList();

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
