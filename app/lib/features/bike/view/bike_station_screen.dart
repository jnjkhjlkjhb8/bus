import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/firebase/crash_reporter.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_bloc.dart';
import 'package:wheres_the_car/features/bike/bloc/bike_station_state.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/availability_gauge.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/state_cards.dart';

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

  @override
  void initState() {
    super.initState();
    _sheetController = SheetController();
    unawaited(_moveToLocation());
  }

  @override
  void dispose() {
    _controller?.dispose();
    _sheetController.dispose();
    super.dispose();
  }

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
    return BlocProvider(
      create: (_) => BikeStationBloc(stationUid: widget.stationUid),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            Positioned.fill(
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: _kDefaultPos,
                  zoom: 15,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                onMapCreated: (c) {
                  _controller = c;
                  unawaited(_moveToLocation());
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
                    initialOffset: const SheetOffset.proportionalToViewport(
                      0.45,
                    ),
                    snapGrid: const SheetSnapGrid(
                      snaps: [
                        SheetOffset.proportionalToViewport(0.25),
                        SheetOffset.proportionalToViewport(0.45),
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
                    child: const BikeStationSheetContent(),
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

class BikeStationSheetContent extends StatelessWidget {
  const BikeStationSheetContent({
    this.onBack,
    super.key,
  });
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<BikeStationBloc, BikeStationState>(
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 56),
          children: [
            const SheetDragHandle(),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onBack != null)
                  Semantics(
                    label: '返回',
                    button: true,
                    child: GestureDetector(
                      onTap: () {
                        unawaited(HapticService.instance.lightTap());
                        onBack!();
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4, right: 8),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          size: 22,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.name, style: AppTextStyles.heading1),
                    Text(
                      'YouBike 2.0',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (state.loading) ...const [
              ShimmerRow(height: 120),
              SizedBox(height: 16),
              ShimmerRow(),
              ShimmerRow(),
            ] else ...[
              AvailabilityGauge(
                available: state.available,
                docks: state.returnDocks,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.pedal_bike_rounded,
                      size: 24,
                      color: cs.onSurface,
                    ),
                    const SizedBox(width: 6),
                    const Text('YouBike 2.0', style: AppTextStyles.bodySmall),
                    const Spacer(),
                    Text(
                      '${state.generalBikes}',
                      style: AppTextStyles.bodyRegular.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      ' 輛',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.electric_bike_rounded,
                      size: 24,
                      color: cs.onSurface,
                    ),
                    const SizedBox(width: 6),
                    const Text('YouBike 2.0E', style: AppTextStyles.bodySmall),
                    const Spacer(),
                    Text(
                      '${state.electricBikes}',
                      style: AppTextStyles.bodyRegular.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      ' 輛',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
