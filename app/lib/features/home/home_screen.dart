import 'dart:async';
import 'dart:math' as math;

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
import 'package:wheres_the_car/shared/map/marker_factory.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
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
  late final TabController _tabController;
  LatLng _center = _kDefaultPosition;
  LatLng _camCenter = _kDefaultPosition;
  double _zoom = 15;
  _MarkerStyle _markerStyleCache = _MarkerStyle.largeDot;
  Set<Marker> _markers = {};
  int _markerRevision = 0;
  Timer? _idleDebounce;
  bool _mapReady = false;
  bool _tabApplied = false;

  Future<void> _rebuildMarkers(List<NearStationViewModel> stations) async {
    final revision = ++_markerRevision;
    final style = _markerStyle(_zoom);
    final markers = await Future.wait(
      stations.take(_kMapMarkerLimit).map((s) async {
        final icon = await _markerIcon(s, style);
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

  Future<int> _visibleRadiusMeters() async {
    final controller = _mapController;
    if (controller == null) return _kFallbackRadiusMeters;
    final bounds = await controller.getVisibleRegion();
    final northEast = bounds.northeast;
    final southWest = bounds.southwest;
    final northWest = LatLng(northEast.latitude, southWest.longitude);
    final southEast = LatLng(southWest.latitude, northEast.longitude);
    final radius = [
      northEast,
      southWest,
      northWest,
      southEast,
    ].map((p) => _distanceMeters(_camCenter, p)).reduce(math.max);
    return radius.ceil();
  }

  Future<void> _requestNearbyForViewport(NearbyBloc bloc) async {
    final radius = await _visibleRadiusMeters();
    if (!mounted) return;
    bloc.add(
      NearbyRequested(
        lat: _camCenter.latitude,
        lon: _camCenter.longitude,
        radius: radius,
      ),
    );
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
    try {
      final pos = await LocationService.instance.currentPosition();
      final target = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _center = target;
        _camCenter = target;
      });
      final controller = _mapController;
      if (controller != null) {
        unawaited(controller.animateCamera(CameraUpdate.newLatLng(target)));
      }
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
    }
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
          listenWhen: (p, c) => p.stations != c.stations,
          listener: (_, state) => unawaited(_rebuildMarkers(state.stations)),
          child: _buildScaffold(context, cs),
        ),
      ),
    );
  }
}
