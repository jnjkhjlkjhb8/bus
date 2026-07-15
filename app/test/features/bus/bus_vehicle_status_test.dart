import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/features/bus/bus_vehicle_status.dart';

BusVehiclePosition _v({int duty = 0, int bus = 0, int gps = 0}) =>
    BusVehiclePosition(
      plate: 'AAA-1',
      lat: 25,
      lon: 121,
      azimuth: 0,
      dutyStatus: duty,
      busStatus: bus,
      gpsTimeUnix: gps,
    );

void main() {
  group('busVehicleStatus', () {
    test('normal driving reads as operating', () {
      final s = busVehicleStatus(_v());
      expect(s.label, '營運中');
      expect(s.tone, BusStatusTone.normal);
    });

    test('ending duty overrides the driving state', () {
      final s = busVehicleStatus(_v(duty: 2, bus: 3));
      expect(s.label, '收班中');
      expect(s.tone, BusStatusTone.muted);
    });

    test('breakdown is a warning', () {
      expect(busVehicleStatus(_v(bus: 2)).tone, BusStatusTone.warning);
    });

    test('congestion is a notice', () {
      final s = busVehicleStatus(_v(bus: 3));
      expect(s.label, '塞車');
      expect(s.tone, BusStatusTone.notice);
    });

    test('unknown code falls back to operating', () {
      expect(busVehicleStatus(_v(bus: 255)).label, '營運中');
    });
  });

  group('busGpsAge', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1_000_000 * 1000);
    int at(int secondsAgo) => 1_000_000 - secondsAgo;

    test('missing fix reads as unlocated', () {
      final a = busGpsAge(0, now);
      expect(a.text, '無定位');
      expect(a.stale, isTrue);
    });

    test('very recent reads as 剛剛', () {
      expect(busGpsAge(at(5), now).text, '剛剛');
    });

    test('seconds bucket', () {
      expect(busGpsAge(at(22), now).text, '22秒前');
    });

    test('minutes bucket', () {
      expect(busGpsAge(at(90), now).text, '1分前');
    });

    test('past 3 minutes is stale', () {
      final a = busGpsAge(at(200), now);
      expect(a.text, '定位延遲');
      expect(a.stale, isTrue);
    });
  });
}
