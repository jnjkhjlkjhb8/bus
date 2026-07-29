import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/data/decoders/thsr_decoder.dart';
import 'package:wheres_the_bus/data/generated/thsr.pb.dart';

const ThsrDecoder _decoder = ThsrDecoder.instance;

void main() {
  group('decodeTimetableCard', () {
    test('fixes the type label to 高鐵 and preserves the rest verbatim', () {
      final view = _decoder.decodeTimetableCard(
        thsa_timetable(
          trainNo: '0821',
          startingStationName: '南港',
          endingStationName: '左營',
          startingTime: '09:00',
          endingTime: '10:36',
          travelTime: '1:36',
        ),
      );
      expect(view.trainNo, '0821');
      // THSR has a single service class; the wire carries no type name.
      expect(view.trainType, '高鐵');
      expect(view.originName, '南港');
      expect(view.destinationName, '左營');
      expect(view.departureTime, '09:00');
      expect(view.arrivalTime, '10:36');
      expect(view.travelTime, '1:36');
    });
  });
}
