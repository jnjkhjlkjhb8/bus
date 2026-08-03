import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_bus/shared/map/marker_factory.dart';

/// The ways [MapMarkers.busMark] can be wrong without looking wrong.
///
/// The mark is published with `Marker.rotation`, which turns the bitmap about
/// its anchor — so the body has to sit dead centre in a square canvas. Get that
/// wrong and a bus doesn't point wrong, it *orbits* its own position as it
/// turns, which only shows up on a vehicle that is actually changing heading.
/// An incomplete cache key serves the bitmap built for another state, so a bus
/// that has just broken down keeps painting its plain ink body.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // configure() is process-global; leaving a scale set would silently resize
  // every later test's bitmaps. The scaler is left at its no-scaling default,
  // which is the reset.
  setUp(() => MapMarkers.configure(devicePixelRatio: 3));

  Future<BitmapDescriptor> build({
    Color body = Colors.black,
    Color halo = Colors.white,
    Color? ring,
    bool showHeading = true,
    bool shadow = true,
    double size = 28,
  }) => MapMarkers.busMark(
    body: body,
    halo: halo,
    ring: ring,
    showHeading: showHeading,
    shadow: shadow,
    size: size,
  );

  Future<ui.Size> sizeOf(BitmapDescriptor descriptor) async {
    final codec = await ui.instantiateImageCodec(
      (descriptor as BytesMapBitmap).byteData,
    );
    final image = (await codec.getNextFrame()).image;
    final size = ui.Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    return size;
  }

  group('canvas', () {
    test('is square, so rotation turns it instead of orbiting it', () async {
      // Every variant, because the ring and the shadow each change how much
      // room the mark needs around the body, and a canvas sized to fit only
      // what a given variant draws would stop being square.
      final variants = {
        'default': build(),
        'no heading': build(showHeading: false),
        'ringed': build(ring: Colors.orange),
        'shadowless': build(shadow: false),
        'larger': build(size: 40),
      };
      for (final entry in variants.entries) {
        final size = await sizeOf(await entry.value);
        expect(size.width, greaterThan(0));
        expect(size.height, size.width, reason: '${entry.key} is not square');
      }
    });

    test('leaves room for the halo and the shadow', () async {
      // 24 units of half-extent around a 14-unit radius: body + the halo's 4 +
      // the shadow's offset and blur. Trimmed any tighter and the shadow clips
      // along the bottom edge; every transparent pixel past it is texture the
      // map uploads per vehicle. 28pt body at dpr 3 => 48 units * 3.
      expect(await sizeOf(await build()), const ui.Size(144, 144));
    });

    test('scales with size', () async {
      final base = await sizeOf(await build());
      final bigger = await sizeOf(await build(size: 42));
      expect(bigger.width / base.width, closeTo(1.5, 0.02));
    });
  });

  group('text scale', () {
    test('does not grow with the text setting', () async {
      // Deliberately unlike stopMarker: the mark carries no text, so the text
      // setting has nothing to scale here. Growing it would only push the
      // vehicle layer over the stop plates it annotates.
      final base = await sizeOf(await build());
      MapMarkers.configure(
        devicePixelRatio: 3,
        textScaler: const TextScaler.linear(1.3),
      );
      expect(await sizeOf(await build()), base);
    });
  });

  group('cache key', () {
    test('identical inputs reuse the same bitmap', () async {
      expect(await build(), same(await build()));
    });

    test('every input discriminates the cache entry', () async {
      final base = await build();
      final variants = {
        'body': build(body: Colors.red),
        'halo': build(halo: Colors.black),
        'ring': build(ring: Colors.orange),
        'showHeading': build(showHeading: false),
        'shadow': build(shadow: false),
        'size': build(size: 32),
      };
      for (final entry in variants.entries) {
        expect(
          await entry.value,
          isNot(same(base)),
          reason: '${entry.key} is not part of the cache key',
        );
      }
    });

    test('the device pixel ratio reaches the key', () async {
      final atThree = await build();
      MapMarkers.configure(devicePixelRatio: 2);
      expect(await build(), isNot(same(atThree)));
    });
  });
}
