import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';

class MapMarkers {
  const MapMarkers._();

  // LRU-bounded: stop plates x live states x themes, plus selected capsules,
  // would otherwise grow the cache monotonically for the life of the app. Sized
  // so one frame of the longest route plus its vehicles fits without evicting
  // itself — asserted by stop_marker_test.
  static const int _cacheCap = 256;
  static final LinkedHashMap<String, Object> _cache =
      LinkedHashMap<String, Object>();

  // Bubbles get their own cache because their key carries the GPS-freshness
  // text, which changes every second through the 15–59 s window. Sharing the
  // main cache meant one open bubble minted ~45 write-once entries a minute and
  // evicted the stop plates behind it, so the next live frame had to re-paint
  // plates it had already drawn. Measured on a 66-stop route: frames needing
  // fresh plates cost 53 ms against 2 ms for frames that still had them.
  //
  // Small on purpose: only a pinned bus and any vehicle in a warning state
  // carries a bubble, and each is re-keyed every second regardless.
  static const int _bubbleCacheCap = 16;
  static final LinkedHashMap<String, Object> _bubbleCache =
      LinkedHashMap<String, Object>();

  static double _dpr = 3;

  /// Ceiling on [_textScale]. A 32pt stop disc grows to ~42pt here, which is
  /// about the 44pt touch-target floor — past that, adjacent stops on a dense
  /// urban route start to occlude the line they annotate and the marker stops
  /// being an annotation. Map furniture earns less headroom than body text.
  static const double _maxTextScale = 1.3;

  /// Uniform scale applied to a text-bearing marker's type *and* its geometry,
  /// so the ladder's proportions (ring weights, wash, pill shape — see
  /// `docs/design.md`) survive it instead of a bigger label bursting a fixed
  /// plate.
  ///
  /// Only ever raised, never lowered: the sizes in `docs/design.md` are the
  /// designed minimum, and the map underneath does not shrink with the text
  /// setting, so shrinking its labels buys nothing.
  static double _textScale = 1;

  /// Layout unit — device pixels per logical pixel, enlarged for the text
  /// setting. [_dpr] alone still governs the bitmap's own `imagePixelRatio`, so
  /// a scaled marker is genuinely bigger on screen rather than the same size
  /// rendered at more detail.
  static double get _unit => _dpr * _textScale;

