import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wheres_the_bus/app/theme/app_shadows.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/core/haptics/alight_haptics.dart';
import 'package:wheres_the_bus/data/decoders/fare_decoder.dart';
import 'package:wheres_the_bus/data/models/bus_models.dart';
import 'package:wheres_the_bus/data/models/bus_route_detail.dart';
import 'package:wheres_the_bus/data/models/fare_type.dart';
import 'package:wheres_the_bus/data/models/timeline_stop.dart';
import 'package:wheres_the_bus/data/tracking/journey_session_bloc.dart';
import 'package:wheres_the_bus/data/tracking/journey_session_event.dart';
import 'package:wheres_the_bus/data/tracking/tracking_session.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_route_bloc.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_route_event.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_route_state.dart';
import 'package:wheres_the_bus/features/bus/map/bus_route_overlay.dart';
import 'package:wheres_the_bus/features/bus/widgets/bus_timeline_stops.dart';
import 'package:wheres_the_bus/features/bus/widgets/bus_timetable_day.dart';
import 'package:wheres_the_bus/features/bus/widgets/pinned_bus.dart';
import 'package:wheres_the_bus/features/bus/widgets/track_trigger_stop.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/map/map_color_scheme.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';
import 'package:wheres_the_bus/shared/widgets/alight_track/alight_confirm_bar.dart';
import 'package:wheres_the_bus/shared/widgets/alight_track/alight_pick_capsule.dart';
import 'package:wheres_the_bus/shared/widgets/alight_track/alight_swipe_row.dart';
import 'package:wheres_the_bus/shared/widgets/app_accordion.dart';
import 'package:wheres_the_bus/shared/widgets/app_bars.dart';
import 'package:wheres_the_bus/shared/widgets/app_card.dart';
import 'package:wheres_the_bus/shared/widgets/app_input.dart';
import 'package:wheres_the_bus/shared/widgets/app_sliding_segment.dart';
import 'package:wheres_the_bus/shared/widgets/bookmark_button.dart';
import 'package:wheres_the_bus/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_bus/shared/widgets/divider_line.dart';
import 'package:wheres_the_bus/shared/widgets/error_state_view.dart';
import 'package:wheres_the_bus/shared/widgets/fare_preference.dart';
import 'package:wheres_the_bus/shared/widgets/route_tab_bar.dart';
import 'package:wheres_the_bus/shared/widgets/transit_timeline.dart';

part '../widgets/bus_route_chrome_widgets.dart';
part '../widgets/bus_route_data_helpers.dart';
part '../widgets/bus_route_detail_widgets.dart';
part '../widgets/bus_route_fare_widgets.dart';
part '../widgets/bus_route_horizontal_timeline.dart';
part '../widgets/bus_route_sheet_widgets.dart';
part '../widgets/bus_route_stop_list_widgets.dart';
part '../widgets/bus_route_timetable_widgets.dart';

const _kDefaultCamera = CameraPosition(
  target: LatLng(25.0416, 121.5501),
  zoom: 14,
);

// Route sheet drops the shared grid's half detent: at half the timeline is
// already fully visible and the tab content below it is still cut off, so the
// stop is a stall on the way to full rather than a height anyone rests at.
const _kRouteSnapGrid = SheetSnapGrid(
  snaps: [AppSheetSnap.peek, AppSheetSnap.full],
  minFlingSpeed: AppSheetSnap.flingSpeed,
);

class BusRouteScreen extends StatefulWidget {
  const BusRouteScreen({required this.subRouteUid, super.key});
  final String subRouteUid;

  @override
  State<BusRouteScreen> createState() => _BusRouteScreenState();
}

