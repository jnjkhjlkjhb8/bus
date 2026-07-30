import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_bus/app/theme/app_shadows.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/core/haptics/haptic_service.dart';
import 'package:wheres_the_bus/core/location/location_service.dart';
import 'package:wheres_the_bus/data/models/plan_models.dart';
import 'package:wheres_the_bus/data/repositories/maas_repository.dart';
import 'package:wheres_the_bus/data/repositories/settings_repository.dart';
import 'package:wheres_the_bus/features/go/bloc/plan_bloc.dart';
import 'package:wheres_the_bus/features/go/bloc/plan_event.dart';
import 'package:wheres_the_bus/features/go/bloc/plan_state.dart';
import 'package:wheres_the_bus/features/go/model/plan_options.dart';
import 'package:wheres_the_bus/features/go/model/planned_place.dart';
import 'package:wheres_the_bus/features/go/navigation/navigation_coordinator.dart';
import 'package:wheres_the_bus/features/go/view/place_search_screen.dart';
import 'package:wheres_the_bus/features/go/widgets/route_option_card.dart';
import 'package:wheres_the_bus/features/go/widgets/transit_visuals.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_bus/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/map/map_color_scheme.dart';
import 'package:wheres_the_bus/shared/map/marker_factory.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';
import 'package:wheres_the_bus/shared/widgets/app_badge.dart';
import 'package:wheres_the_bus/shared/widgets/app_button.dart';
import 'package:wheres_the_bus/shared/widgets/app_date_picker.dart';
import 'package:wheres_the_bus/shared/widgets/app_progress_bar.dart';
import 'package:wheres_the_bus/shared/widgets/app_quantity_selector.dart';
import 'package:wheres_the_bus/shared/widgets/app_range_slider.dart';
import 'package:wheres_the_bus/shared/widgets/app_slider.dart';
import 'package:wheres_the_bus/shared/widgets/app_sliding_segment.dart';
import 'package:wheres_the_bus/shared/widgets/app_snackbar.dart';
import 'package:wheres_the_bus/shared/widgets/app_time_picker.dart';
import 'package:wheres_the_bus/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_bus/shared/widgets/divider_line.dart';
import 'package:wheres_the_bus/shared/widgets/filter_chip_group.dart';

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
// zoom 15.5). The bearing is a fixed constant — the map never rotates; only
// the puck rotates to the device heading.
const _kNavZoom = 15.5;
const _kNavTilt = 45.0;
const _kNavBearing = 30.0;

// The departure/arrival stance for a plan query. `leaveNow` always re-queries
// with a fresh current time; `departAt`/`arriveBy` pin the chosen instant and
// map to the wire `arriveBy` flag. Surfaced only after a query (the results
// header time chip); plan entry is always `leaveNow`.
enum _TimeMode { leaveNow, departAt, arriveBy }

class GoScreen extends StatefulWidget {
  const GoScreen({super.key, this.initialDestination});

  /// A destination handed in by whoever opened the planner (a station detail
  /// saying "take me here"). The origin still resolves from GPS, so the plan
  /// fires on its own as soon as that lands — see [_GoScreenState._initOrigin].
  final PlannedPlace? initialDestination;

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
  // Whether the GPS fix that fills the origin is still coming, arrived, or was
  // refused — the field says which rather than showing an unfilled hint that
  // reads like a required choice.
  OriginStatus _originStatus = OriginStatus.resolving;
  PlannedPlace? _dest;
  PlanOptions _options = const PlanOptions();
  // Departure/arrival time stance for the query. `_timeAt` is only consulted
  // when `_timeMode` is not `leaveNow`.
  _TimeMode _timeMode = _TimeMode.leaveNow;
  DateTime _timeAt = DateTime.now();
  // Whether the autopilot currently has a live GPS fix flowing. Gates the
  // manual progression controls in the nav sheet: shown only when the
  // autopilot can't actually drive (no permission / location services off).
  bool _autopilotDriving = true;

