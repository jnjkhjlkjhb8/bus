import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
import 'package:wheres_the_car/data/repositories/settings_repository.dart';
import 'package:wheres_the_car/features/alerts/view/alert_banner.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_bloc.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_state.dart';
import 'package:wheres_the_car/features/bus/view/bus_stop_detail_view.dart';
import 'package:wheres_the_car/features/bus/widgets/stop_board_toggle.dart';
import 'package:wheres_the_car/features/live_activity/bloc/stop_board_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/stop_board_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/stop_board_state.dart';
import 'package:wheres_the_car/shared/map/map_color_scheme.dart';
import 'package:wheres_the_car/shared/map/marker_factory.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_spinner.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';

const _kDefaultPos = LatLng(25.0330, 121.5654);

class BusStopScreen extends StatefulWidget {
  const BusStopScreen({
    required this.stopName,
    this.stopId,
    this.city,
    super.key,
  });
  final String stopName;
  final String? stopId;
  final String? city;

  @override
  State<BusStopScreen> createState() => _BusStopScreenState();
}

class _BusStopScreenState extends State<BusStopScreen> {
  GoogleMapController? _controller;
  late final SheetController _sheetController;
  late final BusStopBloc _bloc;
  BitmapDescriptor? _busIcon;
  bool _locating = false;

  /// The one GPS fix requested for map init, shared between `initState` and
  /// `onMapCreated` (both race to move the camera as soon as it's ready) so
  /// they don't each fire their own `currentPosition()` call.
  Future<Position>? _initialPosition;

  @override
  void initState() {
    super.initState();
    _sheetController = SheetController();
    _bloc = BusStopBloc(stopId: widget.stopId, city: widget.city);
    unawaited(_loadMarkerIcon());
    _initialPosition = LocationService.instance.currentPosition();
    unawaited(_moveToInitialLocation());
  }

  Future<void> _loadMarkerIcon() async {
    final icon = await MapMarkers.svgAsset('assets/marker/Bus.svg', size: 32);
    if (mounted) setState(() => _busIcon = icon);
  }

  /// Animates the map to [pos], the coordinates of the selected member stop.
  void _focusStation(LatLng pos) {
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.animateCamera(CameraUpdate.newLatLng(pos)));
  }

  @override
  void dispose() {
    _controller?.dispose();
    _sheetController.dispose();
    unawaited(_bloc.close());
    super.dispose();
  }

  Future<void> _moveToInitialLocation() async {
    final initial = _initialPosition;
    if (initial == null) return;
    try {
      final pos = await initial;
      final controller = _controller;
      if (controller != null) {
        unawaited(
          controller.animateCamera(
            CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
          ),
        );
      }
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
    }
  }

  /// User-triggered recenter: always requests a fresh fix, unlike the shared
  /// one-shot [_initialPosition] used during map init.
  Future<void> _moveToCurrentLocation() async {
    if (mounted) setState(() => _locating = true);
    try {
      final pos = await LocationService.instance.currentPosition();
      final controller = _controller;
      if (controller != null) {
        unawaited(
          controller.animateCamera(
            CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
          ),
        );
      }
    } on Object catch (e, s) {
      CrashReporter.record(e, s);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _recenterMap() {
    unawaited(HapticService.instance.lightTap());
    unawaited(_moveToCurrentLocation());
  }

  /// Toggles the 站牌看板 Live Activity for this stop. [isActive] reflects
  /// whether the shared [StopBoardBloc] is currently broadcasting *this*
  /// stop (matched by name — the bloc is a single app-wide instance shared
  /// with the journey/track card, so any other active board reads as off
  /// here and a tap takes over as this stop's board).
  void _toggleBoard(bool isActive) {
    unawaited(HapticService.instance.lightTap());
    final bloc = context.read<StopBoardBloc>();
    if (isActive) {
      bloc.add(const StopBoardStopped());
    } else {
      bloc.add(
        StopBoardStarted(
          widget.city ?? '',
          widget.stopId ?? '',
          widget.stopName,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Single BusStopBloc instance, shared by the map (marker layer below) and
    // the BusStopDetailView sheet — see class doc on BusStopDetailView.bloc.
    return BlocProvider<BusStopBloc>.value(
      value: _bloc,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(
              child: BlocBuilder<BusStopBloc, BusStopState>(
                buildWhen: (prev, next) => prev.members != next.members,
                builder: (context, state) {
                  final target = state.members.isEmpty
                      ? _kDefaultPos
                      : LatLng(
                          state.members.first.lat,
                          state.members.first.lon,
                        );
                  return GoogleMap(
                    style: mapStyleOf(context),
                    initialCameraPosition: CameraPosition(
                      target: target,
                      zoom: 16,
                    ),
                    markers: {
                      for (final m in state.members)
                        Marker(
                          markerId: MarkerId(m.stationUid),
                          position: LatLng(m.lat, m.lon),
                          icon: _busIcon ?? BitmapDescriptor.defaultMarker,
                          anchor: const Offset(0.5, 0.5),
                          infoWindow: InfoWindow(title: m.stationName),
                        ),
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    // Map shares a Stack with the draggable sheet; without an
                    // eager recognizer the map loses the gesture arena, so
                    // pan/pinch leak to the sheet instead of moving the map.
                    gestureRecognizers: const {
                      Factory<OneSequenceGestureRecognizer>(
                        EagerGestureRecognizer.new,
                      ),
                    },
                    onMapCreated: (c) {
                      _controller = c;
                      if (state.members.isEmpty) {
                        unawaited(_moveToInitialLocation());
                      }
                    },
                  );
                },
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
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
                        const Spacer(),
                        if (SettingsRepository.instance.liveActivityEnabled &&
                            (widget.stopId?.isNotEmpty ?? false))
                          BlocBuilder<StopBoardBloc, StopBoardState>(
                            builder: (context, state) {
                              final isActive = isStopBoardActive(
                                state,
                                widget.stopName,
                              );
                              return AppBarCircleButton(
                                onTap: () => _toggleBoard(isActive),
                                semanticLabel: isActive
                                    ? '關閉站牌即時動態'
                                    : '開啟站牌即時動態',
                                child: Icon(
                                  isActive
                                      ? Icons.wifi_tethering_rounded
                                      : Icons.wifi_tethering_off_rounded,
                                  size: 18,
                                  color: cs.onSurface,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  const MapAlertStrip(),
                ],
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
                    child: BusStopDetailView(
                      stopName: widget.stopName,
                      stopId: widget.stopId,
                      city: widget.city,
                      bloc: _bloc,
                      onFocusStation: _focusStation,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
