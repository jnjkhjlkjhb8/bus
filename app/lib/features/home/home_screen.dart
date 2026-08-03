import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart'
    show LocationServiceDisabledException, PermissionDeniedException;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:wheres_the_bus/app/app.dart';
import 'package:wheres_the_bus/app/router/app_routes.dart';
import 'package:wheres_the_bus/app/theme/app_shadows.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/core/diagnostics/report_screen.dart';
import 'package:wheres_the_bus/core/firebase/crash_reporter.dart';
import 'package:wheres_the_bus/core/location/location_service.dart';
import 'package:wheres_the_bus/core/storage/hive_store.dart';
import 'package:wheres_the_bus/data/models/bus_models.dart';
import 'package:wheres_the_bus/data/models/near_models.dart';
import 'package:wheres_the_bus/data/repositories/favorites_repository.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_state.dart';
import 'package:wheres_the_bus/features/alerts/view/home_alert_capsule.dart';
import 'package:wheres_the_bus/features/alerts/view/notification_sheet.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_stop_bloc.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_stop_event.dart';
import 'package:wheres_the_bus/features/bus/bloc/bus_stop_state.dart';
import 'package:wheres_the_bus/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_bus/features/favorites/bloc/favorites_state.dart';
import 'package:wheres_the_bus/features/favorites/widgets/favorite_tile.dart';
import 'package:wheres_the_bus/features/home/bloc/nearby_bloc.dart';
import 'package:wheres_the_bus/features/home/bloc/nearby_event.dart';
import 'package:wheres_the_bus/features/home/bloc/nearby_state.dart';
import 'package:wheres_the_bus/features/home/bloc/nearby_viewport_query.dart';
import 'package:wheres_the_bus/features/home/widgets/home_station_detail.dart';
import 'package:wheres_the_bus/features/metro/widgets/metro_svg_map.dart';
import 'package:wheres_the_bus/features/rail/view/home_rail_query_sheet.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/map/map_color_scheme.dart';
import 'package:wheres_the_bus/shared/map/marker_factory.dart';
import 'package:wheres_the_bus/shared/motion/app_motion.dart';
import 'package:wheres_the_bus/shared/motion/pressable.dart';
import 'package:wheres_the_bus/shared/widgets/app_spinner.dart';
import 'package:wheres_the_bus/shared/widgets/bottom_sheet_shell.dart';
import 'package:wheres_the_bus/shared/widgets/error_state_view.dart';
import 'package:wheres_the_bus/shared/widgets/route_tab_bar.dart';
import 'package:wheres_the_bus/shared/widgets/state_cards.dart';
import 'package:wheres_the_bus/shared/widgets/transport_icon.dart';

part 'widgets/home_marker_helpers.dart';
part 'widgets/home_member_capsules.dart';
part 'widgets/home_scaffold_widgets.dart';
part 'widgets/home_favorites_widgets.dart';
part 'widgets/home_nearby_widgets.dart';

const _kDefaultPosition = LatLng(25.0330, 121.5654);

/// Gap between the sheet edge and the Google logo. Tuning knob: 0 sits the
/// logo flush on the sheet edge, larger values lift it further up the map.
const _kMapLogoGap = 2.0;

/// How far a settled camera may sit from where the app aimed it and still
/// count as that move arriving — see [_HomeScreenState._selfDrivenTarget]. A
/// bounds fit lands on the centre of the padded viewport rather than the exact
/// midpoint of the poles, so the match has to be approximate.
const _kSelfDrivenSlackMeters = 100.0;

/// One frame's worth of scan-ring geometry — see [_HomeScreenState._scanRing].
typedef _ScanRing = ({Offset center, double radiusPx, bool still});