  // Camera follow mode — ephemeral UI state, deliberately kept out of PlanBloc.
  // While navigating, each GPS fix recenters the camera on the user unless the
  // user has panned the map by gesture (then follow pauses until re-armed by a
  // nav (re)start or a leg advance).
  bool _followPaused = false;
  // Puck-only heading: the directional arrow's rotation, driven by the compass.
  // The camera bearing stays the _kNavBearing constant, so this never rotates
  // the map — it only points the puck at the device's true (north-referenced)
  // heading. Seeds to _kNavBearing until the first compass event.
  double _puckHeading = _kNavBearing;
  // Most recent navigation GPS fix, cached so the recenter button can snap the
  // camera back to the user, and so the puck can be placed at the user.
  Position? _lastFix;
  // Compass heading subscription — magnetometer draws battery, so it lives only
  // for the duration of an active navigation (started with follow, torn down at
  // nav end / dispose), never on the planner screen.
  StreamSubscription<double>? _compassSub;
  // Last compass heading actually applied to the puck, plus when — feeds the
  // shouldApplyHeading throttle.
  double? _lastAppliedHeading;
  DateTime _lastHeadingApplied = DateTime.fromMillisecondsSinceEpoch(0);
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
    _dest = widget.initialDestination;
    _sheet = SheetController();
    _previewSheet = SheetController();
    _navigationCoordinator = NavigationCoordinator(
      planBloc: context.read<PlanBloc>(),
      journeySessionBloc: context.read<JourneySessionBloc>(),
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
    _stopCompass();
    _map?.dispose();
    _sheet.dispose();
    _previewSheet.dispose();
    super.dispose();
  }

