import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_bloc.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_state.dart';
import 'package:wheres_the_car/features/bike/view/bike_station_detail_view.dart';
import 'package:wheres_the_car/shared/map/map_color_scheme.dart';
import 'package:wheres_the_car/shared/map/marker_factory.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_spinner.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';

const _kDefaultPos = LatLng(25.0330, 121.5654);

class BikeStationScreen extends StatefulWidget {
  const BikeStationScreen({required this.stationUid, super.key});
  final String stationUid;

  @override
  State<BikeStationScreen> createState() => _BikeStationScreenState();
}

class _BikeStationScreenState extends State<BikeStationScreen> {
  GoogleMapController? _controller;
  late final SheetController _sheetController;

  // Own bloc instance, separate from BikeStationDetailView's: it exists only
  // to read the station's static lat/lon for the marker/camera target, kept
  // out of the shared sheet bloc so this screen doesn't have to reach into
  // the detail view's widget tree to read it.
  late final BikeStationBloc _bloc;
  BitmapDescriptor? _bikeIcon;
  bool _locating = false;

  /// The one GPS fix requested for map init, shared between `initState` and
  /// `onMapCreated` (both race to move the camera as soon as it's ready) so
  /// they don't each fire their own `currentPosition()` call.
  Future<Position>? _initialPosition;

  @override
  void initState() {
    super.initState();
    _sheetController = SheetController();
    _bloc = BikeStationBloc(stationUid: widget.stationUid);
    unawaited(_loadMarkerIcon());
    _initialPosition = LocationService.instance.currentPosition();
    unawaited(_moveToInitialLocation());
  }

  Future<void> _loadMarkerIcon() async {
    final icon = await MapMarkers.svgAsset('assets/marker/bike.svg', size: 32);
    if (mounted) setState(() => _bikeIcon = icon);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _sheetController.dispose();
    unawaited(_bloc.close());
    super.dispose();
  }

  /// Falls back to a GPS pan only until the station's own coordinates are
  /// known (see the `BlocBuilder` in [build]); once they land, the camera
  /// target comes from the station, not the user's location.
  Future<void> _moveToInitialLocation() async {
    final initial = _initialPosition;
    if (initial == null) return;
    if (_bloc.state.lat != 0 || _bloc.state.lon != 0) return;
    try {
      final pos = await initial;
      unawaited(
        _controller?.animateCamera(
          CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
        ),
      );
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
    }
  }

  /// User-triggered recenter: always requests a fresh fix, unlike the shared
  /// one-shot [_initialPosition] used during map init.
  Future<void> _moveToLocation() async {
    if (mounted) setState(() => _locating = true);
    try {
      final pos = await LocationService.instance.currentPosition();
      unawaited(
        _controller?.animateCamera(
          CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
        ),
      );
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _recenterMap() {
    unawaited(HapticService.instance.lightTap());
    unawaited(_moveToLocation());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: BlocConsumer<BikeStationBloc, BikeStationState>(
              bloc: _bloc,
              listenWhen: (prev, next) =>
                  (prev.lat == 0 && prev.lon == 0) &&
                  (next.lat != 0 || next.lon != 0),
              // The static fetch can land after the map is already up (its
              // initial camera target was only the GPS fallback); once the
              // station's coordinates arrive, pan to them explicitly since
              // `initialCameraPosition` never re-applies post-creation.
              listener: (context, state) {
                unawaited(
                  _controller?.animateCamera(
                    CameraUpdate.newLatLng(LatLng(state.lat, state.lon)),
                  ),
                );
              },
              buildWhen: (prev, next) =>
                  prev.lat != next.lat || prev.lon != next.lon,
              builder: (context, state) {
                final hasStation = state.lat != 0 || state.lon != 0;
                final target = hasStation
                    ? LatLng(state.lat, state.lon)
                    : _kDefaultPos;
                return GoogleMap(
                  style: mapStyleOf(context),
                  initialCameraPosition: CameraPosition(
                    target: target,
                    zoom: 16,
                  ),
                  markers: {
                    if (hasStation)
                      Marker(
                        markerId: MarkerId(widget.stationUid),
                        position: target,
                        icon: _bikeIcon ?? BitmapDescriptor.defaultMarker,
                        anchor: const Offset(0.5, 0.5),
                        infoWindow: InfoWindow(title: state.name),
                      ),
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  onMapCreated: (c) {
                    _controller = c;
                    if (!hasStation) {
                      unawaited(_moveToInitialLocation());
                    }
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Row(
                children: [
                  AppBarCircleButton(
                    onTap: context.pop,
                    semanticLabel: '返回',
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
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
                  child: AnimatedSwitcher(
                    duration: AppMotion.short,
                    child: _locating
                        ? const AppSpinner(
                            key: ValueKey('locating'),
                            size: 20,
                          )
                        : Icon(
                            Icons.gps_fixed_rounded,
                            key: const ValueKey('idle'),
                            size: 20,
                            color: cs.onSurface,
                          ),
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
              child: SheetExitGestureDetector(
                onExit: () => context.pop(),
                child: Sheet(
                  controller: _sheetController,
                  initialOffset: AppSheetSnap.half,
                  snapGrid: AppSheetSnap.grid,
                  scrollConfiguration: const SheetScrollConfiguration(),
                  decoration: MaterialSheetDecoration(
                    size: SheetSize.stretch,
                    color: cs.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppTheme.radiusBottomSheet),
                    ),
                    clipBehavior: Clip.antiAlias,
                  ),
                  child: BikeStationDetailView(stationUid: widget.stationUid),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
