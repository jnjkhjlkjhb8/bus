import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/app.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/data/models/near_models.dart';
import 'package:wheres_the_car/data/repositories/favorites_repository.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_state.dart';
import 'package:wheres_the_car/features/alerts/view/notification_sheet.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_state.dart';
import 'package:wheres_the_car/features/favorites/widgets/favorite_tile.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_bloc.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_event.dart';
import 'package:wheres_the_car/features/home/bloc/nearby_state.dart';
import 'package:wheres_the_car/features/home/widgets/home_station_detail.dart';
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
  /// Center of the last nearby query actually sent; used to suppress redundant
  /// re-queries when the camera settles only a few metres away.
  LatLng? _lastQueryCenter;
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
              initialOffset: const SheetOffset.proportionalToViewport(0.55),
              snapGrid: const SheetSnapGrid(
                snaps: [
                  SheetOffset.proportionalToViewport(0.30),
                  SheetOffset.proportionalToViewport(0.55),
                  SheetOffset.proportionalToViewport(1),
                ],
              ),
              builder: (_) => stationDetailPage(station),
            ),
          )
          .then((_) => _unfocusStationOnMap()),
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

  double _distanceMeters(LatLng a, LatLng b) {
    const earth = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earth * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  Future<void> _requestNearbyForViewport(NearbyBloc bloc) async {
    // Skip re-querying when the camera barely moved — sub-200 m nudges return
    // essentially the same stations and only churn markers.
    final last = _lastQueryCenter;
    if (last != null && _distanceMeters(_camCenter, last) < 200) return;
    _lastQueryCenter = _camCenter;
    bloc.add(
      NearbyRequested(
        lat: _camCenter.latitude,
        lon: _camCenter.longitude,
        radius: _kNearbyRadiusMeters,
      ),
    );
    // Sonar cue at the query center; skipped under reduce-motion / no controller
    // by _playPing's own guards.
    unawaited(_playPing(_camCenter));
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
      Timer(const Duration(milliseconds: 700), () {
        unawaited(_initializeMapPosition());
      });
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
    var target = _kDefaultPosition;
    try {
      final pos = await LocationService.instance.currentPosition();
      target = LatLng(pos.latitude, pos.longitude);
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
    }
    if (!mounted) return;
    setState(() {
      _center = target;
      _camCenter = target;
      _mapReady = true;
    });
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

  /// On-screen radius, in logical pixels, that the 1 km query radius spans at
  /// the current zoom around [center]. Measures the pixel gap between [c0]
  /// (the already-fetched screen coordinate of [center]) and a point 1 km due
  /// east. Returns null if the widget unmounts.
  Future<double?> _groundRadiusPixels(
    GoogleMapController controller,
    LatLng center,
    ScreenCoordinate c0,
  ) async {
    final eastLon =
        center.longitude +
        _kNearbyRadiusMeters /
            (111320 * math.cos(center.latitude * math.pi / 180));
    final c1 = await controller.getScreenCoordinate(
      LatLng(center.latitude, eastLon),
    );
    if (!mounted) return null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (c1.x - c0.x).abs() / dpr;
  }

  /// Emits a single expanding ring at [target]'s screen position once the
  /// camera move has settled, growing to the on-screen size of the 1 km query
  /// radius. `getScreenCoordinate` returns physical pixels, so divide by the
  /// device ratio for logical layout coordinates.
  Future<void> _playPing(LatLng target) async {
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    final controller = _mapController;
    if (!mounted || controller == null) return;
    final coord = await controller.getScreenCoordinate(target);
    final radius = await _groundRadiusPixels(controller, target, coord);
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
          listenWhen: (p, c) => !listEquals(p.stations, c.stations),
          listener: (_, state) {
            _stations = state.stations;
            unawaited(_rebuildMarkers(state.stations));
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