  Future<void> _initOrigin() async {
    if (mounted) setState(() => _originStatus = OriginStatus.resolving);
    // This runs synchronously out of initState, where reading an inherited
    // widget (Localizations, below) throws. Yield first so the lookup happens
    // once the element is settled — otherwise every open reported the origin
    // as unavailable, permission granted or not.
    await Future<void>.microtask(() {});
    if (!mounted) return;
    final i18n = AppI18n.of(context);
    try {
      final place = await resolveCurrentPlace(i18n);
      if (!mounted) return;
      setState(() {
        _origin = place;
        _originStatus = OriginStatus.resolved;
      });
      // No-op unless a destination was seeded in (see [GoScreen
      // .initialDestination]); with one, this is what fires the plan once the
      // GPS fix that completes the pair finally lands. A denied or failed fix
      // leaves the destination filled and the origin field waiting for a pick,
      // which is the same state as opening the planner and typing a
      // destination first.
      _maybePlan();
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _originStatus = OriginStatus.unavailable);
    }
  }

  Future<void> _editField({required bool origin}) async {
    final picked = await showPlaceSearchPage(
      context,
      fieldLabel: origin
          ? AppI18n.of(context).goChooseOrigin
          : AppI18n.of(context).goChooseDestination,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (origin) {
        _origin = picked;
        _originStatus = OriginStatus.resolved;
      } else {
        _dest = picked;
      }
    });
    _maybePlan();
  }

  // A destination picked from the plan-entry shortcut list. If the origin isn't
  // resolved yet (GPS pending or denied), don't swallow the pick — send the
  // user to choose an origin first, then plan with both set.
  void _pickDestination(PlannedPlace place) {
    if (_origin == null) {
      unawaited(_resolveOriginThenPlan(place));
      return;
    }
    setState(() => _dest = place);
    _maybePlan();
  }

  Future<void> _resolveOriginThenPlan(PlannedPlace dest) async {
    final picked = await showPlaceSearchPage(
      context,
      fieldLabel: AppI18n.of(context).goChooseOrigin,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _origin = picked;
      _dest = dest;
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
    // `leaveNow` always resolves a fresh timestamp; the other modes pin the
    // user's chosen instant and set the wire `arriveBy` flag accordingly.
    final when = _timeMode == _TimeMode.leaveNow ? DateTime.now() : _timeAt;
    String two(int v) => v.toString().padLeft(2, '0');
    // A fresh search invalidates every marker built for the prior results;
    // drop them so the caches don't grow for the life of the screen across
    // successive searches. Markers for the new plan rebuild on the next
    // _ensureOverlays pass once results arrive.
    _markerCache.clear();
    _markerPending.clear();
    context.read<PlanBloc>().add(
      PlanSearchRequested(
        fromLat: from.latLng.latitude,
        fromLon: from.latLng.longitude,
        toLat: to.latLng.latitude,
        toLon: to.latLng.longitude,
        date: '${when.year}-${two(when.month)}-${two(when.day)}',
        time: '${two(when.hour)}:${two(when.minute)}',
        arriveBy: _timeMode == _TimeMode.arriveBy,
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

  // Give up on a query that is taking too long. The destination is cleared with
  // it so the screen falls back to the entry surface rather than sitting on a
  // map with nothing on it; the origin and the typed options survive.
  void _cancelPlan() {
    unawaited(HapticService.instance.lightTap());
    context.read<PlanBloc>().add(const PlanSearchCancelled());
    setState(() => _dest = null);
  }

  // A saved route between the same two points, matched on where it actually
  // starts and ends rather than on the place names — the same corner searched
  // twice can come back with two different labels. Shown while waiting, so a
  // rider on a trip they have taken before sees it immediately.
  PlanRoute? _lastRouteForTrip(List<PlanRoute> saved) {
    final from = _origin?.latLng;
    final to = _dest?.latLng;
    if (from == null || to == null) return null;
    for (final route in saved) {
      final sections = route.sections;
      if (sections.isEmpty) continue;
      final start = sections.first.departure.location;
      final end = sections.last.arrival.location;
      if (_near(from, start) && _near(to, end)) return route;
    }
    return null;
  }

  // Within a short walk of the same spot. Loose on purpose: a saved route's
  // ends are the stop it boarded at, not the address that was searched for.
  static const _kSameTripMeters = 400.0;

  double? _straightLineMeters() {
    final from = _origin?.latLng;
    final to = _dest?.latLng;
    if (from == null || to == null) return null;
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  bool _near(LatLng a, PlanPoint b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.lat, b.lng) <=
      _kSameTripMeters;

  Future<void> _adjustOptions() async {
    final picked = await showOptionsSheet(context, current: _options);
    if (picked == null || !mounted || picked == _options) return;
    setState(() => _options = picked);
    _maybePlan();
  }

  Future<void> _adjustTime() async {
    final picked = await _showTimeModeSheet(
      context,
      mode: _timeMode,
      at: _timeAt,
    );
    if (picked == null || !mounted) return;
    // No re-plan when nothing effectively changed (same mode, and — for the
    // timed modes — the same instant).
    final sameInstant =
        picked.mode == _TimeMode.leaveNow || picked.at == _timeAt;
    if (picked.mode == _timeMode && sameInstant) return;
    setState(() {
      _timeMode = picked.mode;
      _timeAt = picked.at;
    });
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
        AppI18n.of(context).favoritesRemoved,
        action: AppI18n.of(context).commonUndo,
        onAction: () => bloc.add(RouteSaveToggled(route)),
      );
    }
  }

  void _openSaved(PlanRoute route) {
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
    // (Re)starting navigation re-arms follow and reseeds the puck heading; the
    // compass then rotates the puck (never the map) as fixes drive the camera.
    setState(() => _followPaused = false);
    _puckHeading = _kNavBearing;
    _lastAppliedHeading = null;
    _startCompass();
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

  // Subscribes to the compass only while navigating; a no-op if already live so
  // a nav restart doesn't stack subscriptions.
  void _startCompass() {
    _compassSub ??= LocationService.instance.compassStream().listen(
      _onCompassHeading,
    );
  }

  void _stopCompass() {
    unawaited(_compassSub?.cancel());
    _compassSub = null;
    _lastAppliedHeading = null;
  }

  // Compass event: rotate only the puck to the phone's heading while
  // navigating, including standing still — the map never rotates. Throttled by
  // shouldApplyHeading so it stays under ~5 setStates/sec and ignores sub-3°
  // jitter. Not gated on _followPaused: the puck stays visible (and honest)
  // even after a gesture pause.
  void _onCompassHeading(double heading) {
    if (!mounted) return;
    final navigating = context.read<PlanBloc>().state.activeLegIndex != null;
    if (!navigating) return;
    if (!shouldApplyHeading(
      last: _lastAppliedHeading,
      next: heading,
      sinceLast: DateTime.now().difference(_lastHeadingApplied),
    )) {
      return;
    }
    _lastAppliedHeading = heading;
    _lastHeadingApplied = DateTime.now();
    // Rotate the directional puck; heading is north-referenced and the camera
    // stays at _kNavBearing, so no bearing compensation is needed.
    setState(() => _puckHeading = heading);
  }

  // Each navigation GPS fix. Keeps the camera on the user (tilt/zoom/bearing
  // all fixed — only the target follows) unless the user has panned away.
  void _onFollowUpdate(Position fix) {
    if (!mounted) return;
    // Cache every fix (even while paused) so the recenter button and the puck
    // always have a fresh position.
    _lastFix = fix;
    final navigating = context.read<PlanBloc>().state.activeLegIndex != null;
    // Move the directional puck to the new fix.
    if (navigating) setState(() {});
    if (!navigating || _followPaused) return;
    _followTo(fix);
  }

  void _followTo(Position fix) {
    // The camera bearing is the fixed _kNavBearing — the map never rotates, so
    // a follow tick only recenters the target.
    unawaited(
      _animateCameraGuarded(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(fix.latitude, fix.longitude),
            zoom: _kNavZoom,
            bearing: _kNavBearing,
            tilt: _kNavTilt,
          ),
        ),
      ),
    );
  }

  // Puck tap: re-arm follow and snap the camera back to the user.
  void _recenterFollow() {
    unawaited(HapticService.instance.lightTap());
    setState(() => _followPaused = false);
    final fix = _lastFix;
    if (fix != null) _followTo(fix);
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
      AppSnackbar.show(
        context,
        AppI18n.of(context).goArrived,
        type: SnackType.success,
      );
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
      AppSnackbar.show(
        context,
        AppI18n.of(context).goArrived,
        type: SnackType.success,
      );
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
    // Every navigation-end path funnels through here (manual end, auto-arrival,
    // self-completed journey), so release the compass here too.
    _stopCompass();
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

      // Walk sections trace the real OSRM foot path when it resolved; rail
      // transit sections trace the line geometry the router clipped to this
      // section's stops when it resolved. Either way, an unresolved path
      // falls back to a straight line through departure→intermediateStops→
      // arrival.
      if (walk && s.walkPath.isNotEmpty) {
        s.walkPath.forEach(add);
      } else if (!walk && s.transitPath.isNotEmpty) {
        s.transitPath.forEach(add);
      } else {
        add(s.departure.location);
        for (final stop in s.intermediateStops) {
          add(stop.location);
        }
        add(s.arrival.location);
      }
      if (pts.length < 2) continue;
      final dim = activeLeg != null && i < activeLeg;
      Color d(Color c) => dim ? c.withValues(alpha: 0.3) : c;
      if (walk) {
        // White-cased ink dots: a wide card-colored casing under narrower ink
        // dots, both on the same points/pattern so the dots read against any
        // map background. Card color matches the nav header's card.
        final card = cs.brightness == Brightness.light
            ? Colors.white
            : cs.surfaceContainerHigh;
        final pattern = [PatternItem.dot, PatternItem.gap(16)];
        lines
          ..add(
            Polyline(
              polylineId: PolylineId('leg_${i}_casing'),
              points: pts,
              width: 11,
              color: d(card),
              // Casing sits below its dots, both above the muted alternates.
              zIndex: 2,
              patterns: pattern,
            ),
          )
          ..add(
            Polyline(
              polylineId: PolylineId('leg_$i'),
              points: pts,
              width: 7,
              color: d(cs.onSurface),
              zIndex: 3,
              patterns: pattern,
            ),
          );
      } else {
        final base = transitColor(s.transport, cs);
        lines.add(
          Polyline(
            polylineId: PolylineId('leg_$i'),
            points: pts,
            width: 6,
            color: d(base),
            // Sits above the muted alternates.
            zIndex: 2,
          ),
        );
      }
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

  // Directional user puck during navigation: an ink arrow on a white disc at
  // the latest fix, replacing the default blue dot. Flat + center-anchored;
  // its rotation is the north-referenced compass heading and the map stays at
  // _kNavBearing, so the arrow points at the device's true heading on the map.
  // Shown for the whole navigation regardless of follow state — gated only on
  // having a fix. Rebuilt on each fix (position) and each applied heading
  // (rotation), both throttled upstream, so never at raw compass rate.
  Marker? _navPuck(ColorScheme cs) {
    final fix = _lastFix;
    if (fix == null) return null;
    // Card color matches the nav header's card (white in light, elevated
    // surface in dark); it forms the puck's ring and arrow glyph.
    final card = cs.brightness == Brightness.light
        ? Colors.white
        : cs.surfaceContainerHigh;
    final icon = _resolveMarker(
      'go_nav_puck|${cs.onSurface.toARGB32()}|${card.toARGB32()}',
      () => MapMarkers.navArrow(cs.onSurface, card),
    );
    if (icon == null) return null;
    return Marker(
      markerId: const MarkerId('nav_puck'),
      position: LatLng(fix.latitude, fix.longitude),
      icon: icon,
      anchor: const Offset(0.5, 0.5),
      rotation: _puckHeading,
      flat: true,
      zIndexInt: 40,
      // Doubles as the recenter affordance: tapping re-arms follow and snaps
      // back to the user. Harmless while already following (puck is centered);
      // it only matters after a gesture pause.
      onTap: _recenterFollow,
    );
  }

  // What the map can honestly show before the router answers: the two ends and
  // the straight line between them. It is not a route and does not pretend to
  // be one — dotted, muted, and replaced the moment real geometry arrives.
  Set<Polyline> _pendingLines(ColorScheme cs) {
    final from = _origin?.latLng;
    final to = _dest?.latLng;
    if (from == null || to == null) return const {};
    return {
      Polyline(
        polylineId: const PolylineId('pending_direct'),
        points: [from, to],
        width: 3,
        color: cs.onSurface.withValues(alpha: 0.45),
        patterns: [PatternItem.dot, PatternItem.gap(14)],
      ),
    };
  }

  Set<Marker> _pendingMarkers(ColorScheme cs) {
    final from = _origin?.latLng;
    final to = _dest?.latLng;
    if (from == null || to == null) return const {};
    final origin = _originMarker(cs, dim: false);
    final dest = _destMarker(cs, dim: false);
    return {
      if (origin != null)
        Marker(
          markerId: const MarkerId('pending_origin'),
          position: from,
          icon: origin,
          anchor: const Offset(0.5, 0.5),
        ),
      if (dest != null)
        Marker(
          markerId: const MarkerId('pending_dest'),
          position: to,
          icon: dest,
          anchor: const Offset(0.5, 0.5),
        ),
    };
  }

  // Frames the pair while the query runs, so the map is about this trip from
  // the first frame instead of sitting on a default city view.
  void _fitPending() {
    final from = _origin?.latLng;
    final to = _dest?.latLng;
    if (from == null || to == null) return;
    _fitBounds([from, to]);
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
      // Loading counts as a phase: framing the origin/destination pair is what
      // makes the wait look like it is about this trip.
      listenWhen: (p, c) =>
          (p.status != c.status &&
              (c.status == PlanStatus.success ||
                  c.status == PlanStatus.loading)) ||
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
        if (state.status == PlanStatus.loading) {
          _fitPending();
          return;
        }
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
            // Plan entry is a map-less phase: while no destination is chosen
            // the GoogleMap is not built at all, so the planner never opens on
            // the map first. Choosing a destination crossfades to the map.
            body: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppMotion.medium,
              switchInCurve: AppMotion.easeOut,
              switchOutCurve: AppMotion.easeOut,
              child: (!navigating && !previewing && _dest == null)
                  ? _PlannerEntry(
                      key: const ValueKey('entry'),
                      origin: _origin,
                      originStatus: _originStatus,
                      savedRoutes: state.savedRoutes,
                      onEditOrigin: () => _editField(origin: true),
                      onSwap: _swap,
                      onPickDestination: _pickDestination,
                      onOpenSaved: _openSaved,
                      onToggleSave: _toggleSave,
                      onBack: () => context.pop(),
                      onEnableLocation: () => unawaited(_initOrigin()),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('map'),
                      child: _mapPhase(
                        context,
                        state,
                        navigating: navigating,
                        previewing: previewing,
                        route: route,
                        result: result,
                        selectedIndex: selectedIndex,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  // The map phase: the GoogleMap with the planner/nav header and the results /
  // preview / nav sheet. Built only once a destination exists (never during
  // plan entry), so the map is not instantiated on the planner's landing.
  Widget _mapPhase(
    BuildContext context,
    PlanState state, {
    required bool navigating,
    required bool previewing,
    required PlanRoute? route,
    required PlanResult? result,
    required int? selectedIndex,
  }) {
    return Stack(
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
              if (navigating) return;
              if (result == null) {
                _fitPending();
                return;
              }
              if (previewing && route != null) {
                _fitTo(route);
              } else {
                _fitAll(result);
              }
            },
            // Fires for programmatic moves too, so ignore the app's own
            // animations (via the guard counter) and only treat a real user
            // gesture during navigation as a follow pause.
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
            // The default blue dot only in the planner; navigation renders its
            // own directional arrow puck instead.
            myLocationEnabled: !navigating,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            polylines: route == null
                ? _pendingLines(Theme.of(context).colorScheme)
                : _overlayPolylines,
            markers: {
              if (route != null)
                ..._overlayMarkers
              else
                ..._pendingMarkers(Theme.of(context).colorScheme),
              if (navigating) ?_navPuck(Theme.of(context).colorScheme),
            },
            // Map shares a Stack with the draggable sheet; without an eager
            // recognizer the map loses the gesture arena, so pan/pinch leak
            // to the sheet instead of moving the map.
            gestureRecognizers: const {
              Factory<OneSequenceGestureRecognizer>(
                EagerGestureRecognizer.new,
              ),
            },
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
            initialOffset: carriedSheetOffset(
              _sheet,
              min: AppSheetSnap.peekFrac,
              max: AppSheetSnap.fullFrac,
              fallback: AppSheetSnap.halfFrac,
            ),
            route: route,
            activeLeg: state.activeLegIndex!,
            onAdvance: () => _advance(route, state.activeLegIndex!),
            onEnd: _endNav,
            showManualControls: !_autopilotDriving,
          )
        else
          _sheetSwap(state, route, selectedIndex),
      ],
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
            // Carry the planner sheet's height into the preview swap.
            initialOffset: carriedSheetOffset(
              _sheet,
              min: AppSheetSnap.peekFrac,
              max: AppSheetSnap.fullFrac,
              fallback: AppSheetSnap.halfFrac,
            ),
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
            // Carry the preview sheet's height back into the planner swap.
            initialOffset: carriedSheetOffset(
              _previewSheet,
              min: AppSheetSnap.peekFrac,
              max: AppSheetSnap.fullFrac,
              fallback: AppSheetSnap.halfFrac,
            ),
            state: state,
            hasDestination: _dest != null,
            timeMode: _timeMode,
            timeAt: _timeAt,
            routeCount: _options.top,
            lastRoute: _lastRouteForTrip(state.savedRoutes),
            straightLineMeters: _straightLineMeters(),
            onSelect: _previewRoute,
            onRetry: _retry,
            onCancel: _cancelPlan,
            onAdjustOptions: _adjustOptions,
            onAdjustTime: _adjustTime,
            onToggleSave: _toggleSave,
          );
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : AppMotion.medium,
      reverseDuration: reduce ? Duration.zero : AppMotion.micro,
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