const _ScanRing _kScanRingIdle = (
  center: Offset.zero,
  radiusPx: 0,
  still: false,
);

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

  /// Keeps the sheet's height continuous when a pushed page pops back to the
  /// nearby list — the root route's snap grid *and* the sheet navigator's
  /// observer. See [CarryBackSnapGrid].
  late final CarryBackSnapGrid _sheetCarry;

  /// Sheet-offset ticks for the *root* sheet page only. Its offset-driven
  /// insets must stop tracking once a detail page covers them — see
  /// [CurrentPageSheetTicks].
  late final CurrentPageSheetTicks _rootSheetTicks;
  late final TabController _tabController;
  LatLng _center = _kDefaultPosition;
  LatLng _camCenter = _kDefaultPosition;
  double _zoom = 15;
  _MarkerStyle _markerStyleCache = _MarkerStyle.largeDot;

  /// Markers feed the [GoogleMap] leaf and nothing else, so they publish
  /// through a notifier rather than setState. A camera settle refreshes them
  /// while the sheet is showing its own bloc-driven list update; routing both
  /// through the root element relaid the whole home tree twice per pan.
  final ValueNotifier<Set<Marker>> _markers = ValueNotifier(const {});
  int _markerRevision = 0;
  Timer? _idleDebounce;
  Timer? _metroPrecacheTimer;

  /// Owned here rather than created by the `BlocProvider` in [build] so the
  /// State can reach it before its first frame: the startup query fires from
  /// [initState]'s post-frame callback, whose context sits above any provider
  /// [build] would install.
  late final NearbyBloc _nearbyBloc = NearbyBloc();

  /// Attempted/succeeded nearby-query centers — see [NearbyViewportQuery]:
  /// a failed attempt never suppresses a retry, only a successful one does.
  NearbyViewportQuery _viewportQuery = const NearbyViewportQuery();

  /// True once the camera sits on a position that came from the device rather
  /// than [_kDefaultPosition] — the position persisted by the previous session
  /// ([HiveStore.lastDevicePosition]), the OS-cached fix, or the fresh GPS one.
  /// Nearby queries are gated on this so the default-Taipei centre the map
  /// falls back to never itself triggers a station fetch.
  bool _deviceLocationResolved = false;

  bool _tabApplied = false;

  String? _highlightedKey;

  /// Member stops of the open bus station group, spread over the map. Null
  /// when no group is open; non-null with an empty member list while the group
  /// fetch is still in flight.
  final ValueNotifier<_MemberSpread?> _spread = ValueNotifier(null);

  /// The capsules those members are drawn as, published separately from
  /// [_markers] so a nearby refresh and a selection never rebuild each other.
  final ValueNotifier<Set<Marker>> _memberMarkers = ValueNotifier(const {});
  int _memberRevision = 0;

  /// Which rendering of the open group is on screen — see [_SpreadPhase].
  final ValueNotifier<_SpreadPhase> _spreadPhase = ValueNotifier(
    _SpreadPhase.idle,
  );

  /// How each pole is drawn, resolved once per spread so a refresh costs
  /// arithmetic rather than a rebuild of the whole cast.
  List<_SpreadPart> _spreadParts = const [];

  /// What the last published capsules were built from. A re-publish only earns
  /// its platform-channel round trip when one of these actually moved; the
  /// arrivals stream ticks every 15 s and mostly changes neither.
  ({int members, String? selected, int labels})? _memberSignature;

  /// Marker key of the group standing spread. Its own pin is withheld while
  /// its members are on the map in its place.
  String? _spreadKey;

  /// Bus station group feeding the spread. Home owns this rather than letting
  /// the sheet's detail view build its own, because the member chips there and
  /// the map's capsules have to agree on which pole is selected.
  BusStopBloc? _stopBloc;
  StreamSubscription<BusStopState>? _stopSub;

  /// Bumped per station-detail push. A superseded detail route completes its
  /// pop future the moment it is removed from under the new one, so the
  /// unfocus that follows must only fire for the detail still on screen.
  int _detailToken = 0;

  /// Latest nearby stations, mirrored from [NearbyBloc] by the listener in
  /// [build]. Focus/unfocus read this rather than the bloc's own state so a
  /// marker rebuild never races the listener that populated it.
  List<NearStationViewModel> _stations = const [];

  /// True while a manual "locate me" tap is acquiring the GPS fix — drives the
  /// recenter FAB's spinner so the button never reads as doing nothing.
  bool _locating = false;

  /// Drives the one-shot scan ring — see [_playScanSweep].
  late final AnimationController _scanController;

  /// Where the ring is anchored, how far it reaches in logical pixels, and
  /// whether it is the quiet variant that holds at its final radius instead of
  /// expanding (see [_playScanSweep]). A zero radius means it has never played
  /// and nothing is painted.
  ///
  /// Only [_ScanRingPainter] reads this, so it publishes through a notifier —
  /// see the note on [_markers] for why the root element stays out of it.
  final ValueNotifier<_ScanRing> _scanRing = ValueNotifier(_kScanRingIdle);

  /// Set by [_locateUser] so the search its recentre triggers is answered with
  /// the full sweep rather than the quiet ring, and cleared as soon as that
  /// search is decided. A deliberate tap is a question; a pan is not.
  bool _scanFromLocate = false;

  /// Where a camera move the app made for the rider is heading — the pan onto
  /// a tapped station, the fit around its poles. Drilling into a station is
  /// not a request to search somewhere else, so the idle those moves end on
  /// must not re-query: the list the rider tapped from stays exactly as they
  /// left it, and no ring claims a search nobody asked for.
  ///
  /// Held as the destination rather than a bare flag so a move that never
  /// happened (target already on screen, animation coalesced away) cannot
  /// swallow the rider's next real pan — only an idle that actually landed on
  /// this spot is skipped.
  LatLng? _selfDrivenTarget;

  Future<void> _rebuildMarkers(List<NearStationViewModel> stations) async {
    final revision = ++_markerRevision;
    final style = _markerStyle(_zoom);
    // A group whose members are on the map withholds its own centre pin: the
    // centre is the average of the poles, not a place anyone waits. Until the
    // members land it stays, so the tap never leaves the map empty.
    // An open group is drawn by the member set from the moment it is tapped:
    // first as its own pin, then as the poles that dissolve it. Two sets would
    // otherwise both claim that marker id.
    final withheld = _spreadKey;
    final markers = await Future.wait(
      stations
          .take(_kMapMarkerLimit)
          .where((s) => '${s.type.name}:${s.stationId}' != withheld)
          .map((s) async {
            final key = '${s.type.name}:${s.stationId}';
            final highlighted = key == _highlightedKey;
            final icon = await _markerIcon(s, style, highlighted: highlighted);
            return Marker(
              markerId: MarkerId(key),
              position: LatLng(s.lat, s.lon),
              icon: icon,
              anchor: const Offset(0.5, 0.5),
              // No InfoWindow: Google's own balloon would open alongside the
              // sheet the tap pushes, giving one action two answers, one of
              // them not ours.
              onTap: () {
                _openStationDetail(s);
              },
            );
          }),
    );
    if (!mounted || revision != _markerRevision) return;
    _markerStyleCache = style;
    _markers.value = markers.toSet();
  }

  void _openStationDetail(NearStationViewModel station) {
    // Only bus stations are groups of poles; everything else is one place and
    // keeps the plain highlight.
    final grouped = station.type == NearStationType.bus;
    if (grouped) {
      _openStopBloc(station);
    } else {
      // Switching to a different kind of station is not a "close" gesture, so
      // the poles leave without the collapse.
      _endSpread();
    }
    _focusStationOnMap(station, spread: grouped);
    final navigator = _sheetNavigatorKey.currentState;
    if (navigator == null) return;
    final token = ++_detailToken;
    // The route stays `/` while this page is up, so a shake report would
    // otherwise name the home screen and not the station it is about.
    ReportScreen.hold(
      route: AppRoutes.home,
      detail:
          '${station.type.name}:${station.stationId} ${station.stationName}',
    );
    unawaited(
      navigator
          // Station detail always sits directly on the root page: tapping a
          // marker from a pushed page replaces that page instead of stacking
          // on it, so one back gesture returns to the nearby list.
          .pushAndRemoveUntil(
            PagedSheetRoute<void>(
              scrollConfiguration: const SheetScrollConfiguration(),
              // Open where the sheet already is, so drilling in from the
              // nearby list doesn't jump the height.
              initialOffset: carriedSheetOffset(
                _sheetController,
                min: AppSheetSnap.peekFrac,
                max: AppSheetSnap.fullFrac,
                fallback: AppSheetSnap.halfFrac,
              ),
              snapGrid: AppSheetSnap.grid,
              builder: (_) => stationDetailPage(
                station,
                bloc: grouped ? _stopBloc : null,
              ),
            ),
            (route) => route.isFirst,
          )
          .then((_) {
            // A newer detail page has already replaced this one's label; only
            // the page that is still current may clear it.
            if (token != _detailToken) return;
            ReportScreen.release();
            _highlightedKey = null;
            // The collapse gives the group's pin back to the nearby set itself
            // when the poles have landed on it, so the rebuild waits for it
            // rather than racing it.
            _collapseSpread();
          }),
    );
  }

  /// Opens the station group behind [station] and starts its spread.
  ///
  /// The sheet is handed this same bloc, so a chip picked in the list and a
  /// capsule tapped on the map are one selection, not two.
  void _openStopBloc(NearStationViewModel station) {
    unawaited(_stopSub?.cancel());
    unawaited(_stopBloc?.close());
    final origin = LatLng(station.lat, station.lon);
    _spreadKey = '${station.type.name}:${station.stationId}';
    _memberSignature = null;
    _spreadParts = const [];
    _memberRevision++;
    _memberMarkers.value = const {};
    _spreadPhase.value = _SpreadPhase.holding;
    // Hand the pin over before the nearby set drops it, so the map never
    // blinks where the user just tapped.
    unawaited(_holdGroupPin(station));
    _spread.value = (
      origin: origin,
      members: const [],
      labels: const {},
      selectedUid: null,
    );
    final bloc = BusStopBloc(
      i18n: AppI18n.of(context),
      stopId: station.stationId,
    );
    _stopBloc = bloc;
    _stopSub = bloc.stream.listen((state) => _onStopState(origin, state));
  }

  void _onStopState(LatLng origin, BusStopState state) {
    if (!mounted || _spread.value == null) return;
    final labels = memberStopLabels(state.members, state.arrivalsByStation);
    final arrived = _spread.value!.members.isEmpty && state.members.isNotEmpty;
    _spread.value = (
      origin: origin,
      members: state.members,
      labels: labels,
      selectedUid: state.selectedStationUid,
    );
    final signature = (
      members: state.members.length,
      selected: state.selectedStationUid,
      labels: Object.hashAll(labels.values),
    );
    if (signature == _memberSignature) return;
    _memberSignature = signature;
    _resolveSpreadParts(_spread.value!);
    if (arrived) {
      unawaited(_openSpread(state.members));
    } else if (_spreadPhase.value == _SpreadPhase.open) {
      // A selection or a label refresh: the poles are already where they
      // belong, so only the markers change.
      unawaited(_publishMemberMarkers());
    }
  }

  /// Frames the poles, then puts them on the map.
  ///
  /// Sequenced, not overlapped: the camera fit decides which poles are on
  /// screen, and publishing under it would only be a set the fit invalidates.
  Future<void> _openSpread(List<BusStationMember> members) async {
    await _fitMembers(members);
    if (!mounted || _spreadPhase.value != _SpreadPhase.holding) return;
    // One publish, so the holding pin is replaced by the poles in the same
    // marker-set write rather than the map going empty between two.
    await _publishMemberMarkers();
    if (!mounted || _spreadPhase.value != _SpreadPhase.holding) return;
    _spreadPhase.value = _SpreadPhase.open;
  }

  /// Drops the group and gives its pin back to the nearby set.
  void _collapseSpread() {
    unawaited(_stopSub?.cancel());
    unawaited(_stopBloc?.close());
    _stopSub = null;
    _stopBloc = null;
    _memberSignature = null;
    _endSpread();
  }

  /// Clears everything the open group owned and gives its pin back to the
  /// nearby set.
  void _endSpread() {
    _spreadPhase.value = _SpreadPhase.idle;
    _spreadKey = null;
    _spread.value = null;
    _spreadParts = const [];
    _memberRevision++;
    _memberMarkers.value = const {};
    unawaited(_rebuildMarkers(_stations));
  }

  void _selectMember(String? stationUid) {
    _stopBloc?.add(BusStopStationSelected(stationUid));
  }

  /// Frames every pole in the group.
  Future<void> _fitMembers(List<BusStationMember> members) async {
    final controller = _mapController;
    if (controller == null || members.length < 2) return;
    // Poles already on screen need no camera at all. Worth the check twice
    // over: it spares a move nobody asked for, and the spread that follows
    // wants the ground still — a fit running underneath would trip the
    // guard that cuts a transition short when the camera moves, and the
    // poles would snap into place instead of leaving the pin.
    if (_membersAlreadyFramed(context, members)) return;
    var south = members.first.lat;
    var north = members.first.lat;
    var west = members.first.lon;
    var east = members.first.lon;
    for (final m in members.skip(1)) {
      south = math.min(south, m.lat);
      north = math.max(north, m.lat);
      west = math.min(west, m.lon);
      east = math.max(east, m.lon);
    }
    // Poles landing on the same coordinate make a zero-size box, which
    // newLatLngBounds answers by zooming all the way in. The pan
    // [_focusStationOnMap] already ran is the right answer for that group.
    if (north - south < 1e-6 && east - west < 1e-6) return;
    _selfDrivenTarget = LatLng((south + north) / 2, (west + east) / 2);
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        _kMemberBoundsPadding,
      ),
    );
  }

  void _openRailQuerySheet() {
    final navigator = _sheetNavigatorKey.currentState;
    if (navigator == null) return;
    unawaited(
      navigator.push(
        PagedSheetRoute<void>(
          scrollConfiguration: const SheetScrollConfiguration(),
          initialOffset: AppSheetSnap.half,
          snapGrid: AppSheetSnap.grid,
          builder: (_) => const SheetPageTopInset(child: HomeRailQuerySheet()),
        ),
      ),
    );
  }

  void _focusStationOnMap(NearStationViewModel station, {bool spread = false}) {
    final key = '${station.type.name}:${station.stationId}';
    // Read only by _rebuildMarkers, which publishes through _markers on the
    // next line — no element on this tree depends on it, so no setState. A
    // group that is about to spread needs no enlarged pin: its members say
    // which station was picked, and better than a bigger dot could.
    _highlightedKey = spread ? null : key;
    final controller = _mapController;
    final target = LatLng(station.lat, station.lon);
    if (controller != null) {
      final tooFarOut = _zoom < _kIconZoomThreshold;
      // A group is about to be followed by a bounds fit once its poles land.
      // Panning to its centre first would spend a camera move only to spend
      // another one a moment later, which reads as a lurch — so it only
      // happens when the pin is far enough off centre to need it.
      final needsPan = !spread || _isOffCentre(context, target);
      // Pan, don't zoom. A tap is not a request to discard the zoom the user
      // chose; only a camera too far out for the icon band gets raised, and
      // only as far as that floor.
      if (tooFarOut) {
        _selfDrivenTarget = target;
        unawaited(
          controller.animateCamera(
            CameraUpdate.newLatLngZoom(target, _kIconZoomThreshold),
          ),
        );
      } else if (needsPan) {
        _selfDrivenTarget = target;
        unawaited(controller.animateCamera(CameraUpdate.newLatLng(target)));
      }
    }
    unawaited(_rebuildMarkers(_stations));
  }

  /// Whether every pole already sits inside the visible band, with the same
  /// margin a bounds fit would have left around them.
  bool _membersAlreadyFramed(
    BuildContext context,
    List<BusStationMember> members,
  ) {
    final viewport = MediaQuery.sizeOf(context);
    final bottomPadding = _mapBottomPadding(context);
    final right = viewport.width - _kMemberBoundsPadding;
    final bottom = viewport.height - bottomPadding - _kMemberBoundsPadding;
    for (final m in members) {
      final at = _projectToScreen(
        point: LatLng(m.lat, m.lon),
        center: _camCenter,
        zoom: _zoom,
        viewport: viewport,
        bottomPadding: bottomPadding,
      );
      if (at.dx < _kMemberBoundsPadding ||
          at.dx > right ||
          at.dy < _kMemberBoundsPadding ||
          at.dy > bottom) {
        return false;
      }
    }
    return true;
  }

  /// Whether [target] sits far enough from the camera centre that a tap on it
  /// should recentre. Measured against the visible band — the part of the map
  /// the sheet is not covering — because that is what the user can see.
  bool _isOffCentre(BuildContext context, LatLng target) {
    final size = MediaQuery.sizeOf(context);
    final visible = math.min(
      size.width,
      size.height - _mapBottomPadding(context),
    );
    final metres =
        visible *
        _kRecentreThresholdFrac *
        metersPerPixel(_camCenter.latitude, _zoom);
    const metresPerDegree = 111320.0;
    final dLat = (target.latitude - _camCenter.latitude) * metresPerDegree;
    final dLon =
        (target.longitude - _camCenter.longitude) *
        metresPerDegree *
        math.cos(_camCenter.latitude * math.pi / 180);
    return math.sqrt(dLat * dLat + dLon * dLon) > metres;
  }

  Future<void> _requestNearbyForViewport(NearbyBloc bloc) async {
    // Home queries only once the camera is on a real device position — never
    // off the default-Taipei centre the map falls back to meanwhile.
    if (!_deviceLocationResolved) return;
    final controller = _mapController;
    // The radius is needed before the dedup check, not after: zooming out at a
    // fixed centre changes nothing about distance but does widen what the query
    // has to cover.
    final int radius;
    if (controller == null) {
      // Startup only: the platform view is still being created. Estimating the
      // radius here rather than waiting for it takes ~1 s off cold-start
      // time-to-stations. See [estimatedNearbyRadius].
      radius = estimatedNearbyRadius(
        size: MediaQuery.sizeOf(context),
        bottomPadding: _mapBottomPadding(context),
        center: _camCenter,
        zoom: _zoom,
      );
    } else {
      final bounds = await controller.getVisibleRegion();
      if (!mounted) return;
      radius = nearbyRadiusForViewport(center: _camCenter, bounds: bounds);
    }
    // Skip when the in-flight or last successful query already covers this
    // viewport — sub-200 m nudges at a comparable radius return essentially the
    // same stations. A *failed* attempt covers nothing, so it can't suppress
    // the next retry (see NearbyViewportQuery).
    final send = _viewportQuery.shouldQuery(_camCenter, radius);
    final fromLocate = _scanFromLocate;
    _scanFromLocate = false;
    // A tap on the locate button is answered even when the dedup skips the
    // query: "this area is already covered" is the honest reply, and a button
    // that does nothing visible is what the ring exists to fix.
    if (send || fromLocate) {
      unawaited(_playScanSweep(radius, still: !fromLocate));
    }
    if (!send) return;
    _viewportQuery = _viewportQuery.withAttempted(_camCenter, radius);
    bloc.add(
      NearbyRequested(
        lat: _camCenter.latitude,
        lon: _camCenter.longitude,
        radius: radius,
      ),
    );
  }

  void _scheduleNearbyForViewport() {
    _idleDebounce?.cancel();
    // The debounce coalesces the burst of camera-idle events a drag or a
    // programmatic recentre produces. The first query of the session has
    // nothing to coalesce with, and those 300 ms sit directly on cold-start
    // time-to-stations, so it goes out immediately instead.
    if (_viewportQuery.inFlight == null &&
        _viewportQuery.lastSuccessful == null) {
      unawaited(_requestNearbyForViewport(_nearbyBloc));
      return;
    }
    _idleDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      unawaited(_requestNearbyForViewport(_nearbyBloc));
    });
  }

  /// Paints the area a nearby search just covered: a ring out to the radius
  /// the query actually used, then gone. Sized off the query's own metres
  /// rather than a pleasing constant, so it states the real reach.
  ///
  /// Two volumes, by how deliberate the search was. A locate tap is rare and
  /// asks a direct question, so it gets the expanding sweep. A pan-driven
  /// search happens tens of times a session, so it gets the [still] variant —
  /// same radius, no travel. Reduce-motion pins everything to [still].
  ///
  /// Either way the trigger is a search, not a camera event: the nudges that
  /// reach no new stations were already dropped upstream, so a ring never
  /// claims a search that did not happen.
  Future<void> _playScanSweep(int meters, {required bool still}) async {
    if (!mounted) return;
    final quiet = still || AppMotion.reduced(context);
    final size = MediaQuery.sizeOf(context);
    _scanRing.value = (
      // Centre of what was searched: the map centres its camera target in the
      // space left above the sheet's bottom padding, and the query is centred
      // on that same target.
      center: Offset(
        size.width / 2,
        (size.height - _mapBottomPadding(context)) / 2,
      ),
      radiusPx: screenPixelsForMeters(
        meters: meters,
        latitude: _camCenter.latitude,
        zoom: _zoom,
      ),
      still: quiet,
    );
    _scanController.duration = quiet ? AppMotion.scanStill : AppMotion.scan;
    await _scanController.forward(from: 0);
  }

  void _onCameraIdle(BuildContext context) {
    final style = _markerStyle(_zoom);
    if (style != _markerStyleCache) {
      unawaited(_rebuildMarkers(_nearbyBloc.state.stations));
    }
    final selfDriven = _selfDrivenTarget;
    _selfDrivenTarget = null;
    // Landed where the app sent it: this idle belongs to a tap on a station,
    // not to the rider looking somewhere new — see [_selfDrivenTarget].
    if (selfDriven != null &&
        haversineMeters(_camCenter, selfDriven) < _kSelfDrivenSlackMeters) {
      return;
    }
    _scheduleNearbyForViewport();
  }

  /// Bottom inset handed to the native map, so the Google logo rides the sheet
  /// edge and parks at half exactly like the floating controls. Read per frame
  /// from the sheet — the padding write re-projects the camera, so the map
  /// content shifts up with the drag rather than jumping once it settles.
  double _mapBottomPadding(BuildContext context) {
    final metrics = _sheetController.metrics;
    if (metrics == null) {
      return (MediaQuery.sizeOf(context).height * 0.30).clamp(180.0, 280.0);
    }
    // Parks the logo just above the sheet edge rather than level with the
    // recenter button, so it reads as map chrome instead of a control.
    return math.min(
          metrics.offset,
          metrics.viewportSize.height * AppSheetSnap.halfFrac,
        ) +
        _kMapLogoGap;
  }

  @override
  void initState() {
    super.initState();
    // Where the device was last seen. Opens the map on the right city and lets
    // the first nearby query go out on the frame after this one, instead of
    // behind the OS location lookup. A stale-by-one-session centre is corrected
    // by the real fix a moment later; the dedup in [_viewportQuery] then
    // decides whether that costs a second query.
    final resumed = HiveStore.lastDevicePosition;
    if (resumed != null) {
      _center = LatLng(resumed[0], resumed[1]);
      _camCenter = _center;
      _deviceLocationResolved = true;
    }
    _sheetController = SheetController();
    _sheetCarry = CarryBackSnapGrid(controller: _sheetController);
    _rootSheetTicks = CurrentPageSheetTicks(
      source: _sheetController,
      isCurrent: () => !(_sheetNavigatorKey.currentState?.canPop() ?? false),
    );
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _initialTabIndex(),
    );
    _scanController = AnimationController(
      vsync: this,
      duration: AppMotion.scan,
    );
    if (FavoritesRepository.instance.isReady) {
      _tabApplied = true;
    } else {
      App.isInitialized.addListener(_onFavoritesReady);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeMapPosition());
      // A position carried over from the last session is already good enough to
      // query on, and the estimated-radius path needs no map controller — so
      // this asks the router while the platform view and the location lookup
      // are both still in flight. Without one, the query waits for a real fix.
      if (_deviceLocationResolved) _scheduleNearbyForViewport();
      // Deferred so the SVG rasterization doesn't compete with home's first
      // interactive frame; still warm well before a user reaches metro.
      _metroPrecacheTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) MetroSvgMap.precache(context);
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
    // The map is already on screen at the default centre by now. Jump it to
    // the last OS-cached fix rather than blocking on a fresh GPS fix, which
    // can take up to 10 s cold; the fresh fix pans the camera when it lands.
    final last = await LocationService.instance.lastKnownPosition();
    if (last != null) {
      unawaited(
        HiveStore.setLastDevicePosition(last.latitude, last.longitude),
      );
    }
    if (!mounted) return;
    if (last != null) {
      setState(() {
        _center = LatLng(last.latitude, last.longitude);
        _camCenter = _center;
        // A cached fix is a real device position, so stations load off it
        // right away rather than behind the cold GPS wait. When the fresh fix
        // lands more than the viewport-query threshold away it pans the camera
        // and the resulting idle re-queries; nearer than that, the cached
        // result already stands and the second query is suppressed.
        _deviceLocationResolved = true;
      });
      // moveCamera, not animateCamera: on a cold start this is the map's
      // first positioning, and sliding across the country reads as a glitch.
      // Null before the platform view finishes creating — onMapCreated then
      // picks up the already-updated _center.
      unawaited(_mapController?.moveCamera(CameraUpdate.newLatLng(_center)));
    }
    try {
      final pos = await LocationService.instance.currentPosition();
      unawaited(
        HiveStore.setLastDevicePosition(pos.latitude, pos.longitude),
      );
      if (!mounted) return;
      final target = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _center = target;
        _camCenter = target;
      });
      // If the map is already up, pan to the fix; the resulting camera-idle
      // re-queries nearby stations. Before map creation, initialCameraPosition
      // picks up the new _center on its own.
      final controller = _mapController;
      if (controller != null) {
        unawaited(controller.animateCamera(CameraUpdate.newLatLng(target)));
      }
    } on Object catch (e, s) {
      _handleLocationFailure(e, s);
    } finally {
      // Resolved either way — success or failure. On failure with no cached
      // fix this is the only thing that opens the gate, so a user who pans the
      // default-centred map still gets stations for wherever they land.
      if (mounted) setState(() => _deviceLocationResolved = true);
    }
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
      // The ring itself plays off the search the resulting camera-idle
      // decides; this only marks that search as the deliberate kind, which
      // earns the full sweep — see [_playScanSweep].
      _scanFromLocate = true;
      unawaited(controller.animateCamera(CameraUpdate.newLatLng(target)));
    } on Object catch (e, s) {
      if (mounted) setState(() => _locating = false);
      _handleLocationFailure(e, s);
    }
  }

  /// Routes a failed location fix to the right outlet: a denied permission or
  /// disabled location service is an expected user choice, already published
  /// on `LocationService.denial` for the resident notice rail to speak — not
  /// a Crashlytics report. Anything else is genuinely unexpected and still
  /// gets recorded.
  void _handleLocationFailure(Object e, StackTrace s) {
    if (e is PermissionDeniedException ||
        e is LocationServiceDisabledException) {
      return;
    }
    CrashReporter.record(e, s);
  }

  void _recenter() {
    unawaited(_locateUser());
  }

  @override
  void dispose() {
    _idleDebounce?.cancel();
    _metroPrecacheTimer?.cancel();
    App.isInitialized.removeListener(_onFavoritesReady);
    _rootSheetTicks.dispose();
    _sheetController.dispose();
    _tabController.dispose();
    _scanController.dispose();
    _spreadPhase.dispose();
    _markers.dispose();
    _scanRing.dispose();
    _spread.dispose();
    _memberMarkers.dispose();
    unawaited(_stopSub?.cancel());
    unawaited(_stopBloc?.close());
    // BlocProvider.value never closes what it is handed.
    unawaited(_nearbyBloc.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Home has no text input of its own, but it stays mounted under pushed
    // routes that do (search). The keyboard's inset would otherwise shrink the
    // sheet viewport here, which moves `_mapBottomPadding`, which writes a new
    // camera padding to the map platform view — a camera shift on a page
    // nobody can see, undone again on the way back. Pinning the insets keeps
    // the map still while it is covered.
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: BlocProvider.value(
        value: _nearbyBloc,
        child: Builder(
          builder: (context) => BlocListener<NearbyBloc, NearbyState>(
            listenWhen: (p, c) =>
                !listEquals(p.stations, c.stations) ||
                p.loading != c.loading ||
                p.error != c.error,
            listener: (_, state) {
              _stations = state.stations;
              unawaited(_rebuildMarkers(state.stations));
              // A settled response releases the in-flight slot either way: on
              // success it becomes the covered viewport, on failure it is
              // discarded so the next idle event can retry the same spot.
              if (!state.loading) {
                _viewportQuery = state.error == null
                    ? _viewportQuery.withSuccess()
                    : _viewportQuery.withFailure();
              }
            },
            child: _buildScaffold(context, cs),
          ),
        ),
      ),
    );
  }
}

