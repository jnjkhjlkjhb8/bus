import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/features/bike/view/bike_station_detail_view.dart';
import 'package:wheres_the_car/shared/map/map_color_scheme.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
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

  /// The one GPS fix requested for map init, shared between `initState` and
  /// `onMapCreated` (both race to move the camera as soon as it's ready) so
  /// they don't each fire their own `currentPosition()` call.
  Future<Position>? _initialPosition;

  @override
  void initState() {
    super.initState();
    _sheetController = SheetController();
    _initialPosition = LocationService.instance.currentPosition();
    unawaited(_moveToInitialLocation());
  }

  @override
  void dispose() {
    _controller?.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _moveToInitialLocation() async {
    final initial = _initialPosition;
    if (initial == null) return;
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
    try {
      final pos = await LocationService.instance.currentPosition();
      unawaited(
        _controller?.animateCamera(
          CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
        ),
      );
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
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
            child: GoogleMap(
              style: mapStyleOf(context),
              initialCameraPosition: const CameraPosition(
                target: _kDefaultPos,
                zoom: 15,
              ),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              onMapCreated: (c) {
                _controller = c;
                unawaited(_moveToInitialLocation());
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
                    onTap: () {
                      unawaited(HapticService.instance.lightTap());
                      context.pop();
                    },
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
