import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_ce_flutter/adapters.dart';
import 'package:wheres_the_car/app/router/app_router.dart';
import 'package:wheres_the_car/app/theme/app_theme.dart';
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
import 'package:wheres_the_car/features/live_activity/bloc/stop_board_cubit.dart';
import 'package:wheres_the_car/features/live_activity/view/journey_pip_card.dart';

class App extends StatefulWidget {
  const App({super.key});

  /// Tracks background initialization completion
  static final isInitialized = ValueNotifier<bool>(false);

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  Widget build(BuildContext context) {
    // Shared across JourneySessionBloc and StopBoardCubit: only one Live
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
          create: (context) => StopBoardCubit(
            channel: liveActivityChannel,
            session: context.read<JourneySessionBloc>(),
          ),
        ),
        BlocProvider(
          create: (_) =>
              FavoritesBloc(FavoritesRepository.instance, App.isInitialized),
        ),
      ],
      child: const _AppView(),
    );
  }
}

class _AppView extends StatefulWidget {
  const _AppView();

  @override
  State<_AppView> createState() => _AppViewState();
}

class _AppViewState extends State<_AppView> {
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
    return ValueListenableBuilder<bool>(
      valueListenable: App.isInitialized,
      builder: (context, initialized, _) {
        if (!initialized) {
          return MaterialApp.router(
            title: '我車呢？',
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: SettingsRepository.instance.themeMode,
            routerConfig: AppRouter.router,
            debugShowCheckedModeBanner: false,
            builder: (context, child) => _PipGate(
              child: ForceUpdateGate(
                child: NotificationToastHost(child: child!),
              ),
            ),
          );
        }

        return ValueListenableBuilder<Box<dynamic>>(
          valueListenable: HiveStore.settings.listenable(
            keys: const ['large_text', 'appearance_mode'],
          ),
          builder: (context, _, child) => MaterialApp.router(
            title: '我車呢？',
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: SettingsRepository.instance.themeMode,
            routerConfig: AppRouter.router,
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              var base = child!;
              if (HiveStore.largeText) {
                final mq = MediaQuery.of(context);
                base = MediaQuery(
                  data: mq.copyWith(
                    textScaler: mq.textScaler.clamp(
                      minScaleFactor: 1.3,
                      maxScaleFactor: 1.6,
                    ),
                  ),
                  child: base,
                );
              }
              return _PipGate(
                child: ForceUpdateGate(
                  child: NotificationToastHost(child: base),
                ),
              );
            },
          ),
        );
      },
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
