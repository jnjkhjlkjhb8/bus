import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/models/eta_format.dart';

void main() {
  group('etaCeilMinutes', () {
    test('ceils partial minutes up', () {
      expect(etaCeilMinutes(1), 1);
      expect(etaCeilMinutes(59), 1);
      expect(etaCeilMinutes(60), 1);
      expect(etaCeilMinutes(61), 2);
      expect(etaCeilMinutes(120), 2);
    });

    test('non-positive seconds are zero', () {
      expect(etaCeilMinutes(0), 0);
      expect(etaCeilMinutes(-1), 0);
    });

    // Cross-mode consistency: bus (was ceil) and metro (was round) must now
    // agree for every input. 90s -> 2 min both ways; round() would give 2 as
    // well, but 30s must be 1 (ceil) not 0 (round) -- this is the guard.
    test('same seconds map to same minutes across modes (ceil, not round)', () {
      expect(etaCeilMinutes(30), 1); // round() would be 0 -- rejected
      expect(etaCeilMinutes(89), 2); // round() would be 1 -- rejected
    });
  });

  group('busStopDisplayStatus', () {
    test('arriving when stopStatus 0 and no estimate', () {
      expect(
        busStopDisplayStatus(estimateSeconds: 0, stopStatus: 0),
        BusStopDisplayStatus.arriving,
      );
    });
    test('departingSoon under a minute', () {
      expect(
        busStopDisplayStatus(estimateSeconds: 45, stopStatus: 0),
        BusStopDisplayStatus.departingSoon,
      );
    });
    test('minutes when estimate is a minute or more', () {
      expect(
        busStopDisplayStatus(estimateSeconds: 61, stopStatus: 0),
        BusStopDisplayStatus.minutes,
      );
    });
    test('status codes map exhaustively', () {
      expect(
        busStopDisplayStatus(estimateSeconds: -1, stopStatus: 1),
        BusStopDisplayStatus.notDeparted,
      );
      expect(
        busStopDisplayStatus(estimateSeconds: -1, stopStatus: 2),
        BusStopDisplayStatus.trafficControl,
      );
      expect(
        busStopDisplayStatus(estimateSeconds: -1, stopStatus: 3),
        BusStopDisplayStatus.lastBusPassed,
      );
      expect(
        busStopDisplayStatus(estimateSeconds: -1, stopStatus: 4),
        BusStopDisplayStatus.notOperating,
      );
      expect(
        busStopDisplayStatus(estimateSeconds: -1, stopStatus: 9),
        BusStopDisplayStatus.unknown,
      );
    });
  });

  group('busStopDisplayLabel', () {
    test('minutes label uses ceil', () {
      expect(
        busStopDisplayLabel(
          estimateSeconds: 61,
          stopStatus: 0,
          nextBusTime: '',
        ),
        '2分',
      );
    });
    test('arriving label', () {
      expect(
        busStopDisplayLabel(estimateSeconds: 0, stopStatus: 0, nextBusTime: ''),
        '進站中',
      );
    });
    test('clock label parsed from nextBusTime', () {
      expect(
        busStopDisplayLabel(
          estimateSeconds: -1,
          stopStatus: 1,
          nextBusTime: '2026-06-18T08:15:00+08:00',
        ),
        '08:15',
      );
      expect(
        busStopDisplayLabel(
          estimateSeconds: -1,
          stopStatus: 1,
          nextBusTime: '8:05:00',
        ),
        '08:05',
      );
    });
    test('status label when no estimate and no clock', () {
      expect(
        busStopDisplayLabel(
          estimateSeconds: -1,
          stopStatus: 3,
          nextBusTime: '',
        ),
        '末班已過',
      );
      expect(
        busStopDisplayLabel(
          estimateSeconds: -1,
          stopStatus: 9,
          nextBusTime: '',
        ),
        isNull,
      );
    });
  });
}
