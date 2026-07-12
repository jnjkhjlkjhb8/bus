import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';

class MapMarkers {
  const MapMarkers._();

  static final Map<String, BitmapDescriptor> _cache = {};

  static double _dpr = 3;

  static void configure(double devicePixelRatio) {
    if (devicePixelRatio > 0) _dpr = devicePixelRatio;
  }

  static Future<BitmapDescriptor> svgAsset(
    String asset, {
    double size = 36,
  }) {
    return _memo('svg:$asset:$size', () async {
      final info = await vg.loadPicture(SvgAssetLoader(asset), null);
      final px = (size * _dpr).round();
      final image = await _record(px, (canvas) {
        final scale = px / info.size.width;
        canvas
          ..scale(scale)
          ..drawPicture(info.picture);
      });
      info.picture.dispose();
      return _toBitmap(image);
    });
  }

  /// Live-vehicle marker: the bus sprite grounded with a soft contact shadow
  /// so it sits on the map instead of floating. Works with the existing
  /// turntable sprites; shape/scale are untouched.
  static Future<BitmapDescriptor> busMarker(
    String asset, {
    double size = 54,
  }) {
    return _memo('bus:$asset:$size', () async {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final sprite = (await codec.getNextFrame()).image;
      final px = (size * _dpr).round();
      final image = await _record(px, (canvas) {
        // Contact shadow: soft ellipse under the bus.
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(px * 0.5, px * 0.72),
            width: px * 0.68,
            height: px * 0.15,
          ),
          Paint()
            ..color = const Color(0x50000000)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, px * 0.035),
        );
        // Sprite, nudged up so its wheels meet the shadow.
        final side = px * 0.98;
        canvas.drawImageRect(
          sprite,
          Rect.fromLTWH(
            0,
            0,
            sprite.width.toDouble(),
            sprite.height.toDouble(),
          ),
          Rect.fromLTWH(
            (px - side) / 2,
            (px - side) / 2 - px * 0.02,
            side,
            side,
          ),
          Paint()..filterQuality = FilterQuality.high,
        );
      });
      sprite.dispose();
      return _toBitmap(image);
    });
  }

  static Future<BitmapDescriptor> dot(
    Color color, {
    double size = 18,
    Color? ring,
  }) {
    final key = 'dot:${color.toARGB32()}:$size:${ring?.toARGB32()}';
    return _memo(key, () async {
      final px = (size * _dpr).round();
      final r = px / 2;
      final image = await _record(px, (canvas) {
        final c = Offset(r, r);
        if (ring != null) {
          canvas
            ..drawCircle(c, r, Paint()..color = ring)
            ..drawCircle(c, r * 0.82, Paint()..color = color);
        } else {
          canvas.drawCircle(c, r, Paint()..color = color);
        }
      });
      return _toBitmap(image);
    });
  }

  /// Filled disc with a small concentric inner dot — the heaviest node in the
  /// plan-preview marker language, used for the destination. [fill] is the
  /// outer body, [inner] the centre dot.
  static Future<BitmapDescriptor> targetDot(
    Color fill,
    Color inner, {
    double size = 22,
  }) {
    final key = 'target:${fill.toARGB32()}:${inner.toARGB32()}:$size';
    return _memo(key, () async {
      final px = (size * _dpr).round();
      final r = px / 2;
      final image = await _record(px, (canvas) {
        final c = Offset(r, r);
        canvas
          ..drawCircle(c, r, Paint()..color = fill)
          ..drawCircle(c, r * 0.32, Paint()..color = inner);
      });
      return _toBitmap(image);
    });
  }

  static Future<BitmapDescriptor> etaStop(
    String text, {
    double size = 44,
    Color ring = AppTheme.inkLight,
    Color fill = Colors.white,
    Color textColor = AppTheme.inkLight,
  }) {
    final key = 'eta:$text:$size:${ring.toARGB32()}';
    return _memo(key, () async {
      final px = (size * _dpr).round();
      final center = Offset(px / 2, px / 2);
      final stroke = px * (5 / 44);
      final radius = px / 2 - stroke / 2;
      final image = await _record(px, (canvas) {
        canvas
          ..drawCircle(center, radius, Paint()..color = fill)
          ..drawCircle(
            center,
            radius,
            Paint()
              ..color = ring
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke,
          );
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: textColor,
              fontSize: px * (text.length > 2 ? 0.30 : 0.42),
              fontWeight: FontWeight.w700,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          center - Offset(painter.width / 2, painter.height / 2),
        );
      });
      return _toBitmap(image);
    });
  }

  /// Same ring as [etaStop] but painted with a Material [icon] glyph instead of
  /// text — used for not-yet-departed stops, whose arrival is a scheduled clock
  /// time rather than a live countdown.
  static Future<BitmapDescriptor> etaStopIcon(
    IconData icon, {
    double size = 44,
    Color ring = AppTheme.inkLight,
    Color fill = Colors.white,
    Color iconColor = AppTheme.inkLight,
  }) {
    final key = 'etaicon:${icon.codePoint}:$size:${ring.toARGB32()}';
    return _memo(key, () async {
      final px = (size * _dpr).round();
      final center = Offset(px / 2, px / 2);
      final stroke = px * (5 / 44);
      final radius = px / 2 - stroke / 2;
      final image = await _record(px, (canvas) {
        canvas
          ..drawCircle(center, radius, Paint()..color = fill)
          ..drawCircle(
            center,
            radius,
            Paint()
              ..color = ring
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke,
          );
        final painter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              color: iconColor,
              fontSize: px * 0.5,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          center - Offset(painter.width / 2, painter.height / 2),
        );
      });
      return _toBitmap(image);
    });
  }

  /// User-position puck for active navigation: a solid ink disc inside a thin
  /// card-colored ring, with an ink heading arrow (matching the recenter button
  /// glyph) knocked out in the ring color and a soft drop shadow. [disc] is the
  /// solid body (ink), [ring] the outer ring / arrow glyph (card color). The
  /// glyph points up (bitmap north); rendered as a flat marker rotated by the
  /// camera bearing so it tracks the travel/heading direction on the map.
  /// Proportions follow the 48px mock: outer ring radius 20, ink disc radius 17
  /// (3px ring), arrow ~26/48 of the marker.
  static Future<BitmapDescriptor> navArrow(
    Color disc,
    Color ring, {
    double size = 48,
  }) {
    final key = 'navarrow:${disc.toARGB32()}:${ring.toARGB32()}:$size';
    return _memo(key, () async {
      final px = (size * _dpr).round();
      final center = Offset(px / 2, px / 2);
      final rOuter = px * (20 / 48);
      final rInk = px * (17 / 48);
      final image = await _record(px, (canvas) {
        canvas
          ..drawCircle(
            center + Offset(0, px * (2.5 / 48)),
            rOuter,
            Paint()
              ..color = const Color(0x2E000000)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, px * (3 / 48)),
          )
          ..drawCircle(center, rOuter, Paint()..color = ring)
          ..drawCircle(center, rInk, Paint()..color = disc);
        final painter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(Icons.navigation_rounded.codePoint),
            style: TextStyle(
              color: ring,
              fontSize: px * (26 / 48),
              fontFamily: Icons.navigation_rounded.fontFamily,
              package: Icons.navigation_rounded.fontPackage,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          center - Offset(painter.width / 2, painter.height / 2),
        );
      });
      return _toBitmap(image);
    });
  }

  static Future<BitmapDescriptor> _memo(
    String key,
    Future<BitmapDescriptor> Function() build,
  ) async {
    final cacheKey = '$key:$_dpr';
    final hit = _cache[cacheKey];
    if (hit != null) return hit;
    final made = await build();
    _cache[cacheKey] = made;
    return made;
  }

  static Future<ui.Image> _record(int px, void Function(Canvas) draw) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    draw(canvas);
    return recorder.endRecording().toImage(px, px);
  }

  static Future<BitmapDescriptor> _toBitmap(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return BitmapDescriptor.bytes(
      data!.buffer.asUint8List(),
      imagePixelRatio: _dpr,
    );
  }
}
