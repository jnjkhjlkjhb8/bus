import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/live_activity/pip_mode.dart';
import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';
import 'package:wheres_the_car/data/repositories/settings_repository.dart';
import 'package:wheres_the_car/features/go/bloc/plan_bloc.dart';
import 'package:wheres_the_car/features/go/bloc/plan_event.dart';
import 'package:wheres_the_car/features/go/bloc/plan_state.dart';
import 'package:wheres_the_car/features/go/model/plan_options.dart';
import 'package:wheres_the_car/features/go/model/planned_place.dart';
import 'package:wheres_the_car/features/go/navigation/navigation_coordinator.dart';
import 'package:wheres_the_car/features/go/view/place_search_sheet.dart';
import 'package:wheres_the_car/features/go/widgets/route_option_card.dart';
import 'package:wheres_the_car/features/go/widgets/transit_visuals.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_car/shared/map/map_color_scheme.dart';
import 'package:wheres_the_car/shared/map/marker_factory.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_button.dart';
import 'package:wheres_the_car/shared/widgets/app_progress_bar.dart';
import 'package:wheres_the_car/shared/widgets/app_quantity_selector.dart';
import 'package:wheres_the_car/shared/widgets/app_range_slider.dart';
import 'package:wheres_the_car/shared/widgets/app_slider.dart';
import 'package:wheres_the_car/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/divider_line.dart';
import 'package:wheres_the_car/shared/widgets/filter_chip_group.dart';

part '../widgets/go_planner_widgets.dart';
part '../widgets/go_navigation_widgets.dart';
part '../widgets/go_preview_widgets.dart';

const _kDefaultPos = LatLng(25.0416, 121.5438);

// Muted gray for non-selected alternate routes on the map. A fixed neutral
// (rather than a theme color) so it reads as clearly secondary over both the
// light and dark map styles.
const _kAltRouteColor = Color(0xFF9AA0A6);

// Follow-camera framing while navigating. Shared by the one-shot nav-start
// camera and every follow tick so they stay in lockstep (spec: keep tilt 45 /
// zoom 15.5); the initial bearing is only used until the first trustworthy
// heading rotates the map.
const _kNavZoom = 15.5;
const _kNavTilt = 45.0;
const _kNavBearing = 30.0;

class GoScreen extends StatefulWidget {
  const GoScreen({super.key});

  @override
  State<GoScreen> createState() => _GoScreenState();
}

class _GoScreenState extends State<GoScreen> {
  GoogleMapController? _map;
  late final SheetController _sheet;
  // A distinct controller for the preview sheet so it and the results sheet can
  // co-exist briefly while the phase-swap animation crossfades them.
  late final SheetController _previewSheet;
  late final NavigationCoordinator _navigationCoordinator;
  PlannedPlace? _origin;
  PlannedPlace? _dest;
  PlanOptions _options = const PlanOptions();
  // Whether the autopilot currently has a live GPS fix flowing. Gates the
  // manual progression controls in the nav sheet: shown only when the
  // autopilot can't actually drive (no permission / location services off).
  bool _autopilotDriving = true;

  // Camera follow mode — ephemeral UI state, deliberately kept out of PlanBloc.
  // While navigating, each GPS fix recenters the camera on the user unless the
  // user has panned the map by gesture (then follow pauses until re-armed by a
  // nav (re)start or a leg advance).
  bool _followPaused = false;
  // Last bearing the camera adopted; a fix too slow/heading-invalid to trust
  // for direction keeps this rather than spinning the map (see followBearing).
  double _followBearing = _kNavBearing;
  // onCameraMoveStarted fires for the app's own animateCamera too; this counts
  // in-flight programmatic moves so only genuine user gestures pause follow.
  int _programmaticMoves = 0;
  // animateCamera's future completes on the platform method reply (animation
  // start), while onCameraMoveStarted arrives as a separate channel event with
  // no ordering guarantee — the counter can hit zero before the event lands.
  // A short grace window after the last programmatic move covers that race.
  DateTime _lastProgrammaticMove = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kProgrammaticMoveGrace = Duration(milliseconds: 500);