  /// Called from the root `MaterialApp.router` builder, which is the one place
  /// that sees every screen and rebuilds when either value changes. Marker
  /// bitmaps are painted off-tree, so this is how they learn what to paint at.
  static void configure({
    required double devicePixelRatio,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (devicePixelRatio > 0) _dpr = devicePixelRatio;
    // Derived at 12pt because every size these bitmaps paint sits between 10.5
    // and 13.5 — a non-linear scaler is then sampled where it actually applies,
    // rather than at the meaningless 1pt that `scale(1)` would report.
    _textScale = (textScaler.scale(12) / 12).clamp(1.0, _maxTextScale);
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

  /// Live-vehicle mark: a solid disc carrying a heading chevron, painted
  /// north-up and published with `Marker.rotation`, so heading is a continuous
  /// marker property rather than one of 60 pre-rendered perspective frames. A
  /// turning bus turns instead of cutting between 6° steps, one bitmap serves
  /// every heading, and the rotation can be interpolated by the caller's glide.
  ///
  /// **The silhouette stays a plain circle; the heading cue lives inside it.**
  /// That is the load-bearing decision here, arrived at by building the
  /// alternative and looking at it: a disc with a point on one side is pin
  /// geometry, and a pin means *a place*, not a vehicle — at 28pt it renders as
  /// a map pin or a blood drop however the corner where point meets disc is
  /// tuned. A circle also cannot restyle itself as it rotates, the way a
  /// rounded square turns into a diamond at 45°, so a whole fleet keeps one
  /// silhouette while driving.
  ///
  /// States escalate by **fill before colour**, the grammar the stop ladder
  /// already uses (`docs/design.md`) — an ink [body] with no [ring] is a bus
  /// with nothing to report, an ink body plus a status [ring] is a notice, and
  /// a status-coloured [body] is a warning. [halo] is the basemap-coloured
  /// outline every state carries, separating the mark from the route polyline
  /// it rides on; the chevron is drawn in it too, so it reads at full contrast
  /// on every body colour without needing a colour of its own.
  ///
  /// Solid body against the stop ladder's hollow plates is what keeps the two
  /// apart at a glance, so the disc must never be painted hollow here.
  ///
  /// [showHeading] false drops the chevron, for a vehicle with no usable
  /// heading — a plain disc, which is honest. The sprite atlas had no way to
  /// say that, and pointed such a bus at true north.
  ///
  /// Scaled by [_dpr] alone rather than [_unit]: the mark carries no text, so
  /// the text setting has nothing to scale here — the same reasoning as
  /// [busBubble]'s clearance.
  static Future<BitmapDescriptor> busMark({
    required Color body,
    required Color halo,
    Color? ring,
    bool showHeading = true,
    bool shadow = true,
    double size = 28,
  }) {
    final key =
        'busmark:${body.toARGB32()}:${halo.toARGB32()}:${ring?.toARGB32()}:'
        '$showHeading:$shadow:$size';
    return _memo(key, () async {
      // One unit = one logical px at the designed 28pt body, so every constant
      // below reads as its measurement from the design mock.
      final u = size / 28 * _dpr;
      // Square canvas with the body dead centre, because `Marker.rotation`
      // turns the bitmap about its anchor — an off-centre body would orbit its
      // own position as it turned. 24 = radius 14 + the halo's 4 + room for
      // the shadow's offset and blur.
      final half = 24 * u;
      final c = Offset(half, half);
      final disc = Path()..addOval(Rect.fromCircle(center: c, radius: 14 * u));

      Paint outline(Color color, double width) => Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * u;

      final image = await _record((half * 2).round(), (canvas) {
        if (shadow) {
          canvas.drawPath(
            disc.shift(Offset(0, 1.5 * u)),
            Paint()
              ..color = const Color(0x24000000)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * u),
          );
        }
        // Widened when a ring is coming, which eats into the halo's band.
        canvas.drawPath(disc, outline(halo, ring == null ? 5 : 7.5));
        if (ring != null) canvas.drawPath(disc, outline(ring, 2.5));
        // Over both strokes, so they read as bands around the mark rather than
        // rings biting into it.
        canvas.drawPath(disc, Paint()..color = body);
        if (showHeading) {
          // Sits a shade forward of centre: dead-centre reads as an ornament,
          // and any further forward crowds the halo.
          canvas.drawPath(
            Path()
              ..moveTo(c.dx - 6.5 * u, c.dy + 2.5 * u)
              ..lineTo(c.dx, c.dy - 4.5 * u)
              ..lineTo(c.dx + 6.5 * u, c.dy + 2.5 * u),
            outline(halo, 3.2)
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
        }
      });
      return _toBitmap(image);
    });
  }

  /// Member-stop capsule: the marker asset's own plate with a label welded to
  /// its side, as one rounded rect.
  ///
  /// A bitmap rather than a Flutter overlay on purpose. An overlay has to be
  /// projected from `onCameraMove`, whose events arrive on the platform
  /// channel out of step with the map's own frames — the capsule then lags the
  /// tiles by an irregular amount and visibly shakes through every pan. A
  /// marker is composited by the map in the same frame as the ground under it,
  /// so it cannot drift. The price is that a [BitmapDescriptor] can't be
  /// tweened, which is why the spread arrives staggered rather than travelling.
  ///
  /// Returns the anchor to pin it by as well as the bitmap, because the
  /// plate is at one end rather than the middle. Padding the bitmap to centre
  /// the plate would be simpler, but a marker's whole bitmap takes taps — the
  /// transparent half would sit there stealing them from the map beside it.
  ///
  /// [plateGround] is the asset's own plate colour — white for bus, bike and
  /// rail. It is painted under the asset with only its outer corners rounded,
  /// squaring the two corners that meet the label: the asset rounds all four,
  /// and on a selected capsule the ink label would otherwise show through
  /// those corners as notches biting into the plate.
  static Future<({BitmapDescriptor icon, Offset anchor})> stationCapsule({
    required String asset,
    required String label,
    required bool selected,
    required bool flip,
    Color plateGround = AppTheme.surfaceCardLight,
    double size = 30,
  }) {
    final key =
        'cap:$asset:$label:$selected:$flip:${plateGround.toARGB32()}:$size';
    return _memo(key, () async {
      final s = size * _unit;
      final radius = Radius.circular(s * 10 / 45);
      // Room for the shadow's blur and offset; trimmed tight, because every
      // transparent pixel here is texture the map uploads per marker.
      final margin = 8.0 * _unit;
      final padH = 10.0 * _unit;

      final fill = selected ? AppTheme.inkLight : AppTheme.surfaceCardLight;
      final ink = selected ? AppTheme.surfaceCardLight : AppTheme.inkLight;
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: ink,
            fontSize: 12 * _unit,
            fontWeight: FontWeight.w600,
            fontFamily: 'IBMPlexSans',
            height: 1.2,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 132 * _unit);

      final labelW = painter.width + padH * 2;
      final bodyW = s + labelW;
      final w = (margin * 2 + bodyW).ceil();
      final h = (margin * 2 + s).ceil();
      final left = margin;
      final plateLeft = margin + (flip ? labelW : 0);

      final info = await vg.loadPicture(SvgAssetLoader(asset), null);
      final image = await _recordSized(w, h, (canvas) {
        final body = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, margin, bodyW, s),
          radius,
        );
        canvas
          ..drawRRect(
            body.shift(Offset(0, 1.5 * _unit)),
            Paint()
              ..color = const Color(0x1F000000)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * _unit),
          )
          ..drawRRect(body, Paint()..color = fill)
          // The plate's own ground, square on the side the label meets.
          ..drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTWH(plateLeft, margin, s, s),
              topLeft: flip ? Radius.zero : radius,
              bottomLeft: flip ? Radius.zero : radius,
              topRight: flip ? radius : Radius.zero,
              bottomRight: flip ? radius : Radius.zero,
            ),
            Paint()..color = plateGround,
          )
          ..save()
          ..translate(plateLeft, margin)
          ..scale(s / info.size.width)
          ..drawPicture(info.picture)
          ..restore();
        painter.paint(
          canvas,
          Offset(
            (flip ? left : plateLeft + s) + padH,
            margin + (s - painter.height) / 2,
          ),
        );
      });
      info.picture.dispose();
      return (
        icon: await _toBitmap(image),
        // Pin by the plate's centre, wherever in the bitmap it landed.
        anchor: Offset((plateLeft + s / 2) / w, 0.5),
      );
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

  /// One bus-route stop marker, in any of its live states, optionally with the
  /// stop name welded to its side as a selected capsule.
  ///
  /// A single painter for the whole state ladder, because the states differ
  /// only in [fill] / [ring] / [content] and in whether the plate is a disc or
  /// a pill. The shape changes only when the content does: a countdown or a
  /// status glyph fits a disc, while 進站中 is a word, so it gets a [pill] sized
  /// to the text. Which state maps to which values is the caller's business
  /// (`bus_route_data_helpers.dart`) — this file knows nothing about ETAs.
  ///
  /// A bitmap rather than a Flutter overlay for the reason spelled out on
  /// [stationCapsule]: an overlay projected from `onCameraMove` shakes through
  /// every pan. The same trade applies — a [BitmapDescriptor] cannot be
  /// tweened, so a state change is a swapped image and the capsule appears
  /// rather than growing out of the plate.
  ///
  /// [ring] null paints no ring, which is what the solid 進站中 plate wants.
  ///
  /// Returns the anchor to pin by rather than assuming (0.5, 0.5): on a capsule
  /// the plate sits at one end, and even a bare plate is inset by the shadow
  /// margin. That margin doubles as tap area — a 32pt plate reads ~42pt to the
  /// finger, nearer the 44pt floor than the tight bitmap it replaces.
  static Future<({BitmapDescriptor icon, Offset anchor})> stopMarker({
    required Color fill,
    required Color content,
    Color? ring,
    double ringWidth = 2,
    double height = 32,
    String? text,
    IconData? glyph,
    bool pill = false,
    String? label,
    Color labelFill = AppTheme.inkLight,
    Color labelInk = AppTheme.surfaceCardLight,
    bool flip = false,
  }) {
    final key =
        'stop:$height:${fill.toARGB32()}:${content.toARGB32()}:'
        '${ring?.toARGB32()}:$ringWidth:$text:${glyph?.codePoint}:$pill:'
        '$label:${labelFill.toARGB32()}:${labelInk.toARGB32()}:$flip';
    return _memo(key, () async {
      final h = height * _unit;
      final radius = Radius.circular(h / 2);
      // Room for the shadow's blur and offset. Trimmed tight — every
      // transparent pixel is texture the map uploads, once per stop on a route
      // that can run 60 stops long.
      final margin = 5.0 * _unit;
      final padH = 11.0 * _unit;

      final contentPainter = TextPainter(
        text: TextSpan(
          text: glyph != null
              ? String.fromCharCode(glyph.codePoint)
              : (text ?? ''),
          style: TextStyle(
            color: content,
            fontSize: switch ((glyph, pill)) {
              (final IconData _, _) => h * 0.5,
              (_, true) => 12 * _unit,
              // Three characters only fit a disc at the smaller step; two or
              // fewer (the common countdown) get the readable one.
              _ => h * ((text?.length ?? 0) > 2 ? 0.30 : 0.42),
            },
            fontWeight: FontWeight.w700,
            fontFamily:
                glyph?.fontFamily ?? (pill ? 'IBMPlexSans' : 'IBMPlexMono'),
            package: glyph?.fontPackage,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelPainter = label == null
          ? null
          : (TextPainter(
              text: TextSpan(
                text: label,
                style: TextStyle(
                  color: labelInk,
                  fontSize: 12 * _unit,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'IBMPlexSans',
                  height: 1.2,
                ),
              ),
              maxLines: 1,
              ellipsis: '…',
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: 132 * _unit));

      final plateW = pill ? contentPainter.width + padH * 2 : h;
      final labelW = labelPainter == null ? 0.0 : labelPainter.width + padH * 2;
      final bodyW = plateW + labelW;
      final w = (margin * 2 + bodyW).ceil();
      final imageH = (margin * 2 + h).ceil();
      final plateLeft = margin + (flip ? labelW : 0);

      final image = await _recordSized(w, imageH, (canvas) {
        final body = RRect.fromRectAndRadius(
          Rect.fromLTWH(margin, margin, bodyW, h),
          radius,
        );
        // Lifts the plate off arbitrary map tiles. Barely visible against the
        // dark basemap, which is the same trade AppTheme.floatingControl makes.
        canvas.drawRRect(
          body.shift(Offset(0, 1.5 * _unit)),
          Paint()
            ..color = const Color(0x24000000)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * _unit),
        );
        if (labelPainter != null) {
          canvas.drawRRect(body, Paint()..color = labelFill);
        }
        // The plate is drawn whole, over the capsule body, and its end cap is
        // the body's own — so no corner of the body can show through, and none
        // of the squaring [stationCapsule] needs is required here.
        final plate = RRect.fromRectAndRadius(
          Rect.fromLTWH(plateLeft, margin, plateW, h),
          radius,
        );
        canvas.drawRRect(plate, Paint()..color = fill);
        if (ring != null) {
          canvas.drawRRect(
            plate.deflate(ringWidth * _unit / 2),
            Paint()
              ..color = ring
              ..style = PaintingStyle.stroke
              ..strokeWidth = ringWidth * _unit,
          );
        }
        contentPainter.paint(
          canvas,
          Offset(
            plateLeft + (plateW - contentPainter.width) / 2,
            margin + (h - contentPainter.height) / 2,
          ),
        );
        labelPainter?.paint(
          canvas,
          Offset(
            (flip ? margin : plateLeft + plateW) + padH,
            margin + (h - labelPainter.height) / 2,
          ),
        );
      });
      return (
        icon: await _toBitmap(image),
        // Pin by the plate's centre, wherever in the bitmap it landed.
        anchor: Offset((plateLeft + plateW / 2) / w, 0.5),
      );
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

  /// Live-vehicle info bubble: the vehicle's headline status on top (勤務／行車
  /// 狀況, colored by [statusColor]), plate + GPS freshness below, with a tail
  /// pointing down at the vehicle mark. Rendered as its own marker anchored
  /// (0.5, 1.0) at the vehicle position; [clearance] is transparent space below
  /// the tail so the bubble floats above the mark.
  ///
  /// Only the pinned bus and any vehicle in a warning state gets one — see
  /// `bus_route_screen.dart`, which decides that.
  ///
  /// [clearance] is the one measurement here scaled by the raw device pixel
  /// ratio rather than [_unit]: it has to clear [busMark], which carries no
  /// text and so does not grow with the text setting. Scaling it would lift the
  /// bubble off a mark that never moved. The default clears the mark's 14pt
  /// radius plus its halo, with a few pt of air left over.
  static Future<BitmapDescriptor> busBubble({
    required String plate,
    required Color fill,
    required Color inkSecondary,
    required String statusLabel,
    required Color statusColor,
    required String gpsText,
    String? trackGlyph,
    double clearance = 22,
  }) {
    final key =
        'bubble:$plate:$statusLabel:$gpsText:${fill.toARGB32()}:'
        '${inkSecondary.toARGB32()}:${statusColor.toARGB32()}:'
        '${trackGlyph ?? ''}';
    return _memo(key, store: _bubbleCache, cap: _bubbleCacheCap, () async {
      final statusPainter = TextPainter(
        text: TextSpan(
          text: statusLabel,
          style: TextStyle(
            color: statusColor,
            fontSize: 13.5 * _unit,
            fontWeight: FontWeight.w700,
            fontFamily: 'IBMPlexSans',
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final metaPainter = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: plate,
              style: TextStyle(letterSpacing: 0.3 * _unit),
            ),
            TextSpan(text: ' · $gpsText'),
            // Pin state (＋ selecting / ✓ tracking) sits to the right of the
            // plate line as a bare ink glyph — no chip, matching the mock.
            if (trackGlyph != null)
              TextSpan(
                text: '  $trackGlyph',
                style: TextStyle(
                  fontSize: 13 * _unit,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
          style: TextStyle(
            color: inkSecondary,
            fontSize: 10.5 * _unit,
            fontWeight: FontWeight.w600,
            fontFamily: 'IBMPlexMono',
            fontFeatures: const [ui.FontFeature.tabularFigures()],
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final padH = 11.0 * _unit;
      final padTop = 6.0 * _unit;
      final padBottom = 7.0 * _unit;
      final lineGap = 1.0 * _unit;
      final tailW = 12.0 * _unit;
      final tailH = 6.0 * _unit;
      final margin = 12.0 * _unit;

      final contentW = [
        statusPainter.width,
        metaPainter.width,
      ].reduce((a, b) => a > b ? a : b);
      final bubbleW = contentW + padH * 2;
      final bubbleH =
          padTop +
          statusPainter.height +
          lineGap +
          metaPainter.height +
          padBottom;
      final w = (bubbleW + margin * 2).ceil();
      final h = (margin + bubbleH + tailH + clearance * _dpr).ceil();
      final cx = w / 2;

      final image = await _recordSized(w, h, (canvas) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(margin, margin, bubbleW, bubbleH),
          Radius.circular(10 * _unit),
        );
        final body = Path()
          ..addRRect(rect)
          ..moveTo(cx - tailW / 2, margin + bubbleH)
          ..lineTo(cx + tailW / 2, margin + bubbleH)
          ..lineTo(cx, margin + bubbleH + tailH)
          ..close();
        canvas
          ..drawPath(
            body.shift(Offset(0, 2 * _unit)),
            Paint()
              ..color = const Color(0x29000000)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * _unit),
          )
          ..drawPath(body, Paint()..color = fill);
        statusPainter.paint(
          canvas,
          Offset(cx - statusPainter.width / 2, margin + padTop),
        );
        metaPainter.paint(
          canvas,
          Offset(
            cx - metaPainter.width / 2,
            margin + padTop + statusPainter.height + lineGap,
          ),
        );
      });
      return _toBitmap(image);
    });
  }

  static Future<T> _memo<T extends Object>(
    String key,
    Future<T> Function() build, {
    LinkedHashMap<String, Object>? store,
    int? cap,
  }) async {
    final cache = store ?? _cache;
    final cacheCap = cap ?? _cacheCap;
    // Both scales join every key here rather than in each entry point's own
    // key: a painter that forgets one serves a bitmap built for the wrong size,
    // and this is the single place that cannot be forgotten. The markers that
    // paint no text pay one redundant rebuild after a text-size change.
    final cacheKey = '$key:$_dpr:$_textScale';
    final hit = cache.remove(cacheKey);
    if (hit != null) {
      // Re-insert to mark most-recently-used (LinkedHashMap preserves
      // insertion order). BitmapDescriptor needs no explicit dispose.
      cache[cacheKey] = hit;
      return hit as T;
    }
    final made = await build();
    if (cache.length >= cacheCap) {
      cache.remove(cache.keys.first);
    }
    cache[cacheKey] = made;
    return made;
  }

  static Future<ui.Image> _record(int px, void Function(Canvas) draw) =>
      _recordSized(px, px, draw);

  static Future<ui.Image> _recordSized(
    int w,
    int h,
    void Function(Canvas) draw,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    draw(canvas);
    // The recorded picture holds native memory of its own, separate from the
    // image rasterised out of it, and is dead the moment toImage resolves.
    // Leaving it to the GC finaliser strands that memory on every cache miss —
    // and every marker in the app is built through here.
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(w, h);
    } finally {
      picture.dispose();
    }
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
