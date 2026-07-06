import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/firebase/remote_config.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/data/models/bus_models.dart';
import 'package:wheres_the_car/data/models/bus_route_detail.dart';
import 'package:wheres_the_car/data/models/eta_format.dart';
import 'package:wheres_the_car/data/models/timeline_stop.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_bloc.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_event.dart';
import 'package:wheres_the_car/features/bus/bloc/bus_route_state.dart';
import 'package:wheres_the_car/shared/map/marker_factory.dart';
import 'package:wheres_the_car/shared/map/wkt.dart';
import 'package:wheres_the_car/shared/motion/app_motion.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/app_card.dart';
import 'package:wheres_the_car/shared/widgets/app_sliding_segment.dart';
import 'package:wheres_the_car/shared/widgets/bookmark_button.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_car/shared/widgets/error_state_view.dart';
import 'package:wheres_the_car/shared/widgets/route_tab_bar.dart';

part '../widgets/bus_route_data_helpers.dart';
part '../widgets/bus_route_chrome_widgets.dart';
part '../widgets/bus_route_sheet_widgets.dart';
part '../widgets/bus_route_horizontal_timeline.dart';
part '../widgets/bus_route_stop_list_widgets.dart';
part '../widgets/bus_route_detail_widgets.dart';

const _kDefaultCamera = CameraPosition(
  target: LatLng(25.0416, 121.5501),
  zoom: 14,
);

class BusRouteScreen extends StatefulWidget {
  const BusRouteScreen({required this.subRouteUid, super.key});
  final String subRouteUid;

  @override
  State<BusRouteScreen> createState() => _BusRouteScreenState();
}

class _BusRouteScreenState extends State<BusRouteScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final SheetController _sheetController;
  final _scrollController = ScrollController();
  GoogleMapController? _mapController;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _routePts = [];
  String _mapSig = '';
  String? _geomSig;
  List<List<LatLng>> _geomLines = const [];
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _sheetController = SheetController();
  }

  BusStopEtaViewModel? _etaFor(BusRouteState s, BusStopModel st) =>
      s.etaMap['seq:${s.direction}:${st.sequence}'] ??
      s.etaMap['uid:${st.stopUid}'];

  Future<void> _syncMap(BusRouteState s) async {
    final route = s.route;
    if (route == null) return;
    final stops = s.direction == 0 ? route.stopsGo : route.stopsReturn;
    if (stops.isEmpty) return;

    final sig =
        '${route.subRouteUid}:${s.direction}:${stops.length}:'
        '${stops.map((st) => _markerEta(_etaFor(s, st))).join(',')}';
    if (sig == _mapSig) return;
    _mapSig = sig;

    final stopPts = [
      for (final st in stops)
        if (st.lat != 0 || st.lon != 0) LatLng(st.lat, st.lon),
    ];

    final geomSig = '${route.subRouteUid}:${s.direction}';
    if (geomSig != _geomSig) {
      _geomSig = geomSig;
      final geometry = s.direction == 0
          ? route.geometryGo
          : route.geometryReturn;
      var lines = parseWktLines(geometry);
      if (lines.isEmpty && stopPts.length >= 2) lines = [stopPts];
      _geomLines = lines;
    }

    final cs = Theme.of(context).colorScheme;
    final polylines = <Polyline>{
      for (var i = 0; i < _geomLines.length; i++)
        Polyline(
          polylineId: PolylineId('route_$i'),
          points: _geomLines[i],
          color: cs.onSurface,
          width: 4,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
    };

    final markers = <Marker>{};
    for (final st in stops) {
      if (st.lat == 0 && st.lon == 0) continue;
      final icon = await MapMarkers.etaStop(_markerEta(_etaFor(s, st)));
      markers.add(
        Marker(
          markerId: MarkerId(st.stopUid),
          position: LatLng(st.lat, st.lon),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(title: st.stopName),
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _markers = markers;
      _polylines = polylines;
      _routePts = stopPts;
    });
    _maybeFit();
  }

  void _maybeFit() {
    if (_fitted) return;
    final c = _mapController;
    if (c == null || _routePts.isEmpty) return;
    _fitted = true;
    unawaited(c.animateCamera(_fitUpdate()));
  }

  CameraUpdate _fitUpdate() => _routePts.length == 1
      ? CameraUpdate.newLatLngZoom(_routePts.first, 16)
      : CameraUpdate.newLatLngBounds(_boundsOf(_routePts), 60);

  void _recenterMap() {
    unawaited(HapticService.instance.lightTap());
    final controller = _mapController;
    if (controller != null) {
      unawaited(
        controller.animateCamera(
          _routePts.isEmpty
              ? CameraUpdate.newCameraPosition(_kDefaultCamera)
              : _fitUpdate(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _sheetController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final sheetAnimation = SheetOffsetDrivenAnimation(
      controller: _sheetController,
      initialValue: 0,
    );

    return BlocProvider(
      create: (_) => BusRouteBloc(subRouteUid: widget.subRouteUid),
      child: BlocConsumer<BusRouteBloc, BusRouteState>(
        buildWhen: (prev, curr) =>
            prev.route != curr.route ||
            prev.direction != curr.direction ||
            prev.etaMap != curr.etaMap ||
            prev.fare != curr.fare ||
            prev.bufferSequences != curr.bufferSequences ||
            prev.daily != curr.daily ||
            prev.reminders != curr.reminders ||
            prev.loading != curr.loading ||
            prev.error != curr.error,
        listener: (context, state) => _syncMap(state),
        builder: (context, state) {
          final stops = _stopsFor(state);
          final routeName = state.route?.routeName ?? widget.subRouteUid;
          final dirNames = [
            state.route?.headsignGo ?? '',
            state.route?.headsignReturn ?? '',
          ];
          final dirName = state.direction == 0 ? dirNames[0] : dirNames[1];

          return Scaffold(
            resizeToAvoidBottomInset: false,
            body: Stack(
              children: [
                Positioned.fill(
                  child: GoogleMap(
                    initialCameraPosition: _kDefaultCamera,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    markers: _markers,
                    polylines: _polylines,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _maybeFit();
                    },
                  ),
                ),

                _FloatingAppBar(
                  subRouteUid: widget.subRouteUid,
                  routeName: routeName,
                  dirName: dirName,
                  direction: state.direction,
                  onBookmarkTapped: HapticService.instance.mediumTap,
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
                    child: _RouteSheet(
                      tabController: _tabController,
                      sheetController: _sheetController,
                      scrollController: _scrollController,
                      stops: stops,
                      vehicles: const [],
                      direction: state.direction,
                      isLoading: state.loading,
                      onDirectionChanged: (dir) {
                        if (state.direction == dir) return;
                        unawaited(HapticService.instance.lightTap());
                        context.read<BusRouteBloc>().add(
                          BusRouteDirectionToggled(dir),
                        );
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                      },
                      sheetAnimation: sheetAnimation,
                      routeName: routeName,
                      dirNames: dirNames,
                      routeState: state,
                      reminders: state.reminders,
                      onReminderToggled: (uid) => context
                          .read<BusRouteBloc>()
                          .add(BusRouteReminderToggled(uid)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
