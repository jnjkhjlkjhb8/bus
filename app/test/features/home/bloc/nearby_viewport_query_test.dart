import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_viewport_query.dart';

void main() {
  group('nearbyRadiusForViewport', () {
    test('derives the radius from center to the farthest corner', () {
      const center = LatLng(25.0330, 121.5654);
      // ~0.01 degrees latitude ≈ 1.1 km; northeast is the farthest corner.
      final bounds = LatLngBounds(
        southwest: const LatLng(25.0230, 121.5554),
        northeast: const LatLng(25.0430, 121.5754),
      );

      final radius = nearbyRadiusForViewport(center: center, bounds: bounds);

      final expected = haversineMeters(center, bounds.northeast);
      expect(radius, closeTo(expected, 1));
    });

    test('clamps to the backend max radius for a large viewport', () {
      const center = LatLng(25.0330, 121.5654);
      final bounds = LatLngBounds(
        southwest: const LatLng(24, 120.5),
        northeast: const LatLng(26, 122.5),
      );

      final radius = nearbyRadiusForViewport(center: center, bounds: bounds);

      expect(radius, kNearbyMaxRadiusMeters);
    });

    test('clamps to the minimum radius for a near-zero viewport', () {
      const center = LatLng(25.0330, 121.5654);
      final bounds = LatLngBounds(
        southwest: const LatLng(25.033000001, 121.565400001),
        northeast: const LatLng(25.033000002, 121.565400002),
      );

      final radius = nearbyRadiusForViewport(center: center, bounds: bounds);

      expect(radius, kNearbyMinRadiusMeters);
    });
  });

  group('haversineMeters', () {
    test('is zero for identical points', () {
      const p = LatLng(25.0330, 121.5654);
      expect(haversineMeters(p, p), 0);
    });

    test('one degree of latitude is about 111 km', () {
      const a = LatLng(25, 121);
      const b = LatLng(26, 121);
      final meters = haversineMeters(a, b);
      expect(meters, closeTo(111195, 500));
    });
  });

  group('NearbyViewportQuery', () {
    const center = LatLng(25.0330, 121.5654);
    const nearby = LatLng(25.0331, 121.5655); // well under 200 m away
    const far = LatLng(25.1330, 121.6654); // well over 200 m away

    test('always queries when nothing has succeeded yet', () {
      const query = NearbyViewportQuery();
      expect(query.shouldQuery(center), isTrue);
    });

    test('suppresses a query near the last successful center', () {
      final query = const NearbyViewportQuery().withSuccess(center);
      expect(query.shouldQuery(nearby), isFalse);
    });

    test('still queries when far from the last successful center', () {
      final query = const NearbyViewportQuery().withSuccess(center);
      expect(query.shouldQuery(far), isTrue);
    });

    test(
      'a failed attempt does not suppress a retry at the same center — only '
      'a successful one does',
      () {
        // Attempt (and implicitly fail — no withSuccess call) at `center`.
        final afterFailedAttempt = const NearbyViewportQuery().withAttempted(
          center,
        );

        // The camera settles back on the same spot; since the prior attempt
        // never succeeded, this must still be considered worth querying.
        expect(afterFailedAttempt.shouldQuery(center), isTrue);
      },
    );

    test('lastAttempted and lastSuccessful update independently', () {
      final query = const NearbyViewportQuery()
          .withAttempted(far)
          .withSuccess(center);

      expect(query.lastAttempted, far);
      expect(query.lastSuccessful, center);
    });
  });
}
