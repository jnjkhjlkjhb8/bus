import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:wheres_the_bus/app/router/app_router.dart';
import 'package:wheres_the_bus/app/theme/app_theme.dart';
import 'package:wheres_the_bus/core/bootstrap/app_bootstrap.dart';
import 'package:wheres_the_bus/core/lifecycle/app_foreground.dart';
import 'package:wheres_the_bus/core/live_activity/alight_track.dart';
import 'package:wheres_the_bus/core/live_activity/alight_track_cancel_channel.dart';
import 'package:wheres_the_bus/core/location/location_service.dart';
import 'package:wheres_the_bus/core/storage/hive_store.dart';
import 'package:wheres_the_bus/core/update/update_gate.dart';
import 'package:wheres_the_bus/data/repositories/favorites_repository.dart';
import 'package:wheres_the_bus/data/repositories/settings_repository.dart';
import 'package:wheres_the_bus/data/tracking/journey_session_bloc.dart';
import 'package:wheres_the_bus/data/tracking/journey_session_event.dart';
import 'package:wheres_the_bus/data/tracking/journey_session_state.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_bus/features/alerts/view/notification_toast.dart';
import 'package:wheres_the_bus/features/favorites/bloc/favorites_bloc.dart';
import 'package:wheres_the_bus/features/go/bloc/plan_bloc.dart';
import 'package:wheres_the_bus/features/metro/bloc/mrt_track_bloc.dart';
import 'package:wheres_the_bus/features/metro/bloc/mrt_track_event.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/map/marker_factory.dart';

// the floor must never double as a ceiling — it must not silently roll
// back a larger system-level accessibility preference. Keep this
// clamp-min-only; any max clamp lives in a separate step (see

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
    AppForeground.start();
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
      onGenerateTitle: (context) => AppI18n.of(context).appTitle,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      localizationsDelegates: AppI18n.localizationsDelegates,
      supportedLocales: AppI18n.supportedLocales,
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

  String _message(AppI18n i18n) => switch (phase) {
    AppBootstrapFailurePhase.storage => i18n.bootstrapFailedStorage,
    AppBootstrapFailurePhase.network => i18n.bootstrapFailedNetwork,
    null => i18n.bootstrapFailedUnknown,
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
                  _message(AppI18n.of(context)),
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
                  child: Text(AppI18n.of(context).commonRetry),
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
    // Shared across JourneySessionBloc and MrtTrackBloc: only one tracking
    // card can exist, so both drivers must target the same channel.
    final liveActivityChannel = AlightTrackChannel();
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => AlertBloc()),
        BlocProvider(create: (_) => PlanBloc()),
        BlocProvider(
          create: (_) {
            // iOS drives the Live Activity / Dynamic Island; Android drives
            // the promoted Live Update notification + status-bar chip
            // (supersedes spec 決策 3, which kept Android on PiP only).
            final bloc = JourneySessionBloc(
              channel: liveActivityChannel,
              positions: LocationService.instance.navigationStream,
            );
            // Bus, TRA and THSR sessions live here, so the card's 取消追蹤 has
            // to reach this bloc too — bound only to the metro one, the button
            // did nothing at all on a train.
            //
            // Both owners listen and the non-owner ignores it: only one card
            // exists at a time, so "am I running a session" is the whole
            // routing rule, and it beats teaching the platform side which bloc
            // to talk to.
            AlightTrackCancelChannel.bind(() {
              if (bloc.state.phase == JourneyPhase.idle) return;
              bloc.add(const JourneyCancelled());
            });
            return bloc;
          },
        ),
        BlocProvider(
          // The metro alight-reminder session shares the single Live Activity
          // channel; restoring on startup re-lights the bell and re-watches a
          // session that survived a restart (ADR-0015).
          create: (_) {
            final bloc = MrtTrackBloc(
              // `create` runs against this provider's own context, which sits
              // above the MaterialApp that installs Localizations, so
              // `AppI18n.of` has nothing to read. Resolve the locale the same
              // way MaterialApp does instead.
              i18n: lookupAppI18n(
                SettingsRepository.instance.locale ??
                    basicLocaleListResolution(
                      WidgetsBinding.instance.platformDispatcher.locales,
                      AppI18n.supportedLocales,
                    ),
              ),
              channel: liveActivityChannel,
            )..add(const MrtTrackRestored());
            // Tracking card 取消追蹤 action → CancelTrack, but only while this
            // bloc is the one holding the card (see the journey binding above).
            AlightTrackCancelChannel.bind(() {
              if (bloc.state.session == null) return;
              bloc.add(const MrtTrackCancelled());
            });
            return bloc;
          },
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
  // Cancellable so a shell disposed before the delay elapses (tests, hot
  // restart) doesn't leave a pending timer behind.
  Timer? _alertStartTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Delayed so the alert streams (TRA/THSR gRPC + Remote Config) don't
      // compete with home's first interactive frame.
      _alertStartTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        context.read<AlertBloc>().add(const AlertStarted());
      });
    });
  }

  @override
  void dispose() {
    _alertStartTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<dynamic>>(
      valueListenable: HiveStore.settings.listenable(
        keys: const [
          'large_text',
          'appearance_mode',
          SettingsRepository.languageKey,
        ],
      ),
      builder: (context, _, child) => MaterialApp.router(
        onGenerateTitle: (context) => AppI18n.of(context).appTitle,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: SettingsRepository.instance.themeMode,
        // Null for the 'system' preference, which is what hands resolution
        // back to the device's locale list.
        locale: SettingsRepository.instance.locale,
        localizationsDelegates: AppI18n.localizationsDelegates,
        supportedLocales: AppI18n.supportedLocales,
        routerConfig: widget.router ?? AppRouter.router,
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          final base = child!;
          // Marker bitmaps are painted off-tree on a ui.Canvas, so this is the
          // one place they can learn the device pixel ratio and text size to
          // paint at: the only builder that sees every screen and rebuilds
          // when either changes. Any app-level text-scale override must be
          // installed above this read to be picked up here.
          MapMarkers.configure(
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            textScaler: MediaQuery.textScalerOf(context),
          );
          return UpdateGate(child: NotificationToastHost(child: base));
        },
      ),
    );
  }
}
