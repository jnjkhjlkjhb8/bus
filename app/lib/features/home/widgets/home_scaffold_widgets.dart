part of '../home_screen.dart';

extension _HomeScreenScaffold on _HomeScreenState {
  /// The map and everything the map itself draws.
  ///
  /// Nearby pins and member capsules are published through separate notifiers
  /// — a nearby refresh and a selection have nothing to say to each other —
  /// and merged here into the one set the platform view takes.
  Widget _buildMap(BuildContext context) {
    return ValueListenableBuilder<Set<Marker>>(
      valueListenable: _markers,
      builder: (context, markers, _) => ValueListenableBuilder<Set<Marker>>(
        valueListenable: _memberMarkers,
        // Rebuilt per sheet frame purely to republish `padding`; only that
        // option differs, so the platform view diffs down to one inset write.
        builder: (context, memberMarkers, _) => AnimatedBuilder(
          animation: _sheetController,
          builder: (context, _) => GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 15),
            style: mapStyleOf(context),
            onMapCreated: (controller) {
              _mapController = controller;
              _camCenter = _center;
              // Closes the race where a location fix landed while the platform
              // view was already being created with the older centre —
              // `initialCameraPosition` is only read once.
              unawaited(controller.moveCamera(CameraUpdate.newLatLng(_center)));
              _scheduleNearbyForViewport();
            },
            // Member capsules ride in the same set as the nearby pins so the
            // map composites them with the ground they sit on — a Flutter
            // overlay would have to chase the camera over the platform channel
            // and shake through every pan.
            markers: {...markers, ...memberMarkers},
            // Map shares a Stack with the draggable sheet; without an eager
            // recognizer the map loses the gesture arena, so pan/pinch leak to
            // the sheet instead of moving the map.
            gestureRecognizers: const {
              Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
            },
            onCameraMove: (pos) {
              _zoom = pos.zoom;
              _camCenter = pos.target;
            },
            onCameraIdle: () => _onCameraIdle(context),
            padding: EdgeInsets.only(bottom: _mapBottomPadding(context)),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
          ),
        ),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, ColorScheme cs) {
    return PopScope(
      // Back on home unwinds the sheet before it unwinds the app: a pushed
      // sheet page pops, then the sheet returns to peek, and only a sheet
      // already at peek with nothing pushed lets the app go. `canPop: false`
      // is what buys that — the platform hands the gesture over instead of
      // playing its predictive exit preview, which on the first two steps
      // previews a departure that isn't going to happen.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final sheetNavigator = _sheetNavigatorKey.currentState;
        final metrics = _sheetController.metrics;
        switch (homeBackStep(
          sheetPagePushed: sheetNavigator?.canPop() ?? false,
          // minOffset rather than the peek fraction: peek is the lowest detent
          // of the home grid, and reading it off the metrics keeps this honest
          // if that grid ever changes.
          sheetAbovePeek:
              metrics != null && metrics.offset > metrics.minOffset + 1,
          routeCanPop: context.canPop(),
        )) {
          case HomeBackStep.popSheetPage:
            sheetNavigator!.pop();
          case HomeBackStep.collapseSheet:
            unawaited(
              _sheetController.animateToDetent(
                AppSheetSnap.peek,
                reduced: AppMotion.reduced(context),
              ),
            );
          case HomeBackStep.popRoute:
            context.pop();
          // The exit the platform would have run itself, now that nothing on
          // this page has a use for the gesture.
          case HomeBackStep.exitApp:
            unawaited(SystemNavigator.pop());
        }
      },
      child: _buildScaffoldBody(context, cs),
    );
  }

  Widget _buildScaffoldBody(BuildContext context, ColorScheme cs) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Mounted on the first frame at the default centre. Creating the
          // platform view is the slowest single step in home, so it must not
          // sit behind a location fix; `_initializeMapPosition` moves the
          // camera as soon as the OS-cached position arrives.
          Positioned.fill(child: _buildMap(context)),

          // Sits directly on the map and under every control: the ring is
          // about the map's contents, not about the chrome floating over it.
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<_ScanRing>(
                valueListenable: _scanRing,
                builder: (context, ring, _) => ring.radiusPx <= 0
                    ? const SizedBox.shrink()
                    : RepaintBoundary(
                        child: CustomPaint(
                          painter: _ScanRingPainter(
                            progress: _scanController,
                            center: ring.center,
                            radius: ring.radiusPx,
                            color: cs.onSurface,
                            still: ring.still,
                          ),
                        ),
                      ),
              ),
            ),
          ),

          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: Pressable(
                onTap: () {
                  unawaited(context.push(AppRoutes.settings));
                },
                semanticLabel: AppI18n.of(context).commonSettings,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: AppTheme.floatingControl(
                    cs,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.settings_rounded,
                    size: 20,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  BlocBuilder<AlertBloc, AlertState>(
                    buildWhen: (p, c) => p.unreadCount != c.unreadCount,
                    builder: (context, state) {
                      final unread = state.unreadCount;
                      return Pressable(
                        onTap: () => unawaited(showNotificationSheet(context)),
                        semanticLabel: unread > 0
                            ? AppI18n.of(context).unreadNotifications(unread)
                            : AppI18n.of(context).commonNotifications,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: AppTheme.floatingControl(
                                cs,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                unread > 0
                                    ? Icons.notifications_rounded
                                    : Icons.notifications_none_rounded,
                                size: 20,
                                color: cs.onSurface,
                              ),
                            ),
                            if (unread > 0)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: UnreadBadge(count: unread),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  Pressable(
                    onTap: () {
                      unawaited(context.push(AppRoutes.metro));
                    },
                    semanticLabel: AppI18n.of(context).modeMetro,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: AppTheme.floatingControl(
                        cs,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.directions_subway_rounded,
                        size: 20,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Pressable(
                    onTap: _onRailQueryTap,
                    semanticLabel: AppI18n.of(context).modeRailPair,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: AppTheme.floatingControl(
                        cs,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.train_rounded,
                        size: 20,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Severe-alert capsule, centered in the gap between the settings
          // button and the right control column; expands outward from its
          // midpoint when an alert arrives.
          const Positioned(
            top: 16,
            left: 16 + 44 + 8,
            right: 16 + 44 + 8,
            child: SafeArea(
              // No height cap: the arrival state is taller than the 44px
              // resident capsule and grows downward over the map.
              child: Center(child: HomeAlertCapsule()),
            ),
          ),

          // Floating controls: recenter above, route planner below. They ride
          // the sheet while it sits below the half detent, then park at half
          // once it's taller — so they never climb into the sheet content.
          Positioned(
            right: 16,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _sheetController,
              builder: (context, child) {
                // metrics stays null until the sheet is laid out, whereas
                // SheetController.value throws once attached-but-unmeasured
                // (offset getter is `_offset!`); read both from one snapshot.
                final metrics = _sheetController.metrics;
                final viewport =
                    metrics?.viewportSize.height ??
                    MediaQuery.sizeOf(context).height;
                final offset =
                    metrics?.offset ?? viewport * AppSheetSnap.peekFrac;
                final lift =
                    math.min(offset, viewport * AppSheetSnap.halfFrac) + 16;
                return Padding(
                  padding: EdgeInsets.only(bottom: lift),
                  child: child,
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  Pressable(
                    onTap: _recenter,
                    semanticLabel: AppI18n.of(context).commonLocateMe,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: AppTheme.floatingControl(
                        cs,
                        borderRadius: BorderRadius.circular(12),
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
                  Pressable(
                    onTap: () {
                      unawaited(context.push(AppRoutes.go));
                    },
                    semanticLabel: AppI18n.of(context).homePlanRoute,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: AppTheme.floatingControl(
                        cs,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.directions_rounded,
                        size: 20,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          AppSheet.paged(
            controller: _sheetController,
            navigator: Navigator(
              key: _sheetNavigatorKey,
              observers: [_sheetCarry],
              onGenerateInitialRoutes: (navigator, initialRoute) => [
                PagedSheetRoute(
                  initialOffset: AppSheetSnap.peek,
                  snapGrid: _sheetCarry,
                  scrollConfiguration: const SheetScrollConfiguration(),
                  builder: _buildSheetRoot,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetRoot(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetPageTopInset(child: SheetDragHandle()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _SearchBar(
                  onTap: () {
                    unawaited(context.push(AppRoutes.search));
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        RouteTabBar(
          controller: _tabController,
          tabs: [
            AppI18n.of(context).homeTabFavorites,
            AppI18n.of(context).homeTabNearby,
          ],
          raised: true,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              const _FavoritesTab(),
              _NearbyStationsTab(
                onStationTap: _onStationTap,
                sheetController: _sheetController,
                sheetTicks: _rootSheetTicks,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Radius the ring emerges from — roughly the location dot itself. Growing
/// from zero would read as appearing out of nowhere rather than spreading
/// out from the user.
const double _kScanSeedRadius = 12;
const double _kScanStrokeWidth = 1.5;

/// Peak stroke opacity of the expanding ring, and of the still one that never
/// travels — the still version lingers, so it sits lower.
const double _kScanPeakAlpha = 0.55;
const double _kScanStillPeakAlpha = 0.35;

/// Fill opacity as a fraction of the stroke's, keeping the disc a wash the
/// map still reads through.
const double _kScanFillAlpha = 0.07;

/// Share of the sweep spent fading in. Reaching full opacity instantly makes
/// the tap read as a camera flash.
const double _kScanFadeInFraction = 0.1;

/// Radius and stroke opacity the scan ring holds at [t] of its sweep. Pulled
/// out of the painter so the shape of the motion — emerges from the location
/// dot, peaks early, arrives at the queried radius as it vanishes — can be
/// asserted without a canvas. See [scanRingFrameForTest].
(double, double) _scanRingFrame({
  required double t,
  required double radius,
  required bool still,
}) {
  // The still variant keeps what the ring says — how far the search reached —
  // and drops the travel: it holds at full size and breathes once.
  if (still) {
    return (radius, _kScanStillPeakAlpha * (1 - (t * 2 - 1).abs()));
  }
  final eased = AppMotion.easeOut.transform(t);
  final alpha = eased < _kScanFadeInFraction
      ? _kScanPeakAlpha * eased / _kScanFadeInFraction
      : _kScanPeakAlpha *
            (1 - (eased - _kScanFadeInFraction) / (1 - _kScanFadeInFraction));
  return (_kScanSeedRadius + (radius - _kScanSeedRadius) * eased, alpha);
}

/// The one-shot ring a manual locate tap leaves on the map: it expands from
/// the user's position to [radius] — the true reach of the nearby query, in
/// pixels — and fades. Painted, not composed of widgets, because it is one
/// circle per frame over a platform view.
class _ScanRingPainter extends CustomPainter {
  _ScanRingPainter({
    required this.progress,
    required this.center,
    required this.radius,
    required this.color,
    required this.still,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final Offset center;
  final double radius;
  final Color color;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t == 0 || t == 1) return;
    final (ringRadius, alpha) = _scanRingFrame(
      t: t,
      radius: radius,
      still: still,
    );

    final bounds = Rect.fromCircle(center: center, radius: ringRadius);
    final wash = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha * _kScanFillAlpha),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.72],
      ).createShader(bounds);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kScanStrokeWidth
      ..color = color.withValues(alpha: alpha);
    canvas
      ..drawCircle(center, ringRadius, wash)
      ..drawCircle(center, ringRadius, stroke);
  }

  @override
  bool shouldRepaint(_ScanRingPainter old) =>
      old.center != center ||
      old.radius != radius ||
      old.color != color ||
      old.still != still;
}
