import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_car/app/theme/app_shadows.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/haptics/haptic_service.dart';
import 'package:wheres_the_car/core/live_activity/pip_mode.dart';
import 'package:wheres_the_car/core/storage/hive_store.dart';
import 'package:wheres_the_car/data/models/plan_models.dart';
import 'package:wheres_the_car/features/go/bloc/plan_bloc.dart';
import 'package:wheres_the_car/features/go/bloc/plan_event.dart';
import 'package:wheres_the_car/features/go/bloc/plan_state.dart';
import 'package:wheres_the_car/features/go/model/planned_place.dart';
import 'package:wheres_the_car/features/go/view/place_search_sheet.dart';
import 'package:wheres_the_car/features/go/widgets/route_option_card.dart';
import 'package:wheres_the_car/features/go/widgets/transit_visuals.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_event.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_state.dart';
import 'package:wheres_the_car/features/live_activity/model/journey_models.dart';
import 'package:wheres_the_car/shared/motion/pressable.dart';
import 'package:wheres_the_car/shared/widgets/app_bars.dart';
import 'package:wheres_the_car/shared/widgets/bottom_sheet_shell.dart';

part '../widgets/go_planner_widgets.dart';
part '../widgets/go_navigation_widgets.dart';

const _kDefaultPos = LatLng(25.0416, 121.5438);

class GoScreen extends StatefulWidget {
  const GoScreen({super.key});

  @override
  State<GoScreen> createState() => _GoScreenState();
}

class _GoScreenState extends State<GoScreen> {
  GoogleMapController? _map;
  late final SheetController _sheet;
  PlannedPlace? _origin;
  PlannedPlace? _dest;

  @override
  void initState() {
    super.initState();
    _sheet = SheetController();
    if (context.read<PlanBloc>().state.activeLegIndex == null) {
      unawaited(_initOrigin());
    }
  }

  @override
  void dispose() {
    _map?.dispose();
    _sheet.dispose();
    super.dispose();
  }

  Future<void> _initOrigin() async {
    try {
      final place = await resolveCurrentPlace();
      if (!mounted) return;
      setState(() => _origin = place);
    } on Object catch (_) {}
  }

