import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/app.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/data/models/near_models.dart';
import 'package:wheres_the_car/data/repositories/favorites_repository.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_state.dart';
import 'package:wheres_the_car/features/alerts/view/alert_banner.dart';
import 'package:wheres_the_car/features/alerts/view/notification_sheet.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_state.dart';
import 'package:wheres_the_car/features/favorites/widgets/favorite_tile.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_bloc.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_event.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_state.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_viewport_query.dart';
import 'package:wheres_the_car/features/home/widgets/home_station_detail.dart';
import 'package:wheres_the_car/features/metro/widgets/metro_svg_map.dart';
import 'package:wheres_the_car/features/rail/view/home_rail_query_sheet.dart';
import 'package:wheres_the_car/shared/map/map_color_scheme.dart';
import 'package:wheres_the_car/shared/map/marker_factory.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_spinner.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/route_tab_bar.dart';
import 'package:wheres_the_car/shared/widgets/state_cards.dart';
import 'package:wheres_the_car/shared/widgets/transport_icon.dart';

part 'widgets/home_marker_helpers.dart';
part 'widgets/home_scaffold_widgets.dart';
part 'widgets/home_map_skeleton.dart';
part 'widgets/home_favorites_widgets.dart';
part 'widgets/home_nearby_widgets.dart';

