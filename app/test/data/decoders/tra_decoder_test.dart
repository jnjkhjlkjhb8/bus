import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/decoders/tra_decoder.dart';
import 'package:wheres_the_car/data/generated/tra.pb.dart';

const TraDecoder _decoder = TraDecoder.instance;

/// Exercises the private `_parseTravelMinutes` (tra_decoder.dart:59-68)
/// indirectly through the public `decodeTimetable`, via a single-item
/// timetable that isolates the travelTime field under test.
int _travelMinutesFor(String travelTime) {
  final out = _decoder.decodeTimetable(
    tra_timetables(
      items: [tra_timetable(trainNo: 'T1', travelTime: travelTime)],
    ),
  );
  return out.single.travelMinutes;
}

void main() {
  group('_parseTravelMinutes via decodeTimetable', () {
    test("'1:30' is read as hours:minutes -> 90", () {
      // travelTime.split(':') -> ['1', '30'], so this is h*60+m = 90, not a
      // hours-only truncation. Pinning the correct behavior; the plan
      // flagged this as a candidate bug, but the current code does take
      // both parts.
      expect(_travelMinutesFor('1:30'), 90);
    });

    test("'90分' strips the suffix and parses to 90", () {
      expect(_travelMinutesFor('90分'), 90);
    });

    // '1時30分' has no ':' so it falls to the '分'-stripping branch, which
    // only strips '分' and leaves '1時30' -- int.tryParse fails on that and
    // the fallback `?? 0` fires. This silently drops a valid travel time to
    // 0 rather than parsing the hour. Pinning current (wrong-looking)
    // behavior -- see findings, not fixed here.
    test("'1時30分' (hour+minute suffix form) is not parsed and falls back to 0",
        () {
      expect(_travelMinutesFor('1時30分'), 0);
    });

    test('empty string does not throw and yields 0', () {
      expect(_travelMinutesFor(''), 0);
    });

    test("'N/A' does not throw and yields 0", () {
      expect(_travelMinutesFor('N/A'), 0);
    });
  });

  group('decodeTimetable', () {
    test('maps two items preserving order and fields', () {
      final out = _decoder.decodeTimetable(
        tra_timetables(
          items: [
            tra_timetable(
              trainNo: '123',
              trainTypeName: '自強',
              startingTime: '08:00',
              endingTime: '10:30',
              travelTime: '2:30',
              note: '',
            ),
            tra_timetable(
              trainNo: '456',
              trainTypeName: '莒光',
              startingTime: '09:15',
              endingTime: '12:00',
              travelTime: '165分',
              note: '假日行駛',
            ),
          ],
        ),
      );

      expect(out, hasLength(2));

      expect(out[0].trainNo, '123');
      expect(out[0].trainType, '自強');
      expect(out[0].departureTime, '08:00');
      expect(out[0].arrivalTime, '10:30');
      expect(out[0].travelMinutes, 150);
      expect(out[0].remark, '');

      expect(out[1].trainNo, '456');
      expect(out[1].trainType, '莒光');
      expect(out[1].departureTime, '09:15');
      expect(out[1].arrivalTime, '12:00');
      expect(out[1].travelMinutes, 165);
      expect(out[1].remark, '假日行駛');
    });

    test('empty timetable yields an empty list without throwing', () {
      expect(_decoder.decodeTimetable(tra_timetables()), isEmpty);
    });
  });

  group('decodeTimetableCard', () {
    test('carries station names, type, and the raw travel-time string', () {
      final view = _decoder.decodeTimetableCard(
        tra_timetable(
          trainNo: '123',
          trainTypeName: '自強',
          startingStationName: '臺北',
          endingStationName: '花蓮',
          startingTime: '08:00',
          endingTime: '10:30',
          travelTime: '2:30',
        ),
      );
      expect(view.trainNo, '123');
      expect(view.trainType, '自強');
      expect(view.originName, '臺北');
      expect(view.destinationName, '花蓮');
      expect(view.departureTime, '08:00');
      expect(view.arrivalTime, '10:30');
      // Kept verbatim, not parsed to minutes.
      expect(view.travelTime, '2:30');
    });
  });
}