  // Memoized map overlays. Building the polyline/marker sets walks every route,
  // section, and intermediate stop, so cache them and reuse while the inputs
  // (result identity, selected route, active leg, theme colors) are unchanged.
  PlanResult? _overlayResult;
  int? _overlaySelected;
  int? _overlayLeg;
  ColorScheme? _overlayScheme;
  Set<Polyline> _overlayPolylines = const {};
  Set<Marker> _overlayMarkers = const {};

  // Canvas-drawn marker bitmaps resolve asynchronously; this mirrors the
  // resolved descriptors so overlay builds can read them synchronously. A
  // pending set dedupes in-flight generation. Resolving one invalidates the
  // overlay memo so the marker appears on the next frame.
  final Map<String, BitmapDescriptor> _markerCache = {};
  final Set<String> _markerPending = {};

  @override
  void initState() {
    super.initState();
    _sheet = SheetController();
    _previewSheet = SheetController();
    _navigationCoordinator = NavigationCoordinator(
      planBloc: context.read<PlanBloc>(),
      journeySessionBloc: context.read<JourneySessionBloc>(),
      setPipNavigating: ({required navigating}) =>
          PipMode.instance.setNavigating(navigating),
      liveActivityEnabled: () =>
          SettingsRepository.instance.liveActivityEnabled,
      positions: LocationService.instance.navigationStream,
      onAutoAction: _onAutoNavAction,
      onAutopilotStatus: (driving) {
        if (mounted) setState(() => _autopilotDriving = driving);
      },
      onFollowUpdate: _onFollowUpdate,
    );
    if (context.read<PlanBloc>().state.activeLegIndex == null) {
      unawaited(_initOrigin());
    }
  }

  @override
  void dispose() {
    _navigationCoordinator.dispose();
    _map?.dispose();
    _sheet.dispose();
    _previewSheet.dispose();
    super.dispose();
  }

  Future<void> _initOrigin() async {
    try {
      final place = await resolveCurrentPlace();
      if (!mounted) return;
      setState(() => _origin = place);
    } on Object catch (_) {}
  }