  Future<void> _editField({required bool origin}) async {
    unawaited(HapticService.instance.lightTap());
    final picked = await showPlaceSearchSheet(
      context,
      fieldLabel: origin ? '選擇出發地' : '選擇目的地',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (origin) {
        _origin = picked;
      } else {
        _dest = picked;
      }
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
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    context.read<PlanBloc>().add(
      PlanSearchRequested(
        fromLat: from.latLng.latitude,
        fromLon: from.latLng.longitude,
        toLat: to.latLng.latitude,
        toLon: to.latLng.longitude,
        date: '${now.year}-${two(now.month)}-${two(now.day)}',
        time: '${two(now.hour)}:${two(now.minute)}',
      ),
    );
  }

  void _retry() {
    unawaited(HapticService.instance.lightTap());
    _maybePlan();
  }

  void _selectRoute(PlanRoute route) {
    unawaited(HapticService.instance.heavyTap());
    final bloc = context.read<PlanBloc>();
    final routes = bloc.state.result?.routes ?? const <PlanRoute>[];
    bloc
      ..add(RouteSelected(index: routes.indexOf(route)))
      ..add(const NavigationStarted());
    final legs = JourneyLeg.legsFromRoute(route);
    if (legs.isNotEmpty && HiveStore.liveActivityEnabled) {
      context.read<JourneySessionBloc>().add(JourneyStarted(legs: legs));
      unawaited(PipMode.instance.setNavigating(true));
    }
    final start = _firstPoint(route);
    final map = _map;
    if (start != null && map != null) {
      unawaited(
        map.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: start, zoom: 15.5, bearing: 30, tilt: 45),
          ),
        ),
      );
    }
  }

  void _advance(PlanRoute route, int activeLeg) {
    unawaited(HapticService.instance.lightTap());
    final bloc = context.read<PlanBloc>();
    if (activeLeg >= route.sections.length - 1) {
      bloc.add(const NavigationEnded());
      _stopJourneySession();
      _resetCamera();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已抵達目的地'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    bloc.add(StopArrived(legIndex: activeLeg + 1, stopIndex: 0));
    final next = _firstPoint(route, leg: activeLeg + 1);
    final map = _map;
    if (next != null && map != null) {
      unawaited(map.animateCamera(CameraUpdate.newLatLng(next)));
    }
  }

  void _endNav() {
    unawaited(HapticService.instance.lightTap());
    context.read<PlanBloc>().add(const NavigationEnded());
    _stopJourneySession();
    _resetCamera();
  }

  /// User-initiated end of navigation: tear down the journey session and the
  /// picture-in-picture navigating flag. Safe to call when no session is
  /// active (JourneyCancelled is a no-op from the idle phase).
  void _stopJourneySession() {
    context.read<JourneySessionBloc>().add(const JourneyCancelled());
    unawaited(PipMode.instance.setNavigating(false));
  }

  void _resetCamera() {
    final map = _map;
    if (map == null) return;
    unawaited(
      map.animateCamera(
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

  LatLng? _firstPoint(PlanRoute route, {int leg = 0}) =>
      _latLngOrNull(route.firstPoint(leg: leg));

  void _fitTo(PlanRoute route) {
    final points = _routePoints(route);
    final map = _map;
    if (points.length < 2 || map == null) return;
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
      map.animateCamera(
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

  Set<Polyline> _polylines(PlanRoute route, {int? activeLeg}) {
    final cs = Theme.of(context).colorScheme;
    final lines = <Polyline>{};
    for (final (i, s) in route.sections.indexed) {
      final pts = <LatLng>[];
      void add(PlanPoint point) {
        if (point.lat != 0 || point.lng != 0) {
          pts.add(LatLng(point.lat, point.lng));
        }
      }

      add(s.departure.location);
      for (final stop in s.intermediateStops) {
        add(stop.location);
      }
      add(s.arrival.location);
      if (pts.length < 2) continue;
      final base = isWalk(s) ? cs.outline : transitColor(s.transport, cs);
      final dim = activeLeg != null && i < activeLeg;
      lines.add(
        Polyline(
          polylineId: PolylineId('leg_$i'),
          points: pts,
          width: isWalk(s) ? 4 : 6,
          color: dim ? base.withValues(alpha: 0.3) : base,
          patterns: isWalk(s)
              ? [PatternItem.dot, PatternItem.gap(8)]
              : const [],
        ),
      );
    }
    return lines;
  }

  Set<Marker> _markers(PlanRoute route) {
    final pts = _routePoints(route);
    if (pts.length < 2) return const {};
    return {
      Marker(
        markerId: const MarkerId('origin'),
        position: pts.first,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
      Marker(
        markerId: const MarkerId('dest'),
        position: pts.last,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    // The session can reach `done` on its own (last leg alighted, or the 8h
    // ActivityKit cap). Mirror that back into PlanBloc + PiP so the panel
    // reverts even when the user didn't tap 結束導航.
    return BlocListener<JourneySessionBloc, JourneySessionState>(
      listenWhen: (p, c) => p.phase != c.phase && c.phase == JourneyPhase.done,
      listener: (context, _) {
        unawaited(PipMode.instance.setNavigating(false));
        final plan = context.read<PlanBloc>();
        if (plan.state.activeLegIndex != null) {
          plan.add(const NavigationEnded());
          _resetCamera();
        }
      },
      child: _buildPlanner(),
    );
  }

  Widget _buildPlanner() {
    return BlocConsumer<PlanBloc, PlanState>(
      listenWhen: (p, c) =>
          p.status != c.status && c.status == PlanStatus.success,
      listener: (context, state) {
        final route = _activeRoute(state);
        if (route != null && state.activeLegIndex == null) _fitTo(route);
      },
      builder: (context, state) {
        final navigating = state.activeLegIndex != null;
        final route = _activeRoute(state);
        return PopScope(
          canPop: !navigating,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && navigating) _endNav();
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Stack(
              children: [
                Positioned.fill(
                  child: GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: _kDefaultPos,
                      zoom: 14,
                    ),
                    onMapCreated: (c) {
                      _map = c;
                      if (route != null && !navigating) _fitTo(route);
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    polylines: route == null
                        ? const {}
                        : _polylines(
                            route,
                            activeLeg: navigating ? state.activeLegIndex : null,
                          ),
                    markers: route == null ? const {} : _markers(route),
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
                            )
                          : _PlannerHeader(
                              origin: _origin,
                              dest: _dest,
                              onBack: () => context.pop(),
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
                    route: route,
                    activeLeg: state.activeLegIndex!,
                    onAdvance: () => _advance(route, state.activeLegIndex!),
                    onEnd: _endNav,
                  )
                else
                  _PlannerSheet(
                    controller: _sheet,
                    state: state,
                    hasDestination: _dest != null,
                    onSelect: _selectRoute,
                    onRetry: _retry,
                    onPickDestination: () => _editField(origin: false),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  PlanRoute? _activeRoute(PlanState state) {
    final routes = state.result?.routes;
    if (routes == null || routes.isEmpty) return null;
    final i = state.selectedRouteIndex ?? 0;
    return i >= 0 && i < routes.length ? routes[i] : routes.first;
  }
}