/// What Android back does on home, in the order the page offers it.
enum HomeBackStep { popSheetPage, collapseSheet, popRoute, exitApp }

/// The step back takes given what home currently has to unwind.
///
/// Split out from the [PopScope] callback so the ordering — the only part
/// that can silently go wrong — is a plain table a unit test can read.
HomeBackStep homeBackStep({
  required bool sheetPagePushed,
  required bool sheetAbovePeek,
  required bool routeCanPop,
}) {
  if (sheetPagePushed) return HomeBackStep.popSheetPage;
  if (sheetAbovePeek) return HomeBackStep.collapseSheet;
  if (routeCanPop) return HomeBackStep.popRoute;
  return HomeBackStep.exitApp;
}

@visibleForTesting
Widget buildNearbyRowForTest({
  required NearStationViewModel station,
  required ValueChanged<NearStationViewModel> onStationTap,
}) => _NearbyStationRow(station: station, onStationTap: onStationTap);

/// Radius and stroke opacity the scan ring paints at [t] of its sweep, for
/// the expanding and [still] variants — see `_scanRingFrame`.
@visibleForTesting
(double, double) scanRingFrameForTest({
  required double t,
  required double radius,
  required bool still,
}) => _scanRingFrame(t: t, radius: radius, still: still);

/// Dot marker diameter (logical px) for the mid ([large] = true) vs the most
/// zoomed-out ([large] = false) marker band. Exposed so a plain unit test can
/// verify the intended ordering — large > small — without spinning up a map.
@visibleForTesting
double dotMarkerSizeForTest({required bool large}) =>
    large ? _kLargeDotSize : _kSmallDotSize;
