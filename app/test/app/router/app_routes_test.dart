import 'package:flutter_test/flutter_test.dart';
import 'package:wheres_the_bus/app/router/app_routes.dart';

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
      expect(uri.queryParameters.containsKey('lat'), isFalse);
      expect(uri.queryParameters.containsKey('lon'), isFalse);
    });

    test('carries the first-paint coordinates when supplied', () {
      final uri = Uri.parse(
        AppRoutes.busStopLocation(
          stopName: '南港',
          lat: 25.053,
          lon: 121.6067,
        ),
      );
      expect(uri.queryParameters['lat'], '25.053');
      expect(uri.queryParameters['lon'], '121.6067');
    });
  });

  group('AppRoutes.bikeStationLocation', () {
    test('carries the station uid as a query parameter', () {
      final uri = Uri.parse(
        AppRoutes.bikeStationLocation(stationUid: 'TPE0001'),
      );
      expect(uri.path, AppRoutes.bikeStation);
      expect(uri.queryParameters['uid'], 'TPE0001');
      expect(uri.queryParameters.containsKey('name'), isFalse);
    });

    test('carries the first-paint hints when supplied', () {
      final uri = Uri.parse(
        AppRoutes.bikeStationLocation(
          stationUid: 'TPE0001',
          name: '捷運市政府站',
          lat: 25.0408,
          lon: 121.5679,
        ),
      );
      expect(uri.queryParameters['name'], '捷運市政府站');
      expect(uri.queryParameters['lat'], '25.0408');
      expect(uri.queryParameters['lon'], '121.5679');
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
      expect(args.lat, isNull);
      expect(args.lon, isNull);
    });

    test('parses the first-paint coordinates, unparseable ones stay null', () {
      final args = BusStopRouteArgs.from(
        const {'name': '南港', 'lat': '25.053', 'lon': '121.6067'},
        null,
      );
      expect(args!.lat, 25.053);
      expect(args.lon, 121.6067);
      final bad = BusStopRouteArgs.from(
        const {'name': '南港', 'lat': 'nope', 'lon': ''},
        null,
      );
      expect(bad!.lat, isNull);
      expect(bad.lon, isNull);
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
      expect(args.name, isNull);
      expect(args.lat, isNull);
    });

    test('parses the first-paint hints when present', () {
      final args = BikeStationRouteArgs.from(
        const {
          'uid': 'TPE0001',
          'name': '捷運市政府站',
          'lat': '25.0408',
          'lon': '121.5679',
        },
        null,
      );
      expect(args!.name, '捷運市政府站');
      expect(args.lat, 25.0408);
      expect(args.lon, 121.5679);
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

  group('GoRouteArgs', () {
    test('round-trips a destination through the URL builder', () {
      final uri = Uri.parse(
        AppRoutes.goToDestination(
          name: '北門國小',
          lat: 24.9928,
          lon: 121.3009,
        ),
      );
      expect(uri.path, AppRoutes.go);

      final args = GoRouteArgs.from(uri.queryParameters);
      expect(args, isNotNull);
      expect(args!.name, '北門國小');
      expect(args.lat, 24.9928);
      expect(args.lon, 121.3009);
    });

    test('a partial or malformed seed opens the planner empty, not broken', () {
      expect(GoRouteArgs.from(const {}), isNull);
      expect(
        GoRouteArgs.from(const {'destName': '北門國小', 'destLat': '24.99'}),
        isNull,
      );
      expect(
        GoRouteArgs.from(const {
          'destName': '北門國小',
          'destLat': 'x',
          'destLon': '121.3',
        }),
        isNull,
      );
      expect(
        GoRouteArgs.from(const {
          'destName': '',
          'destLat': '24.99',
          'destLon': '121.3',
        }),
        isNull,
      );
    });
  });
}
