import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/data/models/eta_format.dart';
import 'package:wheres_the_car/data/models/favorite.dart';
import 'package:wheres_the_car/data/repositories/bus_stop_eta_repository.dart';
import 'package:wheres_the_car/features/alerts/view/alert_banner.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_bloc.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_event.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_stop_state.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_event.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_state.dart';
import 'package:wheres_the_car/shared/map/marker_factory.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/motion/stagger.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/eta_list_tile.dart';

part '../widgets/bus_stop_sheet_widgets.dart';
part '../widgets/bus_stop_skeleton_widgets.dart';
part '../widgets/bus_stop_eta_tile_widgets.dart';

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
  BitmapDescriptor? _busIcon;

  @override
  void initState() {
    super.initState();
    _sheetController = SheetController();
    unawaited(_loadMarkerIcon());
    unawaited(_moveToCurrentLocation());
  }

  Future<void> _loadMarkerIcon() async {
    final icon = await MapMarkers.svgAsset('assets/marker/Bus.svg', size: 32);
    if (mounted) setState(() => _busIcon = icon);
  }

  /// Animates the map to [uid]'s member stop when a filter chip is picked.
  void _focusStation(BusStopState state, String? uid) {
    if (uid == null) return;
    final member = state.members.where((m) => m.stationUid == uid).firstOrNull;
    final controller = _controller;
    if (member == null || controller == null) return;
    unawaited(
      controller.animateCamera(
        CameraUpdate.newLatLng(LatLng(member.lat, member.lon)),
      ),
    );
  }

  Favorite get _favorite => Favorite(
    type: FavoriteType.busStop,
    // Persist the station group_uid (falling back to the name when this stop
    // was opened without one) plus city, so reopening loads live ETA.
    refId: (widget.stopId?.isNotEmpty ?? false)
        ? widget.stopId!
        : widget.stopName,
    title: widget.stopName,
    subtitle: widget.city ?? '',
  );

  void _toggleBookmark() {
    unawaited(HapticService.instance.lightTap());
    final wasSaved = context.read<FavoritesBloc>().state.contains(_favorite.id);
    final added = !wasSaved;
    context.read<FavoritesBloc>().add(FavoriteToggled(_favorite));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added ? '已加入收藏' : '已取消收藏'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '復原',
          onPressed: _toggleBookmark,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _moveToCurrentLocation() async {
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
    }
  }

  void _recenterMap() {
    unawaited(HapticService.instance.lightTap());
    unawaited(_moveToCurrentLocation());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocProvider(
      create: (_) => BusStopBloc(
        stopId: widget.stopId,
        city: widget.city,
      ),
      child: BlocListener<BusStopBloc, BusStopState>(
        listenWhen: (prev, next) =>
            prev.selectedStationUid != next.selectedStationUid,
        listener: (context, state) =>
            _focusStation(state, state.selectedStationUid),
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
                      onMapCreated: (c) {
                        _controller = c;
                        if (state.members.isEmpty) {
                          unawaited(_moveToCurrentLocation());
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
                          const Spacer(),
                          BlocBuilder<FavoritesBloc, FavoritesState>(
                            buildWhen: (prev, next) =>
                                prev.contains(_favorite.id) !=
                                next.contains(_favorite.id),
                            builder: (context, state) {
                              final bookmarked = state.contains(_favorite.id);
                              return AppBarCircleButton(
                                onTap: _toggleBookmark,
                                semanticLabel: bookmarked ? '取消收藏' : '收藏',
                                child: Icon(
                                  bookmarked
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                  size: 20,
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
                      initialOffset: const SheetOffset.proportionalToViewport(
                        0.5,
                      ),
                      snapGrid: const SheetSnapGrid(
                        snaps: [
                          SheetOffset.proportionalToViewport(0.25),
                          SheetOffset.proportionalToViewport(0.5),
                          SheetOffset.proportionalToViewport(1),
                        ],
                      ),
                      scrollConfiguration: const SheetScrollConfiguration(),
                      decoration: MaterialSheetDecoration(
                        size: SheetSize.stretch,
                        color: cs.surfaceContainerLow,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppTheme.radiusBottomSheet),
                        ),
                        clipBehavior: Clip.antiAlias,
                      ),
                      child: _StopSheet(stopName: widget.stopName),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
