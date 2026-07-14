import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/decoders/fare_decoder.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';
import 'package:wheres_the_car/data/models/eta_format.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';
import 'package:wheres_the_car/data/models/timeline_stop.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_bloc.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_event.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_state.dart';
import 'package:wheres_the_car/features/bus/bus_vehicle_status.dart';
import 'package:wheres_the_car/features/bus/widgets/bus_timeline_stops.dart';
import 'package:wheres_the_car/features/bus/widgets/pinned_bus.dart';
import 'package:wheres_the_car/features/bus/widgets/track_trigger_stop.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';
import 'package:wheres_the_car/shared/map/bus_sprite.dart';
import 'package:wheres_the_car/shared/map/map_color_scheme.dart';
import 'package:wheres_the_car/shared/map/marker_factory.dart';
import 'package:wheres_the_car/shared/map/wkt.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_accordion.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_card.dart';
import 'package:wheres_the_car/shared/widgets/app_input.dart';
import 'package:wheres_the_car/shared/widgets/app_sliding_segment.dart';
import 'package:wheres_the_car/shared/widgets/bookmark_button.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/divider_line.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/route_tab_bar.dart';

part '../widgets/bus_route_data_helpers.dart';
part '../widgets/bus_route_chrome_widgets.dart';
part '../widgets/bus_route_sheet_widgets.dart';
part '../widgets/bus_route_horizontal_timeline.dart';
part '../widgets/bus_route_stop_list_widgets.dart';
part '../widgets/bus_route_detail_widgets.dart';

const _kDefaultCamera = CameraPosition(
  target: LatLng(25.0416, 121.5501),
  zoom: 14,
);

// peek (0.25) only clears the handle + direction slider + timeline; the pick
// bar inserts above the timeline and would clip it, so the sheet lifts to this
// slightly taller detent while picking and drops back to peek afterwards.
const _kPickSheetOffset = SheetOffset.proportionalToViewport(0.35);

// Map overlays repaint on live ETA/vehicle churn; holding them in a notifier
// keeps that repaint scoped to the GoogleMap layer instead of the whole screen.
typedef _MapLayer = ({Set<Marker> markers, Set<Polyline> polylines});

// A live vehicle frame lands every ~30 s; Google Maps markers have no position
// tween, so without this they teleport. Each glide holds the interpolation
// endpoints plus the (heading-snapped) sprite and info-bubble bitmaps, reused
// unchanged across every tick of a single glide.
class _BusGlide {
  _BusGlide({
    required this.from,
    required this.to,
    required this.icon,
    required this.bubbleIcon,
  });

  final LatLng from;
  final LatLng to;
  final BitmapDescriptor icon;
  final BitmapDescriptor bubbleIcon;
}

LatLng _lerpLatLng(LatLng a, LatLng b, double t) => LatLng(
  a.latitude + (b.latitude - a.latitude) * t,
  a.longitude + (b.longitude - a.longitude) * t,
);

class BusRouteScreen extends StatefulWidget {
  const BusRouteScreen({required this.subRouteUid, super.key});
  final String subRouteUid;

  @override
  State<BusRouteScreen> createState() => _BusRouteScreenState();
}

