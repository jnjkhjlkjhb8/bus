import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:wheres_the_car/app/router/app_router.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
import 'package:wheres_the_car/core/bootstrap/app_bootstrap.dart';
import 'package:wheres_the_car/core/live_activity/live_activity_channel.dart';
import 'package:wheres_the_car/core/live_activity/pip_mode.dart';
import 'package:wheres_the_car/core/location/location_service.dart';
import 'package:wheres_the_car/core/storage/hive_store.dart';
import 'package:wheres_the_car/core/update/force_update.dart';
import 'package:wheres_the_car/data/repositories/favorites_repository.dart';
import 'package:wheres_the_car/data/repositories/settings_repository.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_car/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_car/features/alerts/view/notification_toast.dart';
import 'package:wheres_the_car/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_car/features/go/bloc/plan_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/journey_session_bloc.dart';
import 'package:wheres_the_car/features/live_activity/bloc/stop_board_bloc.dart';
import 'package:wheres_the_car/features/live_activity/view/journey_pip_card.dart';

// the floor must never double as a ceiling — it must not silently roll
// back a larger system-level accessibility preference. Keep this
// clamp-min-only; any max clamp lives in a separate step (see
// [applyLargeTextCeiling]) so both compose without either one reintroducing
// the old regression.
TextScaler applyLargeTextFloor(TextScaler systemScaler) =>
    systemScaler.clamp(minScaleFactor: 1.3);

/// Caps very large system text scales so fixed-height rows (list tiles,
/// chips, the nav bar) don't clip. Applied on top of [applyLargeTextFloor]
/// (or standalone when the large-text toggle is off) — never inside it.
TextScaler applyLargeTextCeiling(TextScaler systemScaler) =>
    systemScaler.clamp(maxScaleFactor: 2);

class App extends StatefulWidget {
  const App({required this.bootstrap, this.debugRouter, super.key});

  /// Drives [isInitialized]: [AppBootstrapState.ready] and
  /// [AppBootstrapState.degraded] both mean Hive and the gRPC channel are
  /// usable (the only difference is whether a best-effort dependency like
  /// Firebase or PowerSync also came up), so either unlocks the full UI.
  final AppBootstrapController bootstrap;

  /// Overrides the router `_AppShell` mounts once bootstrap is ready.
  /// Production always leaves this null (falls back to `AppRouter.router`);
  /// tests use it to avoid routing into screens with platform-view/network
  /// dependencies (Google Maps, gRPC) that widget tests can't satisfy, so
  /// the bootstrap gate itself stays the thing under test.
  @visibleForTesting
  final GoRouter? debugRouter;

  /// Tracks background initialization completion
  static final isInitialized = ValueNotifier<bool>(false);

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    widget.bootstrap.addListener(_syncInitialized);
    _syncInitialized();
  }

  @override
  void dispose() {
    widget.bootstrap.removeListener(_syncInitialized);
    super.dispose();
  }

  void _syncInitialized() {
    final ready =
        widget.bootstrap.state == AppBootstrapState.ready ||
        widget.bootstrap.state == AppBootstrapState.degraded;
    if (App.isInitialized.value != ready) {
      App.isInitialized.value = ready;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.bootstrap,
      builder: (context, _) {
        switch (widget.bootstrap.state) {
          case AppBootstrapState.initializing:
            return const _BootstrapGateApp(child: _BootstrapSplash());
          case AppBootstrapState.failed:
            return _BootstrapGateApp(
              child: _BootstrapFailedView(
                phase: widget.bootstrap.lastErrorPhase,
                onRetry: widget.bootstrap.retry,
              ),
            );
          case AppBootstrapState.ready:
          case AppBootstrapState.degraded:
            return _AppShell(router: widget.debugRouter);
        }
      },
    );
  }
}

/// Minimal `MaterialApp` for the splash/failed states — no router, no
/// providers, so it never touches Hive/location/gRPC-backed singletons
/// before the essential path has actually settled.
class _BootstrapGateApp extends StatelessWidget {
  const _BootstrapGateApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '我車呢？',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: child,
    );
  }
}