class _BusRouteScreenState extends State<BusRouteScreen>
    with TickerProviderStateMixin {
  // Owned here (not created inside build's BlocProvider) so State methods can
  // reach it directly. A BlocProvider in build() sits below this State element,
  // so a context.read from here would fail the ancestor lookup.
  late final BusRouteBloc _bloc;
  late final TabController _tabController;
  late final SheetController _sheetController;
  final _scrollController = ScrollController();
  // The horizontal timeline (collapsed sheet) is a separate scrollable from the
  // vertical stop list, so a marker tap must drive its own controller too.
  final _timelineController = ScrollController();
  GoogleMapController? _mapController;

  /// Stop uids of the current direction, in list order — lets a marker tap map
  /// a stopUid to its row index for scroll-to.
  List<String> _stopUidsInOrder = const [];

  /// The stop briefly highlighted after its marker was tapped; cleared by
  /// [_flashTimer] after a few seconds.
  String? _flashStopUid;
  Timer? _flashTimer;

  /// Drives the visible bubbles' GPS-freshness clock. Alive only while at least
  /// one bubble is on screen — see [_syncBubbleTicker].
  Timer? _bubbleTicker;

  /// The one stop showing its name as a capsule on the map. Outlives
  /// [_flashStopUid]'s few seconds — a name you are still reading shouldn't
  /// expire — and is cleared by tapping the marker again or the bare map.
  String? _selectedStopUid;

  // "Pin a bus, pick your alight stop" state. [_pinnedPlate] is the selected
  // vehicle (null = none); [_pickingStop] is true from selection until a stop
  // is chosen (完成) or skipped (略過); [_pinnedNextStopIndex] snapshots the
  // bus's next-stop index at pin time so the passed/downstream split stays
  // stable while picking; [_targetStopUid] is the chosen alight stop;
  // [_leadStops] is 提前站數 (0–3, default 0 = no early warning).
  String? _pinnedPlate;
  bool _pickingStop = false;
  int? _pinnedNextStopIndex;
  String? _targetStopUid;
  int _leadStops = 0;

  final ValueNotifier<BusMapLayer> _mapLayer = ValueNotifier(
    (markers: <Marker>{}, polylines: <Polyline>{}),
  );

  /// Owns everything pinned to a coordinate: the frame signature, the marker
  /// and geometry caches, the in-flight glides, and the supersede rule.
  late final BusRouteOverlay _overlay = BusRouteOverlay(
    onStopTap: _flashStop,
    onVehicleTap: _togglePin,
  );
  bool _fitted = false;
  // didChangeDependencies fires for reasons other than a brightness flip (text
  // scale, locale, ...); this tracks the last-seen value so only an actual
  // light/dark change forces a resync.
  Brightness? _lastBrightness;
  // Sampled at 12pt, the size the marker bitmaps are scaled from.
  double? _lastTextScale;

  // Vehicle markers slide between live frames; stops/polylines stay static, so
  // a glide tick only repaints the bus + bubble layer on top of them.
  late final AnimationController _busGlide;
  late final CurvedAnimation _busGlideCurve;

  @override
  void initState() {
    super.initState();
    _bloc = BusRouteBloc(subRouteUid: widget.subRouteUid);
    _tabController = TabController(length: 2, vsync: this);
    _sheetController = SheetController();
    // 800ms reads as a bus catching up to its reported spot; a UI-chrome-speed
    // glide (~200ms) would look like a twitch every 30 s.
    _busGlide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addListener(_paintVehicles);
    _busGlideCurve = CurvedAnimation(
      parent: _busGlide,
      curve: AppMotion.easeInOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // _syncMap only runs from the bloc listener, so a theme flip or a text-size
    // change with no new bloc state would otherwise leave every marker bitmap
    // (and the route Polyline color) painted for the brightness and text scale
    // that were active when they were last built. Forcing a resync here is what
    // makes the map repaint for a light/dark switch or a Dynamic Type change at
    // all. Both are tracked rather than resyncing on every dependency change,
    // because that also fires for keyboard insets and locale.
    final brightness = Theme.of(context).colorScheme.brightness;
    final textScale = MediaQuery.textScalerOf(context).scale(12);
    if ((_lastBrightness != null && _lastBrightness != brightness) ||
        (_lastTextScale != null && _lastTextScale != textScale)) {
      _overlay.invalidate();
      unawaited(_syncMap(_bloc.state));
    }
    _lastBrightness = brightness;
    _lastTextScale = textScale;
  }

  /// Asks the overlay for a new frame and commits it.
  ///
  /// Everything expensive — the signature short-circuit, geometry parsing,
  /// marker and bubble rasterising, glide continuity, and the supersede rule —
  /// lives behind [BusRouteOverlay.resolve]. A null frame means "nothing to
  /// show that isn't already on screen", so this leaves the map alone.
  Future<void> _syncMap(BusRouteState s) async {
    // Read before the first await: every caller reaches this from
    // didChangeDependencies or later, so the locale and theme are readable
    // here, and holding them avoids touching `context` across an async gap.
    final i18n = AppI18n.of(context);
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final frame = await _overlay.resolve(
      state: s,
      i18n: i18n,
      colors: colors,
      glideProgress: _busGlideCurve.value,
      now: DateTime.now(),
      selectedStopUid: _selectedStopUid,
      pinnedPlate: _pinnedPlate,
      trackedPlate: context.read<JourneySessionBloc>().state.plate,
      pickingStop: _pickingStop,
    );
    if (frame == null || !mounted) return;

    _stopUidsInOrder = [
      for (final st in _currentStops(s)) st.stopUid,
    ];
    _syncBubbleTicker(wanted: frame.showsAnyBubble);

    if (reduceMotion) {
      // Reduce-motion: snap to the reported position, no glide.
      _busGlide.value = 1;
      _paintVehicles();
    } else {
      // Glide from the current position to the new frame. A frame that didn't
      // move a bus just animates target→target (static); a frame landing
      // mid-glide retargets smoothly because `from` is the live position.
      unawaited(_busGlide.forward(from: 0));
    }
    _maybeFit();
  }

  /// Runs the once-a-second bubble clock only while a bubble is on screen.
  ///
  /// Live frames land every ~30 s, so without this the freshness line sits at
  /// whatever it read when the bus was pinned and then jumps — which is the one
  /// number on this map whose whole job is to say how old the rest of it is.
  void _syncBubbleTicker({required bool wanted}) {
    if (wanted == (_bubbleTicker != null)) return;
    _bubbleTicker?.cancel();
    _bubbleTicker = !wanted
        ? null
        : Timer.periodic(
            const Duration(seconds: 1),
            (_) => unawaited(_tickBubbles()),
          );
  }

  /// Repaints each visible bubble against the current clock.
  ///
  /// Not gated on reduce-motion: a clock reading its own value is information,
  /// not decoration. `busGpsAge` only spells out seconds between 15 and 59, so
  /// outside that window the text is unchanged, `MapMarkers` hands back the
  /// very bitmap already on screen, and the identity check below skips the
  /// repaint. The once-a-second wake-up then costs a cache lookup per bubble.
  Future<void> _tickBubbles() async {
    if (await _overlay.tickBubbles(DateTime.now()) && mounted) {
      _paintVehicles();
    }
  }

  // Composes the animated bus + bubble markers over the static stop layer and
  // pushes them to the GoogleMap notifier. Runs per glide tick; the sprite and
  // bubble bitmaps are memoized upstream, so a tick is cheap position churn.
  void _paintVehicles() {
    _mapLayer.value = _overlay.paint(
      glideProgress: _busGlideCurve.value,
      pinnedPlate: _pinnedPlate,
    );
  }

  void _maybeFit() {
    if (_fitted) return;
    final c = _mapController;
    if (c == null || _overlay.stopPoints.isEmpty) return;
    _fitted = true;
    unawaited(c.animateCamera(_fitUpdate()));
  }

  CameraUpdate _fitUpdate() => _overlay.stopPoints.length == 1
      ? CameraUpdate.newLatLngZoom(_overlay.stopPoints.first, 16)
      : CameraUpdate.newLatLngBounds(boundsOf(_overlay.stopPoints), 60);

  void _recenterMap() {
    final controller = _mapController;
    if (controller != null) {
      unawaited(
        controller.animateCamera(
          _overlay.stopPoints.isEmpty
              ? CameraUpdate.newCameraPosition(_kDefaultCamera)
              : _fitUpdate(),
        ),
      );
    }
  }

  /// Scrolls the stop list to [stopUid] and highlights that row for a few
  /// seconds. Row heights vary, so the target offset is estimated and clamped
  /// to the scroll extent — it lands the stop near the top, not pixel-exact.
  // index × estimated row height; move to scrollable_positioned_list
  // only if pixel-exact landing is ever needed.
  void _flashStop(String stopUid) {
    _selectStop(_selectedStopUid == stopUid ? null : stopUid);
    final index = _stopUidsInOrder.indexOf(stopUid);
    if (index >= 0) {
      // Vertical stop list: rows vary in height, so the offset is an estimate.
      if (_scrollController.hasClients) {
        // Matches _StopListItem's BoxConstraints(minHeight: 54) in
        // bus_route_stop_list_widgets.dart — rows can grow taller than this
        // (secondary label line, text scale), so it's a floor, not an exact
        // row height; keep it in sync if that minHeight ever changes.
        const estRowHeight = 54.0;
        final target = (index * estRowHeight).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        unawaited(
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 320),
            curve: AppMotion.easeInOut,
          ),
        );
      }
      // Horizontal timeline: fixed 120px cells, so centre the stop exactly.
      if (_timelineController.hasClients) {
        const cellWidth = 120.0;
        final pos = _timelineController.position;
        final target =
            (index * cellWidth + cellWidth / 2 - pos.viewportDimension / 2)
                .clamp(0.0, pos.maxScrollExtent);
        unawaited(
          _timelineController.animateTo(
            target,
            duration: const Duration(milliseconds: 320),
            curve: AppMotion.easeInOut,
          ),
        );
      }
    }
    _flashTimer?.cancel();
    setState(() => _flashStopUid = stopUid);
    _flashTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _flashStopUid = null);
    });
  }

  /// Opens (or closes) the stop capsule. Nothing animates: a [BitmapDescriptor]
  /// can't be tweened, so the capsule appears at full size rather than being
  /// faked with an overlay that would shake through every pan
  /// (`marker_factory.dart`). Reduce-motion is therefore already satisfied.
  void _selectStop(String? stopUid) {
    if (_selectedStopUid == stopUid) return;
    _selectedStopUid = stopUid;
    _repaintPins();
  }

  /// Unpins the bus and leaves pick-mode, cancelling any armed tracking
  /// session. Reached both by re-tapping the pinned marker and by the pick
  /// bar's explicit 取消選站 control — the marker alone was undiscoverable as
  /// the only way out.
  void _cancelPick() {
    context.read<JourneySessionBloc>().add(const JourneyCancelled());
    setState(() {
      _pinnedPlate = null;
      _pickingStop = false;
      _pinnedNextStopIndex = null;
      _targetStopUid = null;
    });
    _repaintPins();
    _liftSheet(false);
  }

  /// Selects/deselects the bus marker [plate]. Selecting enters pick-mode
  /// (＋, "selected, not yet tracking"); tapping the pinned bus again unpins and
  /// cancels any armed tracking session.
  /// Selects a bus, or deselects the one already selected.
  ///
  /// Selection is a glance: it brings up that bus's bubble (plate, status, GPS
  /// freshness) and recedes the others. It deliberately does not start the
  /// 下車提醒 flow — tapping a mark to read it should not arm anything. The
  /// bell is the one entry point into picking an alight stop, and it uses this
  /// selection when there is one.
  void _togglePin(String plate) {
    if (_pinnedPlate == plate) {
      _clearPin();
      return;
    }
    final s = _bloc.state;
    // Snapshot the bus's position now, so that if the rider does go on to pick
    // an alight stop the passed/downstream split holds still rather than
    // shifting under each live frame.
    final nextStopIndex = pinnedBusNextStopIndex(
      etas: s.etaMap.values,
      stopUidsInOrder: _stopUidsInOrder,
      direction: s.direction,
      plate: plate,
    );
    setState(() {
      _pinnedPlate = plate;
      _pinnedNextStopIndex = nextStopIndex;
    });
    _repaintPins();
  }

  /// Drops the selection without touching any running 追蹤.
  ///
  /// Distinct from [_cancelPick], which also ends the session: deselecting a
  /// bus you were only looking at must not cancel a reminder you set earlier.
  void _clearPin() {
    setState(() {
      _pinnedPlate = null;
      _pinnedNextStopIndex = null;
    });
    _repaintPins();
  }

  /// Holds the sheet at full while picking — the swiped row and the stop about
  /// to be tapped are both in that list — and drops it back to peek when
  /// picking ends. Also what back collapses to, since the resting detent
  /// differs by mode.
  ///
  /// No scroll-to accompanies it: the rider just swiped the vehicle row, so it
  /// is on screen by definition, and every stop that bus has not reached is
  /// directly below it.
  void _liftSheet(bool picking) => unawaited(
    _sheetController.animateToDetent(
      picking ? AppSheetSnap.full : AppSheetSnap.peek,
      reduced: AppMotion.reduced(context),
    ),
  );

  // Pin state lives in [State], not the map signature, so a select/confirm
  // repaints the bus bubbles (glyph + dim) by forcing [_syncMap] to rebuild.
  void _repaintPins() {
    unawaited(_syncMap(_bloc.state));
  }

  /// Opens pick-mode from a right-swipe on a vehicle marker in the stop list —
  /// the only entry (ADR-0020).
  ///
  /// The gesture *is* the 指定車輛 binding, which is why no plate chooser
  /// follows it: the rider swiped the bus they are sitting on, so there is
  /// nothing left to guess at and nothing to correct afterwards.
  void _enterPickFromSwipe(String plate, int markerIndex) {
    setState(() {
      _pinnedPlate = plate;
      _pickingStop = true;
      // The marker sits between the stop the bus just passed and the one it is
      // heading for, so its own index is that next stop — the same snapshot
      // _togglePin takes, held still for the rest of the flow.
      _pinnedNextStopIndex = markerIndex;
      _targetStopUid = null;
      _leadStops = 0;
    });
    _repaintPins();
    _liftSheet(true);
  }

  /// The confirm bar for an open bus flow: how many stops of warning, and the
  /// commit. It carries no binding row — the swipe that opened the flow named
  /// the vehicle, so there is nothing here for the rider to settle.
  Widget _buildAlightConfirmBar(BuildContext context, BusRouteState state) {
    final stops = _currentStops(state);
    final target = _targetStopUid;
    final targetStop = stops.where((s) => s.stopUid == target).firstOrNull;
    if (targetStop == null) return const SizedBox.shrink();
    return AlightConfirmBar(
      targetName: targetStop.stopName,
      lead: _leadStops,
      onLeadChanged: (v) => setState(() => _leadStops = clampLeadStops(v)),
      onRepick: () => setState(() => _targetStopUid = null),
      onCancel: _cancelPick,
      onStart: _confirmPick,
      canStart: _pinnedPlate != null,
    );
  }

  void _onPickStop(String uid) {
    setState(() => _targetStopUid = uid);
  }

  /// The 提前提醒站 for the current pick, or null when 提前站數 is 0 (the
  /// default) or no 下車站 has been chosen yet. Derived rather than stored so
  /// the 🔔 moves as the rider turns the stepper — the setting's effect is
  /// visible in the list while it is still being set, not only after 開始.
  String? get _leadStopUid {
    final target = _targetStopUid;
    if (target == null || _leadStops <= 0) return null;
    final trigger = resolveTriggerStopUid(_stopUidsInOrder, target, _leadStops);
    return trigger == target ? null : trigger;
  }

  /// The plate a running 下車提醒 on this subroute follows, so the stop list
  /// can mark that vehicle's row. Null for another route's session, or none.
  String? _boundPlate(BuildContext context) {
    final session = context.watch<JourneySessionBloc>().state;
    if (trackedBusStopUid(session, _bloc.subRouteUid) == null) return null;
    return session.plate;
  }

  /// The current direction's stops, or empty when the route isn't loaded.
  List<BusStopModel> _currentStops(BusRouteState s) {
    final route = s.route;
    if (route == null) return const [];
    return s.direction == 0 ? route.stopsGo : route.stopsReturn;
  }

  /// 完成: start plate-tracked waiting on the picked alight stop and arm the
  /// reminders that back it in the background.
  ///
  /// Two rows, not one (ADR-0020): the 下車站 always, and the 提前提醒站 as
  /// well whenever 提前站數 is above 0. They are separate reminders because
  /// they are separate events — a short buzz and a long one — and the server
  /// fires each exactly once.
  void _confirmPick() {
    final plate = _pinnedPlate;
    final target = _targetStopUid;
    if (plate == null || target == null) return;
    final s = _bloc.state;
    final route = s.route;
    if (route == null) return;
    final stops = _currentStops(s);
    final idx = stops.indexWhere((st) => st.stopUid == target);
    if (idx < 0) return;
    context.read<JourneySessionBloc>().add(
      JourneyStarted(
        trackOnly: true,
        plate: plate,
        legs: [
          busTrackingLeg(
            route: route,
            stops: stops,
            boardIndex: idx,
            direction: s.direction,
          ),
        ],
        // The same 提前站數 that arms the reminder below also decides where the
        // tracking card's bar turns warm. Without it the card would fall back
        // to its default and warn at a different stop than the rider set.
        leadStops: _leadStops,
      ),
    );
    _bloc.add(
      BusRoutePinnedReminderArmed(
        stopUid: target,
        plate: plate,
        event: AlightEvent.alight,
      ),
    );
    if (_leadStops > 0) {
      final trigger = resolveTriggerStopUid(
        _stopUidsInOrder,
        target,
        _leadStops,
      );
      // A lead that resolves back onto the 下車站 (the bus is already inside
      // the lead window) would arm the same stop twice; the bloc's own
      // already-armed guard drops it, but not asking is clearer.
      if (trigger != target) {
        _bloc.add(
          BusRoutePinnedReminderArmed(
            stopUid: trigger,
            plate: plate,
            event: AlightEvent.lead,
          ),
        );
      }
    }
    setState(() => _pickingStop = false);
    _repaintPins();
    _liftSheet(false);
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _bubbleTicker?.cancel();
    _busGlideCurve.dispose();
    _busGlide.dispose();
    _tabController.dispose();
    _sheetController.dispose();
    _scrollController.dispose();
    _timelineController.dispose();
    _mapLayer.dispose();
    unawaited(_bloc.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final sheetAnimation = SheetOffsetDrivenAnimation(
      controller: _sheetController,
      initialValue: 0,
    );

    // Pixel height of the peek detent — the resting state whenever the sheet
    // isn't being dragged. Shared by the camera fit (finding 2, keeps the
    // route's tail from landing under the sheet) and the recenter FAB fade
    // (finding 6, keeps it off the app bar mid-drag).
    final sheetPeekPx =
        MediaQuery.sizeOf(context).height * AppSheetSnap.peekFrac;

    return BlocProvider<BusRouteBloc>.value(
      value: _bloc,
      child: BlocConsumer<BusRouteBloc, BusRouteState>(
        // etaMap is deliberately excluded: live ETA frames must not rebuild the
        // static chrome (map, app bar, FAB, sheet skeleton). ETA-consuming
        // subtrees observe etaMap through their own BlocSelectors instead.
        buildWhen: (prev, curr) =>
            prev.route != curr.route ||
            prev.direction != curr.direction ||
            prev.fare != curr.fare ||
            prev.bufferSequences != curr.bufferSequences ||
            prev.daily != curr.daily ||
            prev.loading != curr.loading ||
            prev.error != curr.error,
        listener: (context, state) => _syncMap(state),
        builder: (context, state) {
          // subRouteUid is an internal identifier (e.g. "TPE..."), never a
          // user-facing name — while the route hasn't loaded (still loading,
          // or failed; see the error banner below) the pill shows blank
          // rather than leak it into the header.
          final routeName = state.route?.routeName ?? '';
          final dirNames = [
            state.route?.headsignGo ?? '',
            state.route?.headsignReturn ?? '',
          ];
          final dirName = state.direction == 0 ? dirNames[0] : dirNames[1];

          // Back unwinds the sheet before it unwinds the page, the same way
          // home does: a raised sheet collapses to its resting detent first,
          // and only a sheet already down leaves the route. `canPop` tracks
          // that so the platform keeps its own back gesture (and predictive
          // preview) for the step that really does depart. Rebuilding on every
          // sheet tick is cheap here — only the PopScope is inside the builder.
          return ValueListenableBuilder<double?>(
            valueListenable: _sheetController,
            builder: (context, offset, child) {
              // minOffset rather than the peek fraction: the resting detent is
              // the pick offset mid-pick, and metrics stay honest either way.
              final metrics = _sheetController.metrics;
              final atRest =
                  metrics == null ||
                  offset == null ||
                  offset <= metrics.minOffset + 1;
              return PopScope(
                canPop: atRest,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) _liftSheet(_pickingStop);
                },
                child: child!,
              );
            },
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: Stack(
                children: [
                  Positioned.fill(
                    child: ValueListenableBuilder<BusMapLayer>(
                      valueListenable: _mapLayer,
                      builder: (context, layer, _) => GoogleMap(
                        style: mapStyleOf(context),
                        initialCameraPosition: _kDefaultCamera,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        compassEnabled: false,
                        markers: layer.markers,
                        polylines: layer.polylines,
                        // Reserves the peek sheet's footprint so
                        // newLatLngBounds (in _fitUpdate) fits the route into
                        // the visible area above it instead of the full
                        // viewport — otherwise the route's tail lands hidden
                        // under the sheet.
                        padding: EdgeInsets.only(bottom: sheetPeekPx),
                        // Map shares a Stack with the draggable sheet; without
                        // an eager recognizer the map loses the gesture arena,
                        // so pan/pinch leak to the sheet instead of the map.
                        gestureRecognizers: const {
                          Factory<OneSequenceGestureRecognizer>(
                            EagerGestureRecognizer.new,
                          ),
                        },
                        // The marker toggles its own capsule, but a rider who
                        // has moved on shouldn't have to find it again to
                        // close it.
                        onTap: (_) => _selectStop(null),
                        onMapCreated: (controller) {
                          _mapController = controller;
                          _maybeFit();
                        },
                      ),
                    ),
                  ),

                  if (state.error != null)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      bottom: sheetPeekPx,
                      // Otherwise a load failure leaves the peek detent showing
                      // a blank map above a blank timeline with no explanation
                      // — ErrorStateView already covers this inside the 站牌列表
                      // tab, but that tab sits well below the fold at peek.
                      child: AnimatedBuilder(
                        animation: sheetAnimation,
                        builder: (context, child) {
                          // Mirrors the timeline's own fade curve in
                          // _RouteSheet so this recedes as the sheet rises past
                          // peek, instead of lingering behind it.
                          final progress = sheetAnimation.value;
                          final opacity = (1.0 - progress * 1.6).clamp(
                            0.0,
                            1.0,
                          );
                          return Opacity(
                            opacity: opacity,
                            child: IgnorePointer(
                              ignoring: progress > 0.5,
                              child: child,
                            ),
                          );
                        },
                        // ErrorStateView carries no surface of its own — inside
                        // a sheet it sits on the sheet's. Here its ground is
                        // the live map, so it needs one: unbacked, the text
                        // lands on streets and labels and stops being
                        // readable. Opaque rather than translucent because the
                        // map behind a failed load has nothing left to say,
                        // and it returns the moment the sheet is pulled up
                        // (this whole layer fades with the sheet).
                        child: ColoredBox(
                          color: cs.surface,
                          child: SafeArea(
                            bottom: false,
                            // Clears the floating app bar row (44px buttons +
                            // 8px top/bottom padding) so back/bookmark stay
                            // reachable.
                            child: Padding(
                              padding: const EdgeInsets.only(top: 60),
                              child: ErrorStateView(
                                error: state.error!,
                                onRetry: () => context.read<BusRouteBloc>().add(
                                  const BusRouteStarted(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  _FloatingAppBar(
                    subRouteUid: widget.subRouteUid,
                    routeName: routeName,
                    dirName: dirName,
                    direction: state.direction,
                  ),

                  if (state.error == null)
                    ValueListenableBuilder<double?>(
                      valueListenable: _sheetController,
                      builder: (context, offset, child) {
                        final currentOffset = offset ?? 0.0;
                        // Past the peek detent the sheet keeps climbing toward
                        // the 收藏 bookmark button in the app bar; clamping the
                        // travel stops the FAB there, and fading it out over
                        // the same range means it's not just stuck, it's gone
                        // before it would ever collide.
                        const fadeRange = 80.0;
                        final overshoot = currentOffset - sheetPeekPx;
                        final opacity = (1.0 - overshoot / fadeRange).clamp(
                          0.0,
                          1.0,
                        );
                        return Positioned(
                          right: 16,
                          bottom: currentOffset.clamp(0.0, sheetPeekPx) + 16,
                          child: IgnorePointer(
                            ignoring: opacity == 0,
                            child: Opacity(opacity: opacity, child: child),
                          ),
                        );
                      },
                      child: Pressable(
                        onTap: _recenterMap,
                        semanticLabel: AppI18n.of(context).commonLocateMe,
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

                  _RouteSheet(
                    tabController: _tabController,
                    sheetController: _sheetController,
                    scrollController: _scrollController,
                    timelineController: _timelineController,
                    flashStopUid: _flashStopUid,
                    vehicles: const [],
                    direction: state.direction,
                    isLoading: state.loading,
                    onDirectionChanged: (dir) {
                      if (state.direction == dir) return;
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
                    pickingStop: _pickingStop,
                    pinnedNextStopIndex: _pinnedNextStopIndex,
                    targetStopUid: _targetStopUid,
                    leadStopUid: _leadStopUid,
                    boundPlate: _boundPlate(context),
                    onPickStop: _onPickStop,
                    onSwipeVehicle: _enterPickFromSwipe,
                    onCancelPick: _cancelPick,
                  ),

                  // The mode capsule now rides inside the sheet, in the
                  // direction slider's slot: the list it changes the meaning of
                  // is in the sheet, and a capsule over the map would be
                  // labelling the wrong surface.
                  if (_pickingStop && _targetStopUid != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildAlightConfirmBar(context, state),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