const _kDefaultPosition = LatLng(25.0330, 121.5654);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  late final SheetController _sheetController;
  final GlobalKey<NavigatorState> _sheetNavigatorKey =
      GlobalKey<NavigatorState>();
  late final TabController _tabController;
  LatLng _center = _kDefaultPosition;
  LatLng _camCenter = _kDefaultPosition;
  double _zoom = 15;
  _MarkerStyle _markerStyleCache = _MarkerStyle.largeDot;
  Set<Marker> _markers = {};
  int _markerRevision = 0;
  Timer? _idleDebounce;

  /// Attempted/succeeded nearby-query centers — see [NearbyViewportQuery]:
  /// a failed attempt never suppresses a retry, only a successful one does.
  NearbyViewportQuery _viewportQuery = const NearbyViewportQuery();

  /// True once the initial fresh-GPS fix has resolved (success or failure).
  /// Nearby queries are gated on this so the cached/default-Taipei position
  /// the map shows immediately never itself triggers a station fetch.
  bool _freshLocationResolved = false;

  /// When the last sonar ring was emitted; dedupes back-to-back pings.
  DateTime? _lastPingAt;
  bool _sheetAtTop = false;
  bool _mapReady = false;
  bool _tabApplied = false;

  String? _highlightedKey;

  /// Latest nearby stations, mirrored from [NearbyBloc] by the listener in
  /// [build]. Focus/unfocus read this instead of `context.read<NearbyBloc>()`
  /// because those run on the State's context, which sits above the provider.
  List<NearStationViewModel> _stations = const [];

  /// True while a manual "locate me" tap is acquiring the GPS fix — drives the
  /// recenter FAB's spinner so the button never reads as doing nothing.
  bool _locating = false;

  /// Fires a one-shot sonar ring at the user's on-screen position after a
  /// manual recenter. Null until the first ping.
  final ValueNotifier<_Ping?> _ping = ValueNotifier<_Ping?>(null);

  Future<void> _rebuildMarkers(List<NearStationViewModel> stations) async {
    final revision = ++_markerRevision;
    final style = _markerStyle(_zoom);
    final markers = await Future.wait(
      stations.take(_kMapMarkerLimit).map((s) async {
        final key = '${s.type.name}:${s.stationId}';
        final highlighted = key == _highlightedKey;
        final icon = await _markerIcon(s, style, highlighted: highlighted);
        return Marker(
          markerId: MarkerId('${s.type.name}:${s.stationId}'),
          position: LatLng(s.lat, s.lon),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(title: s.stationName),
          onTap: () {
            unawaited(HapticService.instance.lightTap());
            _openStationDetail(s);
          },
        );
      }),
    );
    if (!mounted || revision != _markerRevision) return;
    setState(() {
      _markerStyleCache = style;
      _markers = markers.toSet();
    });
  }

  void _openStationDetail(NearStationViewModel station) {
    _focusStationOnMap(station);
    final navigator = _sheetNavigatorKey.currentState;
    if (navigator == null) return;
    unawaited(
      navigator
          .push(
            PagedSheetRoute<void>(
              scrollConfiguration: const SheetScrollConfiguration(),
              // Open where the sheet already is, so drilling in from the
              // nearby list doesn't jump the height.
              initialOffset: carriedSheetOffset(
                _sheetController,
                min: AppSheetSnap.peekFrac,
                max: AppSheetSnap.fullFrac,
                fallback: AppSheetSnap.halfFrac,
              ),
              snapGrid: AppSheetSnap.grid,
              builder: (_) => stationDetailPage(station),
            ),
          )
          .then((_) => _unfocusStationOnMap()),
    );
  }

  void _openRailQuerySheet() {
    unawaited(HapticService.instance.lightTap());
    final navigator = _sheetNavigatorKey.currentState;
    if (navigator == null) return;
    unawaited(
      navigator.push(
        PagedSheetRoute<void>(
          scrollConfiguration: const SheetScrollConfiguration(),
          initialOffset: AppSheetSnap.half,
          snapGrid: AppSheetSnap.grid,
          builder: (_) => const HomeRailQuerySheet(),
        ),
      ),
    );
  }

  void _focusStationOnMap(NearStationViewModel station) {
    final key = '${station.type.name}:${station.stationId}';
    setState(() => _highlightedKey = key);
    final controller = _mapController;
    if (controller != null) {
      unawaited(
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(station.lat, station.lon), 16.5),
        ),
      );
    }
    unawaited(_rebuildMarkers(_stations));
  }

  void _unfocusStationOnMap() {
    if (!mounted) return;
    setState(() => _highlightedKey = null);
    unawaited(_rebuildMarkers(_stations));
  }

  Future<void> _requestNearbyForViewport(NearbyBloc bloc) async {
    // Home queries only after the initial fresh-GPS fix has resolved — never
    // off the cached/default-Taipei position the map shows meanwhile.
    if (!_freshLocationResolved) return;
    // Skip re-querying when the camera is still within the area of the last
    // *successful* fetch — sub-200 m nudges return essentially the same
    // stations. A failed attempt is deliberately excluded from this check
    // (see NearbyViewportQuery), so it can't suppress the next retry.
    if (!_viewportQuery.shouldQuery(_camCenter)) return;
    final controller = _mapController;
    if (controller == null) return;
    final bounds = await controller.getVisibleRegion();
    if (!mounted) return;
    final radius = nearbyRadiusForViewport(center: _camCenter, bounds: bounds);
    _viewportQuery = _viewportQuery.withAttempted(_camCenter);
    bloc.add(
      NearbyRequested(
        lat: _camCenter.latitude,
        lon: _camCenter.longitude,
        radius: radius,
      ),
    );
    // Sonar cue at the query center; skipped under reduce-motion / no controller
    // by _playPing's own guards.
    unawaited(_playPing(_camCenter, radiusMeters: radius));
  }

  void _scheduleNearbyForViewport(BuildContext context) {
    _idleDebounce?.cancel();
    _idleDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      unawaited(_requestNearbyForViewport(context.read<NearbyBloc>()));
    });
  }

  void _onCameraIdle(BuildContext context) {
    final style = _markerStyle(_zoom);
    if (style != _markerStyleCache) {
      unawaited(_rebuildMarkers(context.read<NearbyBloc>().state.stations));
    }
    _scheduleNearbyForViewport(context);
  }

  double _mapBottomPadding(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return (height * 0.30).clamp(180.0, 280.0);
  }

  @override
  void initState() {
    super.initState();
    _sheetController = SheetController();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _initialTabIndex(),
    );
    if (FavoritesRepository.instance.isReady) {
      _tabApplied = true;
    } else {
      App.isInitialized.addListener(_onFavoritesReady);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeMapPosition());
      if (mounted) MetroSvgMap.precache(context);
    });
  }

  int _initialTabIndex() =>
      FavoritesRepository.instance.pinned().isNotEmpty ? 0 : 1;

  void _onFavoritesReady() {
    if (!App.isInitialized.value || _tabApplied) return;
    App.isInitialized.removeListener(_onFavoritesReady);
    _tabApplied = true;
    if (FavoritesRepository.instance.pinned().isNotEmpty) {
      _tabController.animateTo(0);
    }
  }

  Future<void> _initializeMapPosition() async {
    // Show the map immediately at the last OS-cached fix (default center when
    // none) instead of blocking on a fresh GPS fix, which can take up to 10 s
    // cold. The fresh fix pans the camera when it arrives.
    final last = await LocationService.instance.lastKnownPosition();
    if (!mounted) return;
    setState(() {
      if (last != null) {
        _center = LatLng(last.latitude, last.longitude);
        _camCenter = _center;
      }
      _mapReady = true;
    });
    try {
      final pos = await LocationService.instance.currentPosition();
      if (!mounted) return;
      final target = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = target;
        _camCenter = target;
      });
      // If the map is already up, pan to the fix; the resulting camera-idle
      // re-queries nearby stations. Before map creation, initialCameraPosition
      // picks up the new _center on its own.
      final controller = _mapController;
      if (controller != null) {
        unawaited(controller.animateCamera(CameraUpdate.newLatLng(target)));
      }
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
    } finally {
      // Resolved either way — success or failure — so the fresh-location gate
      // in _requestNearbyForViewport lets the next camera-idle event through.
      if (mounted) setState(() => _freshLocationResolved = true);
    }
  }

  Future<void> _locateUser() async {
    if (mounted) setState(() => _locating = true);
    try {
      final pos = await LocationService.instance.currentPosition();
      final target = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _center = target;
        _camCenter = target;
        _locating = false;
      });
      final controller = _mapController;
      if (controller == null) return;
      unawaited(controller.animateCamera(CameraUpdate.newLatLng(target)));
      await _playPing(target);
    } on Object catch (e, s) {
      if (mounted) setState(() => _locating = false);
      CrashReporter.record(e, s);
    }
  }

  /// On-screen radius, in logical pixels, that [radiusMeters] spans at the
  /// current zoom around [center]. Measures the pixel gap between [c0] (the
  /// already-fetched screen coordinate of [center]) and a point [radiusMeters]
  /// due east. Returns null if the widget unmounts.
  Future<double?> _groundRadiusPixels(
    GoogleMapController controller,
    LatLng center,
    ScreenCoordinate c0,
    int radiusMeters,
  ) async {
    final eastLon =
        center.longitude +
        radiusMeters / (111320 * math.cos(center.latitude * math.pi / 180));
    final c1 = await controller.getScreenCoordinate(
      LatLng(center.latitude, eastLon),
    );
    if (!mounted) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (c1.x - c0.x).abs() / dpr;
  }

  /// Emits a single expanding ring at [target]'s screen position once the
  /// camera move has settled, growing to the on-screen size of [radiusMeters]
  /// (the actual query radius sent, or the fixed fallback for the manual
  /// "locate me" ping, which issues no query of its own). `getScreenCoordinate`
  /// returns physical pixels, so divide by the device ratio for logical layout
  /// coordinates.
  Future<void> _playPing(
    LatLng target, {
    int radiusMeters = _kNearbyRadiusMeters,
  }) async {
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final controller = _mapController;
    if (!mounted || controller == null) return;
    final coord = await controller.getScreenCoordinate(target);
    final radius = await _groundRadiusPixels(
      controller,
      target,
      coord,
      radiusMeters,
    );
    if (!mounted || radius == null) return;
    final now = DateTime.now();
    final last = _lastPingAt;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastPingAt = now;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    _ping.value = _Ping(Offset(coord.x / dpr, coord.y / dpr), radius);
  }

  void _recenter() {
    unawaited(HapticService.instance.lightTap());
    unawaited(_locateUser());
  }

  @override
  void dispose() {
    _idleDebounce?.cancel();
    App.isInitialized.removeListener(_onFavoritesReady);
    _sheetController.dispose();
    _tabController.dispose();
    _ping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    MapMarkers.configure(MediaQuery.devicePixelRatioOf(context));
    return BlocProvider(
      create: (_) => NearbyBloc(),
      child: Builder(
        builder: (context) => BlocListener<NearbyBloc, NearbyState>(
          listenWhen: (p, c) =>
              !listEquals(p.stations, c.stations) ||
              p.loading != c.loading ||
              p.error != c.error,
          listener: (_, state) {
            _stations = state.stations;
            unawaited(_rebuildMarkers(state.stations));
            // A successful response (not a stale one — NearbyBloc's own
            // generation guard already dropped those) confirms data for the
            // center it was attempted at; only then does it count as
            // "already have this" for the next idle-triggered dedup check.
            if (!state.loading && state.error == null) {
              final attempted = _viewportQuery.lastAttempted;
              if (attempted != null) {
                _viewportQuery = _viewportQuery.withSuccess(attempted);
              }
            }
          },
          child: _buildScaffold(context, cs),
        ),
      ),
    );
  }
}

@visibleForTesting
Widget buildNearbyRowForTest({
  required NearStationViewModel station,
  required ValueChanged<NearStationViewModel> onStationTap,
}) => _NearbyStationRow(station: station, onStationTap: onStationTap);

/// Dot marker diameter (logical px) for the mid ([large] = true) vs the most
/// zoomed-out ([large] = false) marker band. Exposed so a plain unit test can
/// verify the intended ordering — large > small — without spinning up a map.
@visibleForTesting
double dotMarkerSizeForTest({required bool large}) =>
    large ? _kLargeDotSize : _kSmallDotSize;
