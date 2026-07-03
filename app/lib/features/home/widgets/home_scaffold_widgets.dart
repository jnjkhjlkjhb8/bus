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
            left: 68,
            child: SafeArea(
              child: Pressable(
                onTap: () {
                  unawaited(HapticService.instance.lightTap());
                  unawaited(context.push('/rail'));
                },
                semanticLabel: '台鐵',
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
                    Icons.train_rounded,
                    size: 20,
                    color: cs.primary,
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
                onExit: () => _sheetController.animateTo(
                  const SheetOffset.proportionalToViewport(0.30),
                ),
                child: Sheet(
                  controller: _sheetController,
                  initialOffset: const SheetOffset.proportionalToViewport(0.30),
                  snapGrid: const SheetSnapGrid(
                    snaps: [
                      SheetOffset.proportionalToViewport(0.10),
                      SheetOffset.proportionalToViewport(0.30),
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
                  child: Column(
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
                          children: const [
                            _FavoritesTab(),
                            _NearbyStationsTab(),
                          ],
                        ),
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
}