/// Controlled loading screen shown while the essential bootstrap path runs.
/// A plain spinner, not the pulsing coming-soon highlight — that motion is
/// reserved for ETA emphasis (docs/design.md); this is ordinary indefinite
/// progress and respects reduce-motion via `CircularProgressIndicator`'s
/// own platform behavior.
class _BootstrapSplash extends StatelessWidget {
  const _BootstrapSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppTheme.inkLight,
          ),
        ),
      ),
    );
  }
}

/// Shown when an essential dependency (local storage or the gRPC channel
/// config) failed to initialize. No router/providers are mounted behind
/// this — the app cannot safely proceed until [onRetry] succeeds.
class _BootstrapFailedView extends StatelessWidget {
  const _BootstrapFailedView({required this.phase, required this.onRetry});

  final AppBootstrapFailurePhase? phase;
  final VoidCallback onRetry;

  String get _message => switch (phase) {
    AppBootstrapFailurePhase.storage => '本機儲存空間初始化失敗，請確認裝置儲存空間充足後再試一次。',
    AppBootstrapFailurePhase.network => '連線設定初始化失敗，請檢查網路連線後再試一次。',
    null => '啟動失敗，請再試一次。',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 40,
                  color: AppTheme.inkLight,
                ),
                const SizedBox(height: 16),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('bootstrapRetryButton'),
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.inkLight,
                  ),
                  child: const Text('重試'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The full app: providers, router, alerts. Only ever built once bootstrap
/// is `ready` or `degraded` (see `_AppState.build`).
class _AppShell extends StatelessWidget {
  const _AppShell({this.router});

  final GoRouter? router;

  @override
  Widget build(BuildContext context) {
    // Shared across JourneySessionBloc and StopBoardBloc: only one Live
    // Activity can exist, so both drivers must target the same channel.
    final liveActivityChannel = LiveActivityChannel();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AlertBloc()),
        BlocProvider(create: (_) => PlanBloc()),
        BlocProvider(
          create: (_) => JourneySessionBloc(
            // iOS drives the Live Activity / Dynamic Island; Android drives
            // the promoted Live Update notification + status-bar chip
            // (supersedes spec 決策 3, which kept Android on PiP only).
            channel: liveActivityChannel,
            positions: LocationService.instance.navigationStream,
          ),
        ),
        BlocProvider(
          create: (context) => StopBoardBloc(
            channel: liveActivityChannel,
            session: context.read<JourneySessionBloc>(),
          ),
        ),
        BlocProvider(
          create: (_) =>
              FavoritesBloc(FavoritesRepository.instance, App.isInitialized),
        ),
      ],
      child: _AppShellView(router: router),
    );
  }
}

/// Reads `AlertBloc` from context on the first frame, so it must be a
/// *child* of the `MultiBlocProvider` that creates it (P1-08 regression
/// guard: this used to live in the same widget that built the provider,
/// whose own `context` sits above the provider it was trying to read).
class _AppShellView extends StatefulWidget {
  const _AppShellView({this.router});

  final GoRouter? router;

  @override
  State<_AppShellView> createState() => _AppShellViewState();
}

class _AppShellViewState extends State<_AppShellView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AlertBloc>().add(const AlertStarted());
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: HiveStore.settings.listenable(
        keys: const ['large_text', 'appearance_mode'],
      ),
      builder: (context, _, child) => MaterialApp.router(
        title: '我車呢？',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: SettingsRepository.instance.themeMode,
        routerConfig: widget.router ?? AppRouter.router,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          var base = child!;
          final mq = MediaQuery.of(context);
          final floored = HiveStore.largeText
              ? applyLargeTextFloor(mq.textScaler)
              : mq.textScaler;
          base = MediaQuery(
            data: mq.copyWith(textScaler: applyLargeTextCeiling(floored)),
            child: base,
          );
          return _PipGate(
            child: ForceUpdateGate(child: NotificationToastHost(child: base)),
          );
        },
      ),
    );
  }
}

/// Swaps the whole UI for [JourneyPipCard] while Android picture-in-picture is
/// active. On iOS / other platforms [PipMode.isPip] stays false, so [child]
/// always renders.
class _PipGate extends StatelessWidget {
  const _PipGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PipMode.instance.isPip,
      builder: (context, pip, _) => pip ? const JourneyPipCard() : child,
    );
  }
}
