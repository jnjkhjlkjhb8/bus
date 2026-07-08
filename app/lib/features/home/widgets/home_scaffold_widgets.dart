part of '../home_screen.dart';

extension _HomeScreenScaffold on _HomeScreenState {
  Widget _buildScaffold(BuildContext context, ColorScheme cs) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: _mapReady
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _center,
                      zoom: 15,
                    ),
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _camCenter = _center;
                      unawaited(
                        controller.animateCamera(
                          CameraUpdate.newLatLng(_center),
                        ),
                      );
                      _scheduleNearbyForViewport(context);
                    },
                    markers: _markers,
                    onCameraMove: (pos) {
                      _zoom = pos.zoom;
                      _camCenter = pos.target;
                    },
                    onCameraIdle: () => _onCameraIdle(context),
                    padding: EdgeInsets.only(
                      bottom: _mapBottomPadding(context),
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: false,
                  )
                : const _MapSkeleton(),
          ),

          Positioned.fill(
            child: IgnorePointer(child: _LocatePing(ping: _ping)),
          ),

          Positioned(
            top: 16,
            left: 16,
            child: SafeArea(
              child: Pressable(
                onTap: () {
                  unawaited(HapticService.instance.lightTap());
                  unawaited(context.push('/settings'));
                },
                semanticLabel: '設定',
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
                        onTap: () =>
                            unawaited(showNotificationSheet(context)),
                        semanticLabel: unread > 0 ? '通知，$unread 則未讀' : '通知',
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: cs.brightness == Brightness.light
                                    ? Colors.white
                                    : cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: AppShadows.floating,
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
                      unawaited(HapticService.instance.lightTap());
                      unawaited(context.push('/metro'));
                    },
                    semanticLabel: '捷運',
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
                      child: Icon(
                        Icons.directions_subway_rounded,
                        size: 20,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  Pressable(
                    onTap: () {
                      unawaited(HapticService.instance.lightTap());
                      unawaited(context.push('/go'));
                    },
                    semanticLabel: '路線規劃',
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

          // Floating Recenter FAB tracking the bottom sheet's height
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
              onTap: _recenter,
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
                        ? const AppSpinner(key: ValueKey('locating'), size: 20)
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
                onExit: () => _sheetController.animateTo(
                  const SheetOffset.proportionalToViewport(0.30),
                ),
                child: PagedSheet(
                  controller: _sheetController,
                  decoration: MaterialSheetDecoration(
                    size: SheetSize.stretch,
                    color: cs.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppTheme.radiusBottomSheet),
                    ),
                    clipBehavior: Clip.antiAlias,
                  ),
                  navigator: Navigator(
                    key: _sheetNavigatorKey,
                    onGenerateInitialRoutes: (navigator, initialRoute) => [
                      PagedSheetRoute(
                        initialOffset: const SheetOffset.proportionalToViewport(
                          0.30,
                        ),
                        snapGrid: const SheetSnapGrid(
                          snaps: [
                            SheetOffset.proportionalToViewport(0.10),
                            SheetOffset.proportionalToViewport(0.30),
                            SheetOffset.proportionalToViewport(1),
                          ],
                        ),
                        scrollConfiguration: const SheetScrollConfiguration(),
                        builder: (context) => _buildSheetRoot(context, cs),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetRoot(BuildContext context, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetDragHandle(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _SearchBar(
                  onTap: () {
                    unawaited(HapticService.instance.lightTap());
                    unawaited(context.push('/search'));
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        RouteTabBar(
          controller: _tabController,
          tabs: const ['我的收藏', '附近車站'],
          backgroundColor: cs.surfaceContainerLow,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              const _FavoritesTab(),
              _NearbyStationsTab(onStationTap: _openStationDetail),
            ],
          ),
        ),
      ],
    );
  }
}

/// A single ping request: where on screen the ring should emanate from.
class _Ping {
  const _Ping(this.offset);
  final Offset offset;
}

/// Draws one expanding, fading ring — the "scanning around you" cue — each time
/// [ping] changes. Load-only and transient; skipped under reduce-motion (the
/// producer never emits a ping in that case).
class _LocatePing extends StatefulWidget {
  const _LocatePing({required this.ping});

  final ValueListenable<_Ping?> ping;

  @override
  State<_LocatePing> createState() => _LocatePingState();
}

class _LocatePingState extends State<_LocatePing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Offset? _center;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    );
    widget.ping.addListener(_onPing);
  }

  void _onPing() {
    final ping = widget.ping.value;
    if (ping == null || !mounted) return;
    setState(() => _center = ping.offset);
    unawaited(_ctrl.forward(from: 0));
  }

  @override
  void dispose() {
    widget.ping.removeListener(_onPing);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final center = _center;
        if (center == null || !_ctrl.isAnimating) {
          return const SizedBox.expand();
        }
        final t = _ctrl.value;
        final radius = 12 + AppMotion.easeOut.transform(t) * 60;
        return Stack(
          children: [
            Positioned(
              left: center.dx - radius,
              top: center.dy - radius,
              child: CustomPaint(
                size: Size.square(radius * 2),
                painter: _RingPainter(color: color, opacity: (1 - t) * 0.4),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    canvas.drawCircle(
      Offset(r, r),
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.opacity != opacity || old.color != color;
}
