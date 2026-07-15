import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_car/app/router/app_routes.dart';

void main() {
  group('AppRoutes.busRoute', () {
    test('encodes the subRouteUid path segment', () {
      expect(AppRoutes.busRoute('TPE 307/a'), '/bus/route/TPE%20307%2Fa');
    });

    test('leaves plain ids untouched', () {
      expect(AppRoutes.busRoute('TPE10132'), '/bus/route/TPE10132');
    });
  });

  group('AppRoutes.busStopLocation', () {
    test('round-trips name, id, and city through the URI', () {
      final location = AppRoutes.busStopLocation(
        stopName: '台北車站',
        stopId: 'S18',
        city: 'Taipei',
      );
      final uri = Uri.parse(location);
      expect(uri.path, AppRoutes.busStop);
      expect(uri.queryParameters['name'], '台北車站');
      expect(uri.queryParameters['id'], 'S18');
      expect(uri.queryParameters['city'], 'Taipei');
    });

    test('omits absent optional parameters', () {
      final uri = Uri.parse(AppRoutes.busStopLocation(stopName: '南港'));
      expect(uri.queryParameters['name'], '南港');
      expect(uri.queryParameters.containsKey('id'), isFalse);
      expect(uri.queryParameters.containsKey('city'), isFalse);
    });
  });

  group('AppRoutes.bikeStationLocation', () {
    test('carries the station uid as a query parameter', () {
      final uri = Uri.parse(
        AppRoutes.bikeStationLocation(stationUid: 'TPE0001'),
      );
      expect(uri.path, AppRoutes.bikeStation);
      expect(uri.queryParameters['uid'], 'TPE0001');
    });
  });

  group('BusStopRouteArgs.from', () {
    test('parses a cold deep link from query parameters alone', () {
      final args = BusStopRouteArgs.from(
        const {'name': '台北車站', 'id': 'S18', 'city': 'Taipei'},
        null,
      );
      expect(args, isNotNull);
      expect(args!.stopName, '台北車站');
      expect(args.stopId, 'S18');
      expect(args.city, 'Taipei');
    });

    test('optional id and city may be absent', () {
      final args = BusStopRouteArgs.from(const {'name': '南港'}, null);
      expect(args, isNotNull);
      expect(args!.stopName, '南港');
      expect(args.stopId, isNull);
      expect(args.city, isNull);
    });

    test('falls back to a legacy extra map when the query is empty', () {
      final args = BusStopRouteArgs.from(const {}, {
        'stopName': '南港',
        'stopId': 'S2',
        'city': 'Taipei',
      });
      expect(args, isNotNull);
      expect(args!.stopName, '南港');
      expect(args.stopId, 'S2');
      expect(args.city, 'Taipei');
    });

    test('returns null when neither query nor extra identify a stop', () {
      expect(BusStopRouteArgs.from(const {}, null), isNull);
      expect(BusStopRouteArgs.from(const {}, {'stopId': 'S2'}), isNull);
      expect(BusStopRouteArgs.from(const {}, 'not a map'), isNull);
    });
  });

  group('BikeStationRouteArgs.from', () {
    test('parses a cold deep link from query parameters alone', () {
      final args = BikeStationRouteArgs.from(const {'uid': 'TPE0001'}, null);
      expect(args, isNotNull);
      expect(args!.stationUid, 'TPE0001');
    });

    test('falls back to a legacy extra map when the query is empty', () {
      final args = BikeStationRouteArgs.from(const {}, {
        'stationUid': 'TPE0002',
      });
      expect(args, isNotNull);
      expect(args!.stationUid, 'TPE0002');
    });

    test('returns null when neither query nor extra identify a station', () {
      expect(BikeStationRouteArgs.from(const {}, null), isNull);
      expect(BikeStationRouteArgs.from(const {}, {'uid': 1}), isNull);
    });
  });
}
