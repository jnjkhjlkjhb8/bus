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
part 'widgets/home_screen_location.dart';
part 'widgets/home_screen_map.dart';
part 'widgets/home_screen_sheet.dart';
part 'widgets/home_screen_spread.dart';

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
  const HomeScreen({super.key, this.station, this.showRailQuery = false});

  /// The station the sheet's second layer is showing, from
  /// `/near/:type/:id`. Null puts the sheet on its nearby list.
  ///
  /// The location leads and the sheet follows — a tap writes the location and
  /// [_HomeScreenSheetX._syncSheetToLocation] opens the page — so arriving on a
  /// link and tapping a marker take exactly the same path in.
  final NearStationRouteArgs? station;

  /// Whether `/rail-query` is showing the rail form as the sheet's second
  /// layer.
  final bool showRailQuery;

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

  /// What the sheet's second layer currently shows, as the `type:id` key the
  /// location carries — null while the sheet is on the nearby list. Compared
  /// against the location to decide whether the sheet has to move at all.
  String? _shownStationKey;

  /// Where closing the open station detail goes — the caller that could not
  /// stay under it, or null for the bare map. See [AppRoutes.nearStation].
  String? _shownStationBack;
  bool _railQueryShown = false;

  /// The nearby model behind the location being navigated to, when it came
  /// from a tap that already had it. A location carries only what a link can;
  /// rebuilding a model from it would throw away the walking time and the
  /// group's own coordinates for no reason.
  NearStationViewModel? _tappedStation;

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
      // After the first frame, because the sheet's navigator has to exist
      // before a page can be put on it. This is what opens a cold deep link
      // into `/near/...` or `/rail-query`.
      _syncSheetToLocation();
    });
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The page is keyed the same across `/`, `/near/...` and `/rail-query`, so
    // a location change updates this widget in place rather than rebuilding
    // the screen — which is what keeps the map alive across the change.
    _syncSheetToLocation();
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
