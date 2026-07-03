import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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