class _BusRouteScreenState extends State<BusRouteScreen>
    with TickerProviderStateMixin {
  // Owned here (not created inside build's BlocProvider) so State methods can
  // reach it directly. A BlocProvider in build() sits below this State element,
  // so a context.read from here would fail the ancestor lookup.
  late final BusRouteBloc _bloc;
  late final TabController _tabController;
  late final SheetController _sheetController;
  final _scrollController = ScrollController();
  // The horizontal timeline (collapsed sheet) is a separate scrollable from the
  // vertical stop list, so a marker tap must drive its own controller too.
  final _timelineController = ScrollController();
  GoogleMapController? _mapController;

  /// Stop uids of the current direction, in list order — lets a marker tap map
  /// a stopUid to its row index for scroll-to.
  List<String> _stopUidsInOrder = const [];
  /// The stop briefly highlighted after its marker was tapped; cleared by
  /// [_flashTimer] after a few seconds.
  String? _flashStopUid;
  Timer? _flashTimer;

  // "Pin a bus, pick your alight stop" state. [_pinnedPlate] is the selected
  // vehicle (null = none); [_pickingStop] is true from selection until a stop
  // is chosen (完成) or skipped (略過); [_pinnedNextStopIndex] snapshots the
  // bus's next-stop index at pin time so the passed/downstream split stays
  // stable while picking; [_targetStopUid] is the chosen alight stop;
  // [_leadStops] is 提前站數 (default 2, min 1).
  String? _pinnedPlate;
  bool _pickingStop = false;
  int? _pinnedNextStopIndex;
  String? _targetStopUid;
  int _leadStops = 2;

  final ValueNotifier<_MapLayer> _mapLayer = ValueNotifier(
    (markers: <Marker>{}, polylines: <Polyline>{}),
  );
  List<LatLng> _routePts = [];
  // Per-marker reuse cache: id → (rendered-inputs key, built Marker).
  final _markerCache = <String, ({String key, Marker marker})>{};
  String _mapSig = '';
  String? _geomSig;
  List<List<LatLng>> _geomLines = const [];
  bool _fitted = false;

  // Vehicle markers slide between live frames; stops/polylines stay static, so
  // a glide tick only repaints the bus + bubble layer on top of them.
  Set<Marker> _stopMarkers = <Marker>{};
  Set<Polyline> _polylines = <Polyline>{};
  final _glides = <String, _BusGlide>{};
  late final AnimationController _busGlide;
  late final CurvedAnimation _busGlideCurve;

  @override
  void initState() {
    super.initState();
    _bloc = BusRouteBloc(subRouteUid: widget.subRouteUid);
    _tabController = TabController(length: 2, vsync: this);
    _sheetController = SheetController();
    // 800ms reads as a bus catching up to its reported spot; a UI-chrome-speed
    // glide (~200ms) would look like a twitch every 30 s.
    _busGlide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addListener(_paintVehicles);
    _busGlideCurve = CurvedAnimation(
      parent: _busGlide,
      curve: AppMotion.easeInOut,
    );
  }

  BusStopEtaViewModel? _etaFor(BusRouteState s, BusStopModel st) =>
      s.etaMap['seq:${s.direction}:${st.sequence}'] ??
      s.etaMap['uid:${st.stopUid}'];

  Future<void> _syncMap(BusRouteState s) async {
    final route = s.route;
    if (route == null) return;
    final stops = s.direction == 0 ? route.stopsGo : route.stopsReturn;
    if (stops.isEmpty) return;
    _stopUidsInOrder = [for (final st in stops) st.stopUid];

    final vehicles = _vehiclePositionsFor(s);
    // gpsTimeUnix advances every live frame and drives the bubble's freshness
    // reading, so including it here refreshes that label each frame.
    final sig =
        '${route.subRouteUid}:${s.direction}:${stops.length}:'
        '${stops.map((st) => _markerEta(_etaFor(s, st))).join(',')}:'
        '${vehicles.map(
          (v) =>
              '${v.plate}@${v.lat},${v.lon},${v.azimuth},${v.dutyStatus},'
              '${v.busStatus},${v.gpsTimeUnix}',
        ).join(';')}';
    if (sig == _mapSig) return;
    _mapSig = sig;

    final stopPts = [
      for (final st in stops)
        if (st.lat != 0 || st.lon != 0) LatLng(st.lat, st.lon),
    ];

    final geomSig = '${route.subRouteUid}:${s.direction}';
    if (geomSig != _geomSig) {
      _geomSig = geomSig;
      final geometry = s.direction == 0
          ? route.geometryGo
          : route.geometryReturn;
      var lines = parseWktLines(geometry);
      if (lines.isEmpty && stopPts.length >= 2) lines = [stopPts];
      _geomLines = lines;
    }

    final cs = Theme.of(context).colorScheme;
    final polylines = <Polyline>{
      for (var i = 0; i < _geomLines.length; i++)
        Polyline(
          polylineId: PolylineId('route_$i'),
          points: _geomLines[i],
          color: cs.onSurface,
          width: 4,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
    };

    // Stop markers are static between frames; reuse any whose rendered inputs
    // are unchanged so a frame costs O(changed) icon lookups, not O(stops).
    final stopMarkers = <Marker>{};
    for (final st in stops) {
      if (st.lat == 0 && st.lon == 0) continue;
      final eta = _etaFor(s, st);
      final key =
          '${_markerIsScheduled(eta)}:${_markerEta(eta)}:${st.lat},${st.lon}';
      final cached = _markerCache[st.stopUid];
      if (cached != null && cached.key == key) {
        stopMarkers.add(cached.marker);
        continue;
      }
      final icon = _markerIsScheduled(eta)
          ? await MapMarkers.etaStopIcon(Icons.schedule_rounded, size: 32)
          : await MapMarkers.etaStop(_markerEta(eta), size: 32);
      final stopUid = st.stopUid;
      final marker = Marker(
        markerId: MarkerId(stopUid),
        position: LatLng(st.lat, st.lon),
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        infoWindow: InfoWindow(title: st.stopName),
        onTap: () => _flashStop(stopUid),
      );
      _markerCache[st.stopUid] = (key: key, marker: marker);
      stopMarkers.add(marker);
    }

    // Resolve each vehicle's (heading-snapped) sprite + bubble bitmaps, then
    // hand the new position to the glide controller. Every glide starts from
    // where the marker sits *right now* — mid-glide included — so a fresh frame
    // retargets smoothly instead of snapping back to the last reported point.
    final isLight = cs.brightness == Brightness.light;
    final now = DateTime.now();
    final t = _busGlideCurve.value;
    final nextGlides = <String, _BusGlide>{};
    for (final v in vehicles) {
      final icon = await MapMarkers.busMarker(
        busSpriteAsset(v.azimuth.toDouble()),
      );

      // Always-on bubble above the sprite: the vehicle's own 勤務／行車狀況 as
      // the headline, plate + GPS freshness below — replacing the former
      // next-stop + ETA content and the tap-only default InfoWindow.
      final status = busVehicleStatus(v);
      final statusColor = switch (status.tone) {
        BusStatusTone.normal => cs.onSurface,
        BusStatusTone.notice =>
          isLight ? AppTheme.etaApproaching : AppTheme.statusApproach,
        BusStatusTone.warning => cs.error,
        BusStatusTone.muted => cs.onSurfaceVariant,
      };
      final bubbleIcon = await MapMarkers.busBubble(
        plate: v.plate,
        fill: isLight ? Colors.white : cs.surfaceContainerHigh,
        inkSecondary: cs.onSurfaceVariant,
        statusLabel: status.label,
        statusColor: statusColor,
        gpsText: busGpsAge(v.gpsTimeUnix, now).text,
        // ＋ while choosing the alight stop, ✓ once tracking is armed.
        trackGlyph: _pinnedPlate == v.plate
            ? (_pickingStop ? '＋' : '✓')
            : null,
      );

      final target = LatLng(v.lat, v.lon);
      final prev = _glides[v.plate];
      // A newly-seen bus starts at its target (no fly-in from nowhere);
      // otherwise glide from wherever it sits right now.
      final from = prev == null ? target : _lerpLatLng(prev.from, prev.to, t);
      nextGlides[v.plate] = _BusGlide(
        from: from,
        to: target,
        icon: icon,
        bubbleIcon: bubbleIcon,
      );
    }

    if (!mounted) return;
    _stopMarkers = stopMarkers;
    _polylines = polylines;
    _glides
      ..clear()
      ..addAll(nextGlides);
    _routePts = stopPts;

    if (MediaQuery.of(context).disableAnimations) {
      // Reduce-motion: snap to the reported position, no glide.
      _busGlide.value = 1;
      _paintVehicles();
    } else {
      // Glide from the current position to the new frame. A frame that didn't
      // move a bus just animates target→target (static); a frame landing
      // mid-glide retargets smoothly because `from` is the live position.
      unawaited(_busGlide.forward(from: 0));
    }
    _maybeFit();
  }

  // Composes the animated bus + bubble markers over the static stop layer and
  // pushes them to the GoogleMap notifier. Runs per glide tick; the sprite and
  // bubble bitmaps are memoized upstream, so a tick is cheap position churn.
  void _paintVehicles() {
    final t = _busGlideCurve.value;
    final vehicleMarkers = <Marker>{};
    _glides.forEach((plate, g) {
      final pos = _lerpLatLng(g.from, g.to, t);
      // Once a bus is pinned, the others recede so the pinned one leads.
      final dimmed = _pinnedPlate != null && plate != _pinnedPlate;
      final alpha = dimmed ? 0.35 : 1.0;
      vehicleMarkers
        ..add(
          Marker(
            markerId: MarkerId('bus:$plate'),
            position: pos,
            icon: g.icon,
            anchor: const Offset(0.5, 0.5),
            alpha: alpha,
            zIndexInt: 1,
            onTap: () => _togglePin(plate),
          ),
        )
        ..add(
          Marker(
            markerId: MarkerId('bubble:$plate'),
            position: pos,
            icon: g.bubbleIcon,
            alpha: alpha,
            zIndexInt: 2,
          ),
        );
    });
    // ponytail: repaints the whole marker Set per tick — fine for a handful of
    // buses; batch/diff the marker channel if a route ever shows dozens.
    _mapLayer.value = (
      markers: {..._stopMarkers, ...vehicleMarkers},
      polylines: _polylines,
    );
  }

  void _maybeFit() {
    if (_fitted) return;
    final c = _mapController;
    if (c == null || _routePts.isEmpty) return;
    _fitted = true;
    unawaited(c.animateCamera(_fitUpdate()));
  }

  CameraUpdate _fitUpdate() => _routePts.length == 1
      ? CameraUpdate.newLatLngZoom(_routePts.first, 16)
      : CameraUpdate.newLatLngBounds(_boundsOf(_routePts), 60);

  void _recenterMap() {
    unawaited(HapticService.instance.lightTap());
    final controller = _mapController;
    if (controller != null) {
      unawaited(
        controller.animateCamera(
          _routePts.isEmpty
              ? CameraUpdate.newCameraPosition(_kDefaultCamera)
              : _fitUpdate(),
        ),
      );
    }
  }

  /// Scrolls the stop list to [stopUid] and highlights that row for a few
  /// seconds. Row heights vary, so the target offset is estimated and clamped
  /// to the scroll extent — it lands the stop near the top, not pixel-exact.
  // ponytail: index × estimated row height; move to scrollable_positioned_list
  // only if pixel-exact landing is ever needed.
  void _flashStop(String stopUid) {
    unawaited(HapticService.instance.lightTap());
    final index = _stopUidsInOrder.indexOf(stopUid);
    if (index >= 0) {
      // Vertical stop list: rows vary in height, so the offset is an estimate.
      if (_scrollController.hasClients) {
        const estRowHeight = 64.0;
        final target = (index * estRowHeight).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        unawaited(
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 320),
            curve: AppMotion.easeInOut,
          ),
        );
      }
      // Horizontal timeline: fixed 120px cells, so centre the stop exactly.
      if (_timelineController.hasClients) {
        const cellWidth = 120.0;
        final pos = _timelineController.position;
        final target = (index * cellWidth + cellWidth / 2 -
                pos.viewportDimension / 2)
            .clamp(0.0, pos.maxScrollExtent);
        unawaited(
          _timelineController.animateTo(
            target,
            duration: const Duration(milliseconds: 320),
            curve: AppMotion.easeInOut,
          ),
        );
      }
    }
    _flashTimer?.cancel();
    setState(() => _flashStopUid = stopUid);
    _flashTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _flashStopUid = null);
    });
  }

  /// Selects/deselects the bus marker [plate]. Selecting enters pick-mode
  /// (＋, "selected, not yet tracking"); tapping the pinned bus again unpins and
  /// cancels any armed tracking session.
  void _togglePin(String plate) {
    final session = context.read<JourneySessionBloc>();
    if (_pinnedPlate == plate) {
      session.add(const JourneyCancelled());
      setState(() {
        _pinnedPlate = null;
        _pickingStop = false;
        _pinnedNextStopIndex = null;
        _targetStopUid = null;
      });
      _repaintPins();
      _liftSheet(false);
      return;
    }
    final s = _bloc.state;
    unawaited(HapticService.instance.mediumTap());
    setState(() {
      _pinnedPlate = plate;
      _pickingStop = true;
      // Snapshot the bus's position so the passed/downstream split holds still
      // while the rider picks, instead of shifting under each live frame.
      _pinnedNextStopIndex = pinnedBusNextStopIndex(
        etas: s.etaMap.values,
        stopUidsInOrder: _stopUidsInOrder,
        direction: s.direction,
        plate: plate,
      );
      _targetStopUid = null;
      _leadStops = 2;
    });
    _repaintPins();
    _liftSheet(true);
  }

  /// Raises the sheet to [_kPickSheetOffset] while picking so the pick bar has
  /// room above the timeline, and drops it back to peek when picking ends.
  void _liftSheet(bool picking) => unawaited(
    _sheetController.animateTo(picking ? _kPickSheetOffset : AppSheetSnap.peek),
  );

  // Pin state lives in [State], not the map signature, so a select/confirm
  // repaints the bus bubbles (glyph + dim) by forcing [_syncMap] to rebuild.
  void _repaintPins() {
    _mapSig = '';
    unawaited(_syncMap(_bloc.state));
  }

  void _onPickStop(String uid) {
    unawaited(HapticService.instance.lightTap());
    setState(() => _targetStopUid = uid);
  }

  /// The current direction's stops, or empty when the route isn't loaded.
  List<BusStopModel> _currentStops(BusRouteState s) {
    final route = s.route;
    if (route == null) return const [];
    return s.direction == 0 ? route.stopsGo : route.stopsReturn;
  }

  JourneyLeg _trackLeg({
    required BusRouteViewModel route,
    required List<BusStopModel> stops,
    required int idx,
    required int direction,
  }) {
    final routeName = route.routeName;
    final headsign = direction == 0 ? route.headsignGo : route.headsignReturn;
    return JourneyLeg(
      kind: JourneyLegKind.bus,
      routeLabel: headsign.isEmpty ? routeName : '$routeName 往$headsign',
      boardStop: stops[idx].stopName,
      alightStop: stops.last.stopName,
      stopNames: const [],
      identity: PlanIdentity(
        routeType: 'bus',
        routeKey: route.subRouteUid,
        direction: '$direction',
        departureStopKey: stops[idx].stopUid,
        arrivalStopKey: '',
        supported: false,
      ),
      leadingWalkMinutes: 0,
      scheduledDeparture: null,
      scheduledArrival: null,
      boardLocation: PlanPoint(lat: stops[idx].lat, lng: stops[idx].lon),
      stopLocations: const [],
    );
  }

  /// 完成: start plate-tracked waiting on the picked alight stop and arm a
  /// pinned reminder on the trigger stop (提前站數 before it).
  void _confirmPick() {
    final plate = _pinnedPlate;
    final target = _targetStopUid;
    if (plate == null || target == null) return;
    final s = _bloc.state;
    final route = s.route;
    if (route == null) return;
    final stops = _currentStops(s);
    final idx = stops.indexWhere((st) => st.stopUid == target);
    if (idx < 0) return;
    context.read<JourneySessionBloc>().add(
      JourneyStarted(
        trackOnly: true,
        plate: plate,
        legs: [
          _trackLeg(
            route: route,
            stops: stops,
            idx: idx,
            direction: s.direction,
          ),
        ],
      ),
    );
    final trigger = resolveTriggerStopUid(_stopUidsInOrder, target, _leadStops);
    _bloc.add(
      BusRoutePinnedReminderArmed(stopUid: trigger, plate: plate),
    );
    unawaited(HapticService.instance.mediumTap());
    setState(() => _pickingStop = false);
    _repaintPins();
    _liftSheet(false);
  }

  /// 略過: track the pinned bus toward its next stop with no reminder.
  void _skipPick() {
    final plate = _pinnedPlate;
    if (plate == null) return;
    final s = _bloc.state;
    final route = s.route;
    if (route == null) return;
    final stops = _currentStops(s);
    final nextIdx = firstAlightIndex(_pinnedNextStopIndex);
    if (nextIdx >= stops.length) return;
    context.read<JourneySessionBloc>().add(
      JourneyStarted(
        trackOnly: true,
        plate: plate,
        legs: [
          _trackLeg(
            route: route,
            stops: stops,
            idx: nextIdx,
            direction: s.direction,
          ),
        ],
      ),
    );
    unawaited(HapticService.instance.mediumTap());
    setState(() {
      _pickingStop = false;
      _targetStopUid = null;
    });
    _repaintPins();
    _liftSheet(false);
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _busGlideCurve.dispose();
    _busGlide.dispose();
    _tabController.dispose();
    _sheetController.dispose();
    _scrollController.dispose();
    _timelineController.dispose();
    _mapLayer.dispose();
    unawaited(_bloc.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final sheetAnimation = SheetOffsetDrivenAnimation(
      controller: _sheetController,
      initialValue: 0,
    );

    return BlocProvider<BusRouteBloc>.value(
      value: _bloc,
      child: BlocConsumer<BusRouteBloc, BusRouteState>(
        // etaMap is deliberately excluded: live ETA frames must not rebuild the
        // static chrome (map, app bar, FAB, sheet skeleton). ETA-consuming
        // subtrees observe etaMap through their own BlocSelectors instead.
        buildWhen: (prev, curr) =>
            prev.route != curr.route ||
            prev.direction != curr.direction ||
            prev.fare != curr.fare ||
            prev.bufferSequences != curr.bufferSequences ||
            prev.daily != curr.daily ||
            prev.reminders != curr.reminders ||
            prev.loading != curr.loading ||
            prev.error != curr.error,
        listener: (context, state) => _syncMap(state),
        builder: (context, state) {
          final routeName = state.route?.routeName ?? widget.subRouteUid;
          final dirNames = [
            state.route?.headsignGo ?? '',
            state.route?.headsignReturn ?? '',
          ];
          final dirName = state.direction == 0 ? dirNames[0] : dirNames[1];

          return Scaffold(
            resizeToAvoidBottomInset: false,
            body: Stack(
              children: [
                Positioned.fill(
                  child: ValueListenableBuilder<_MapLayer>(
                    valueListenable: _mapLayer,
                    builder: (context, layer, _) => GoogleMap(
                      style: mapStyleOf(context),
                      initialCameraPosition: _kDefaultCamera,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      markers: layer.markers,
                      polylines: layer.polylines,
                      onMapCreated: (controller) {
                        _mapController = controller;
                        _maybeFit();
                      },
                    ),
                  ),
                ),

                _FloatingAppBar(
                  subRouteUid: widget.subRouteUid,
                  routeName: routeName,
                  dirName: dirName,
                  direction: state.direction,
                  onBookmarkTapped: HapticService.instance.mediumTap,
                ),

                ValueListenableBuilder<double?>(
                  valueListenable: _sheetController,
                  builder: (context, offset, child) {
                    final currentOffset = offset ?? 0.0;
                    return Positioned(
                      right: 16,
                      bottom: currentOffset + 16,
                      child: child!,
                    );
                  },
                  child: Pressable(
                    onTap: _recenterMap,
                    semanticLabel: '定位目前位置',
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cs.brightness == Brightness.light
                            ? Colors.white
                            : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: AppShadows.floating,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.gps_fixed_rounded,
                          size: 20,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),

                NotificationListener<SheetNotification>(
                  onNotification: (notification) {
                    if (notification is SheetDragEndNotification) {
                      unawaited(HapticService.instance.lightTap());
                    }
                    return false;
                  },
                  child: SheetViewport(
                    child: _RouteSheet(
                      tabController: _tabController,
                      sheetController: _sheetController,
                      scrollController: _scrollController,
                      timelineController: _timelineController,
                      flashStopUid: _flashStopUid,
                      vehicles: const [],
                      direction: state.direction,
                      isLoading: state.loading,
                      onDirectionChanged: (dir) {
                        if (state.direction == dir) return;
                        unawaited(HapticService.instance.lightTap());
                        context.read<BusRouteBloc>().add(
                          BusRouteDirectionToggled(dir),
                        );
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                      },
                      sheetAnimation: sheetAnimation,
                      routeName: routeName,
                      dirNames: dirNames,
                      routeState: state,
                      reminders: state.reminders,
                      onReminderToggled: (uid) => context
                          .read<BusRouteBloc>()
                          .add(BusRouteReminderToggled(uid)),
                      pickingStop: _pickingStop,
                      pinnedNextStopIndex: _pinnedNextStopIndex,
                      targetStopUid: _targetStopUid,
                      leadStops: _leadStops,
                      onPickStop: _onPickStop,
                      onLeadChanged: (v) =>
                          setState(() => _leadStops = clampLeadStops(v)),
                      onConfirmPick: _confirmPick,
                      onSkipPick: _skipPick,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