  Future<void> _editField({required bool origin}) async {
    unawaited(HapticService.instance.lightTap());
    final picked = await showPlaceSearchSheet(
      context,
      fieldLabel: origin ? '選擇出發地' : '選擇目的地',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (origin) {
        _origin = picked;
      } else {
        _dest = picked;
      }
    });
    _maybePlan();
  }

  void _swap() {
    if (_origin == null && _dest == null) return;
    unawaited(HapticService.instance.lightTap());
    setState(() {
      final t = _origin;
      _origin = _dest;
      _dest = t;
    });
    _maybePlan();
  }

  void _maybePlan() {
    final from = _origin;
    final to = _dest;
    if (from == null || to == null) return;
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    context.read<PlanBloc>().add(
      PlanSearchRequested(
        fromLat: from.latLng.latitude,
        fromLon: from.latLng.longitude,
        toLat: to.latLng.latitude,
        toLon: to.latLng.longitude,
        date: '${now.year}-${two(now.month)}-${two(now.day)}',
        time: '${two(now.hour)}:${two(now.minute)}',
        gc: _options.gc,
        transitModes: _options.transitModes,
        top: _options.top,
        transferMin: _options.transferMin,
        transferMax: _options.transferMax,
        firstMileMode: _options.firstMileMode,
        firstMileTime: _options.firstMileTime,
        lastMileMode: _options.lastMileMode,
        lastMileTime: _options.lastMileTime,
      ),
    );
  }

  void _retry() {
    unawaited(HapticService.instance.lightTap());
    _maybePlan();
  }

  Future<void> _adjustOptions() async {
    unawaited(HapticService.instance.lightTap());
    final picked = await showOptionsSheet(context, current: _options);
    if (picked == null || !mounted || picked == _options) return;
    setState(() => _options = picked);
    _maybePlan();
  }

  // A results card tap selects the route and enters preview (never navigates).
  void _previewRoute(PlanRoute route) {
    final routes = context.read<PlanBloc>().state.result?.routes ?? const [];
    _previewRouteIndex(routes.indexOf(route));
  }

  // A map alternate-polyline tap selects that route and enters preview.
  void _previewRouteIndex(int index) {
    if (index < 0) return;
    unawaited(HapticService.instance.lightTap());
    context.read<PlanBloc>().add(RouteSelected(index: index));
  }

  void _closePreview() {
    unawaited(HapticService.instance.lightTap());
    context.read<PlanBloc>().add(const PreviewClosed());
  }

  // Preview CTA: navigation starts here (the only entry point), so the heavier
  // haptic that used to live on the card tap moves to this commit.
  void _startFromPreview(PlanRoute route, int routeIndex) {
    unawaited(HapticService.instance.heavyTap());
    unawaited(_startNavigation(route: route, routeIndex: routeIndex));
  }

  void _toggleSave(PlanRoute route) {
    unawaited(HapticService.instance.lightTap());
    final bloc = context.read<PlanBloc>();
    final wasSaved = bloc.state.savedKeys.contains(route.savedKey);
    bloc.add(RouteSaveToggled(route));
    // Mirror the favorites-remove undo affordance (see FavoritesScreen).
    if (wasSaved) {
      AppSnackbar.show(
        context,
        '已移除收藏',
        action: '復原',
        onAction: () => bloc.add(RouteSaveToggled(route)),
      );
    }
  }

  void _openSaved(PlanRoute route) {
    unawaited(HapticService.instance.lightTap());
    context.read<PlanBloc>().add(SavedRouteOpened(route));
  }

  Future<void> _startNavigation({
    required PlanRoute route,
    required int routeIndex,
  }) async {
    final start = await _navigationCoordinator.start(
      route: route,
      routeIndex: routeIndex,
    );
    if (!mounted) return;
    // (Re)starting navigation re-arms follow and resets the bearing to the
    // one-shot framing below; subsequent GPS fixes take over from there.
    setState(() => _followPaused = false);
    _followBearing = _kNavBearing;
    final target = _latLngOrNull(start);
    if (target != null) {
      unawaited(
        _animateCameraGuarded(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: target,
              zoom: _kNavZoom,
              bearing: _kNavBearing,
              tilt: _kNavTilt,
            ),
          ),
        ),
      );
    }
  }

  // Wraps every app-initiated camera animation so onCameraMoveStarted can tell
  // programmatic moves from user gestures (only the latter pause follow mode).
  Future<void> _animateCameraGuarded(CameraUpdate update) async {
    final map = _map;
    if (map == null) return;
    _programmaticMoves++;
    try {
      await map.animateCamera(update);
    } finally {
      _programmaticMoves--;
      _lastProgrammaticMove = DateTime.now();
    }
  }

  // Each navigation GPS fix. Keeps the camera on the user (tilt/zoom fixed,
  // bearing following travel direction) unless the user has panned away.
  void _onFollowUpdate(Position fix) {
    if (!mounted) return;
    final navigating = context.read<PlanBloc>().state.activeLegIndex != null;
    if (!navigating || _followPaused) return;
    _followTo(fix);
  }

  void _followTo(Position fix) {
    _followBearing = followBearing(fix) ?? _followBearing;
    unawaited(
      _animateCameraGuarded(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(fix.latitude, fix.longitude),
            zoom: _kNavZoom,
            bearing: _followBearing,
            tilt: _kNavTilt,
          ),
        ),
      ),
    );
  }

  void _advance(PlanRoute route, int activeLeg) {
    unawaited(HapticService.instance.lightTap());
    unawaited(_advanceNavigation(route, activeLeg));
  }

  Future<void> _advanceNavigation(PlanRoute route, int activeLeg) async {
    final result = await _navigationCoordinator.advance(
      route: route,
      activeLeg: activeLeg,
    );
    if (!mounted) return;
    if (result.arrived) {
      _resetCamera();
      AppSnackbar.show(context, '已抵達目的地', type: SnackType.success);
      return;
    }
    // A leg advance re-arms follow: the pan below frames the next leg's
    // departure, then GPS fixes resume driving the camera.
    setState(() => _followPaused = false);
    final next = _latLngOrNull(result.nextCameraPoint);
    if (next != null) {
      unawaited(_animateCameraGuarded(CameraUpdate.newLatLng(next)));
    }
  }

  // Autopilot side effect: mirrors the manual buttons' haptic, and (for
  // alight/advance) either the arrival snackbar+camera reset on the final leg
  // or the camera pan to the next leg's departure point.
  void _onAutoNavAction(
    NavAction action,
    PlanPoint? cameraTarget,
    bool arrived,
  ) {
    if (!mounted) return;
    unawaited(HapticService.instance.lightTap());
    if (arrived) {
      _resetCamera();
      AppSnackbar.show(context, '已抵達目的地', type: SnackType.success);
      return;
    }
    // Auto leg advance re-arms follow, mirroring the manual advance path.
    setState(() => _followPaused = false);
    final next = _latLngOrNull(cameraTarget);
    if (next != null) {
      unawaited(_animateCameraGuarded(CameraUpdate.newLatLng(next)));
    }
  }

  void _endNav() {
    unawaited(HapticService.instance.lightTap());
    unawaited(_navigationCoordinator.end());
    _resetCamera();
  }

  Future<void> _reconcileJourneyDone() async {
    final shouldResetCamera = await _navigationCoordinator
        .reconcileJourneyDone();
    if (mounted && shouldResetCamera) _resetCamera();
  }

  void _resetCamera() {
    unawaited(
      _animateCameraGuarded(
        CameraUpdate.newCameraPosition(
          const CameraPosition(target: _kDefaultPos, zoom: 14),
        ),
      ),
    );
  }

  LatLng? _latLngOrNull(PlanPoint? point) {
    if (point == null) return null;
    return LatLng(point.lat, point.lng);
  }

  void _fitTo(PlanRoute route) => _fitBounds(_routePoints(route));

  // Results phase frames every alternative at once.
  void _fitAll(PlanResult result) {
    final points = [
      for (final route in result.routes) ..._routePoints(route),
    ];
    _fitBounds(points);
  }

  void _fitBounds(List<LatLng> points) {
    if (points.length < 2) return;
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    unawaited(
      _animateCameraGuarded(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          72,
        ),
      ),
    );
  }

  List<LatLng> _routePoints(PlanRoute route) => [
    for (final point in route.points) LatLng(point.lat, point.lng),
  ];

  // Full per-mode colored rendering of one route (the selected/previewed one).
  Set<Polyline> _polylines(
    PlanRoute route,
    ColorScheme cs, {
    int? activeLeg,
  }) {
    final lines = <Polyline>{};
    for (final (i, s) in route.sections.indexed) {
      final walk = isWalk(s);
      final pts = <LatLng>[];
      void add(PlanPoint point) {
        if (point.lat != 0 || point.lng != 0) {
          pts.add(LatLng(point.lat, point.lng));
        }
      }

      // Walk sections trace the real OSRM foot path when it resolved; otherwise
      // fall back to a straight departure→arrival line (same as transit legs).
      if (walk && s.walkPath.isNotEmpty) {
        s.walkPath.forEach(add);
      } else {
        add(s.departure.location);
        for (final stop in s.intermediateStops) {
          add(stop.location);
        }
        add(s.arrival.location);
      }
      if (pts.length < 2) continue;
      final base = walk ? cs.outline : transitColor(s.transport, cs);
      final dim = activeLeg != null && i < activeLeg;
      lines.add(
        Polyline(
          polylineId: PolylineId('leg_$i'),
          points: pts,
          width: walk ? 4 : 6,
          color: dim ? base.withValues(alpha: 0.3) : base,
          // Sits above the muted alternates.
          zIndex: 2,
          patterns: walk
              ? [PatternItem.dot, PatternItem.gap(8)]
              : const [],
        ),
      );
    }
    return lines;
  }

  // Every route on the map: muted single-color polylines for the alternates
  // (tap to select), the selected route's full colored rendering on top. During
  // navigation only the selected route draws (no alternates).
  Set<Polyline> _buildPolylines(
    PlanResult result,
    int selectedIndex,
    int? activeLeg,
    ColorScheme cs,
  ) {
    final lines = <Polyline>{};
    if (activeLeg == null) {
      for (final (i, route) in result.routes.indexed) {
        if (i == selectedIndex) continue;
        final pts = _routePoints(route);
        if (pts.length < 2) continue;
        lines.add(
          Polyline(
            polylineId: PolylineId('alt_$i'),
            points: pts,
            width: 4,
            color: _kAltRouteColor,
            consumeTapEvents: true,
            onTap: () => _previewRouteIndex(i),
          ),
        );
      }
    }
    lines.addAll(
      _polylines(result.routes[selectedIndex], cs, activeLeg: activeLeg),
    );
    return lines;
  }

  Color _dim(Color c, {required bool dim}) =>
      dim ? c.withValues(alpha: 0.3) : c;

  // Returns the cached descriptor, or null while it renders. Requesting a
  // missing one schedules its generation; on completion the overlay memo is
  // invalidated so the marker joins the set on the next frame.
  BitmapDescriptor? _resolveMarker(
    String key,
    Future<BitmapDescriptor> Function() build,
  ) {
    final cached = _markerCache[key];
    if (cached != null) return cached;
    if (_markerPending.add(key)) {
      unawaited(
        build().then((icon) {
          if (!mounted) return;
          _markerPending.remove(key);
          _markerCache[key] = icon;
          // Force the overlay memo to rebuild now the bitmap is available.
          setState(() => _overlayResult = null);
        }),
      );
    }
    return null;
  }

  BitmapDescriptor? _originMarker(ColorScheme cs, {required bool dim}) {
    final ring = _dim(cs.onSurface, dim: dim);
    final fill = _dim(Colors.white, dim: dim);
    return _resolveMarker(
      'go_origin|${ring.toARGB32()}|${fill.toARGB32()}',
      () => MapMarkers.dot(fill, ring: ring, size: 20),
    );
  }

  BitmapDescriptor? _destMarker(ColorScheme cs, {required bool dim}) {
    final fill = _dim(cs.onSurface, dim: dim);
    final inner = _dim(Colors.white, dim: dim);
    return _resolveMarker(
      'go_dest|${fill.toARGB32()}|${inner.toARGB32()}',
      () => MapMarkers.targetDot(fill, inner),
    );
  }

  BitmapDescriptor? _boundaryMarker(Color color, {required bool dim}) {
    final ring = _dim(color, dim: dim);
    final fill = _dim(Colors.white, dim: dim);
    return _resolveMarker(
      'go_boundary|${ring.toARGB32()}|${fill.toARGB32()}',
      () => MapMarkers.dot(fill, ring: ring, size: 16),
    );
  }

  BitmapDescriptor? _stopMarker(ColorScheme cs, {required bool dim}) {
    final ring = _dim(cs.outline, dim: dim);
    final fill = _dim(Colors.white, dim: dim);
    return _resolveMarker(
      'go_stop|${ring.toARGB32()}|${fill.toARGB32()}',
      () => MapMarkers.dot(fill, ring: ring, size: 9),
    );
  }

  // Markers for the selected/previewed route only. Origin/destination anchor
  // the ends; each transit leg's board/alight get a leg-colored ring (transfers
  // dedupe by position); intermediate stops get tiny neutral dots. While
  // navigating, markers of already-passed legs dim in step with their lines.
  Set<Marker> _buildMarkers(PlanRoute route, int? activeLeg, ColorScheme cs) {
    final sections = route.sections;
    if (sections.isEmpty) return const {};
    final markers = <Marker>{};
    // Higher-priority markers claim a coordinate first; a lower-priority marker
    // at the same spot (e.g. a transfer boundary under the origin) is skipped.
    final used = <String>{};
    String posKey(PlanPoint p) =>
        '${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}';
    bool valid(PlanPoint p) => p.lat != 0 || p.lng != 0;
    bool dimLeg(int i) => activeLeg != null && i < activeLeg;

    void place(String id, PlanPoint p, BitmapDescriptor? icon, int z) {
      if (icon == null || !valid(p) || !used.add(posKey(p))) return;
      markers.add(
        Marker(
          markerId: MarkerId(id),
          position: LatLng(p.lat, p.lng),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          zIndexInt: z,
        ),
      );
    }

    place(
      'origin',
      sections.first.departure.location,
      _originMarker(cs, dim: dimLeg(0)),
      30,
    );
    place(
      'dest',
      sections.last.arrival.location,
      _destMarker(cs, dim: dimLeg(sections.length - 1)),
      30,
    );
    for (final (i, s) in sections.indexed) {
      if (isWalk(s)) continue;
      final color = transitColor(s.transport, cs);
      final dim = dimLeg(i);
      final icon = _boundaryMarker(color, dim: dim);
      place('board_$i', s.departure.location, icon, 20);
      place('alight_$i', s.arrival.location, icon, 20);
    }
    for (final (i, s) in sections.indexed) {
      if (isWalk(s)) continue;
      final dim = dimLeg(i);
      for (final (j, stop) in s.intermediateStops.indexed) {
        place('stop_${i}_$j', stop.location, _stopMarker(cs, dim: dim), 10);
      }
    }
    return markers;
  }

  // Recomputes the cached overlays only when the result identity, selected
  // route, active leg, or theme colors change; identical inputs reuse the sets.
  void _ensureOverlays(
    PlanResult result,
    int selectedIndex,
    int? activeLeg,
    ColorScheme cs,
  ) {
    if (identical(_overlayResult, result) &&
        _overlaySelected == selectedIndex &&
        _overlayLeg == activeLeg &&
        identical(_overlayScheme, cs)) {
      return;
    }
    _overlayResult = result;
    _overlaySelected = selectedIndex;
    _overlayLeg = activeLeg;
    _overlayScheme = cs;
    _overlayPolylines = _buildPolylines(result, selectedIndex, activeLeg, cs);
    _overlayMarkers = _buildMarkers(
      result.routes[selectedIndex],
      activeLeg,
      cs,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The session can reach `done` on its own (last leg alighted, or the 8h
    // ActivityKit cap). Mirror that back into PlanBloc + PiP so the panel
    // reverts even when the user didn't tap 結束導航.
    return BlocListener<JourneySessionBloc, JourneySessionState>(
      listenWhen: (p, c) => p.phase != c.phase && c.phase == JourneyPhase.done,
      listener: (context, _) => unawaited(_reconcileJourneyDone()),
      child: _buildPlanner(),
    );
  }

  Widget _buildPlanner() {
    return BlocConsumer<PlanBloc, PlanState>(
      // Camera reframes on entering a phase or switching the previewed route.
      listenWhen: (p, c) =>
          (p.status != c.status && c.status == PlanStatus.success) ||
          p.selectedRouteIndex != c.selectedRouteIndex ||
          p.previewing != c.previewing,
      // activeStopIndex advances within a leg as the user progresses but does
      // not affect this subtree, so skip those emissions.
      buildWhen: (p, c) =>
          p.status != c.status ||
          p.result != c.result ||
          p.error != c.error ||
          p.selectedRouteIndex != c.selectedRouteIndex ||
          p.previewing != c.previewing ||
          p.activeLegIndex != c.activeLegIndex ||
          p.activeWalkStepIndex != c.activeWalkStepIndex ||
          p.savedRoutes.length != c.savedRoutes.length,
      listener: (context, state) {
        // Navigation drives its own camera.
        if (state.activeLegIndex != null) return;
        final result = state.result;
        if (result == null || result.routes.isEmpty) return;
        // Preview frames the selected route; results frame every alternative.
        if (state.previewing) {
          final route = _activeRoute(state);
          if (route != null) _fitTo(route);
        } else {
          _fitAll(result);
        }
      },
      builder: (context, state) {
        MapMarkers.configure(MediaQuery.devicePixelRatioOf(context));
        final navigating = state.activeLegIndex != null;
        final previewing = state.previewing;
        final route = _activeRoute(state);
        final result = state.result;
        final selectedIndex = _selectedIndex(state);
        if (result != null && selectedIndex != null) {
          _ensureOverlays(
            result,
            selectedIndex,
            navigating ? state.activeLegIndex : null,
            Theme.of(context).colorScheme,
          );
        }
        // Back walks the phases outward: navigating → end nav, previewing →
        // results list, results → leave the screen.
        return PopScope(
          canPop: !navigating && !previewing,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (navigating) {
              _endNav();
            } else if (previewing) {
              _closePreview();
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Stack(
              children: [
                Positioned.fill(
                  child: GoogleMap(
                    style: mapStyleOf(context),
                    initialCameraPosition: const CameraPosition(
                      target: _kDefaultPos,
                      zoom: 14,
                    ),
                    onMapCreated: (c) {
                      _map = c;
                      if (result == null || navigating) return;
                      if (previewing && route != null) {
                        _fitTo(route);
                      } else {
                        _fitAll(result);
                      }
                    },
                    // Fires for programmatic moves too, so ignore the app's own
                    // animations (via the guard counter) and only treat a
                    // real user gesture during navigation as a follow pause.
                    onCameraMoveStarted: () {
                      if (_programmaticMoves > 0 || !navigating) return;
                      if (DateTime.now().difference(_lastProgrammaticMove) <
                          _kProgrammaticMoveGrace) {
                        return;
                      }
                      if (!_followPaused) {
                        setState(() => _followPaused = true);
                      }
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    polylines: route == null ? const {} : _overlayPolylines,
                    markers: route == null ? const {} : _overlayMarkers,
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: navigating && route != null
                          ? _NavHeader(
                              route: route,
                              activeLeg: state.activeLegIndex!,
                              walkStepIndex: state.activeWalkStepIndex,
                            )
                          : _PlannerHeader(
                              origin: _origin,
                              dest: _dest,
                              onEditOrigin: () => _editField(origin: true),
                              onEditDest: () => _editField(origin: false),
                              onSwap: _swap,
                            ),
                    ),
                  ),
                ),
                if (navigating && route != null)
                  _NavSheet(
                    controller: _sheet,
                    route: route,
                    activeLeg: state.activeLegIndex!,
                    onAdvance: () => _advance(route, state.activeLegIndex!),
                    onEnd: _endNav,
                    showManualControls: !_autopilotDriving,
                  )
                else
                  _sheetSwap(state, route, selectedIndex),
              ],
            ),
          ),
        );
      },
    );
  }

  // Phase-swap between the results list and the plan-preview itinerary. Both
  // are full sheets; the swap animates with transform + opacity only (enter
  // ease-out ~240ms, exit faster ~150ms), collapsing to an instant swap under
  // reduce-motion.
  Widget _sheetSwap(PlanState state, PlanRoute? route, int? selectedIndex) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final showPreview = state.previewing && route != null;
    final routeCount = state.result?.routes.length ?? 0;
    final child = showPreview
        ? _PreviewSheet(
            key: const ValueKey('preview'),
            controller: _previewSheet,
            route: route,
            isFastest: routeCount > 1 && (selectedIndex ?? 0) == 0,
            isSaved: state.savedKeys.contains(route.savedKey),
            origin: _origin?.name,
            dest: _dest?.name,
            onBack: _closePreview,
            onStartNavigation: () =>
                _startFromPreview(route, selectedIndex ?? 0),
            onToggleSave: () => _toggleSave(route),
          )
        : _PlannerSheet(
            key: const ValueKey('planner'),
            controller: _sheet,
            state: state,
            hasDestination: _dest != null,
            onSelect: _previewRoute,
            onRetry: _retry,
            onPickDestination: () => _editField(origin: false),
            onAdjustOptions: _adjustOptions,
            onToggleSave: _toggleSave,
            onOpenSaved: _openSaved,
          );
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : AppMotion.medium,
      reverseDuration: reduce
          ? Duration.zero
          : const Duration(milliseconds: 150),
      switchInCurve: AppMotion.easeOut,
      switchOutCurve: AppMotion.easeOut,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: child,
    );
  }

  int? _selectedIndex(PlanState state) {
    final routes = state.result?.routes;
    if (routes == null || routes.isEmpty) return null;
    final i = state.selectedRouteIndex ?? 0;
    return i >= 0 && i < routes.length ? i : 0;
  }

  PlanRoute? _activeRoute(PlanState state) {
    final i = _selectedIndex(state);
    return i == null ? null : state.result!.routes[i];
  }
}
