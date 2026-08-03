import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/core/location/location_service.dart';
import 'package:wheres_the_bus/core/update/update_gate.dart';
import 'package:wheres_the_bus/core/update/update_status.dart';
import 'package:wheres_the_bus/data/models/alert_models.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_bloc.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_event.dart';
import 'package:wheres_the_bus/features/alerts/bloc/alert_state.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';
import 'package:wheres_the_bus/shared/widgets/notice_rail.dart';

/// The resident notice layer: at most one ops notice and at most one
/// condition, stacked above the app shell.
///
/// The cap is the point. Four simultaneous strips would eat the top of every
/// screen, so maintenance outranks a general announcement, and offline
/// outranks a dropped alert stream, which outranks a missing location fix.
/// Everything that loses is still reachable — announcements sit in the inbox,
/// and a condition that matters resurfaces the moment the one above it clears.
class NoticeRailHost extends StatefulWidget {
  const NoticeRailHost({super.key});

  @override
  State<NoticeRailHost> createState() => _NoticeRailHostState();
}

class _NoticeRailHostState extends State<NoticeRailHost> {
  /// Which denial the rider has waved off this session. Keyed by value rather
  /// than a bool so that turning location services back on and then denying
  /// permission still gets to speak once.
  LocationDenial? _dismissedDenial;

  Future<void> _openLocationSettings(LocationDenial denial) async {
    switch (denial) {
      case LocationDenial.permission:
        await Geolocator.openAppSettings();
      case LocationDenial.serviceDisabled:
        await Geolocator.openLocationSettings();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      BlocBuilder<AlertBloc, AlertState>(
        buildWhen: (p, c) =>
            p.railAnnouncements.firstOrNull?.message !=
            c.railAnnouncements.firstOrNull?.message,
        builder: _announcementRail,
      ),
      ValueListenableBuilder<LocationDenial?>(
        valueListenable: LocationService.denial,
        builder: (context, denial, _) => BlocBuilder<AlertBloc, AlertState>(
          buildWhen: (p, c) => p.error.runtimeType != c.error.runtimeType,
          builder: (context, state) => _conditionRail(context, state, denial),
        ),
      ),
    ],
  );

  /// Maintenance first: it is the only notice ops can force to stay put.
  Widget _announcementRail(BuildContext context, AlertState state) {
    final announcements = state.railAnnouncements;
    final notice =
        announcements
            .where((a) => a.source?.kind == AlertSourceKind.appMaintenance)
            .firstOrNull ??
        announcements.firstOrNull;
    if (notice == null) {
      return const NoticeRail(
        tone: NoticeTone.info,
        icon: Icons.campaign_rounded,
      );
    }
    final maintenance = notice.source?.kind == AlertSourceKind.appMaintenance;
    return NoticeRail(
      tone: notice.tone,
      icon: maintenance ? Icons.build_rounded : Icons.campaign_rounded,
      message: notice.message,
      // Closing a general announcement means "I've seen it": it stops
      // occupying the rail and stays in the inbox, already read.
      onDismiss: notice.dismissible
          ? () => context.read<AlertBloc>().add(
              AlertMarkedRead(notice.message),
            )
          : null,
    );
  }

  Widget _conditionRail(
    BuildContext context,
    AlertState state,
    LocationDenial? denial,
  ) {
    final error = state.error;
    if (error is OfflineError) {
      return NoticeRail(
        tone: NoticeTone.neutral,
        icon: Icons.cloud_off_rounded,
        message: AppI18n.of(context).alertsOffline,
      );
    }
    if (error != null) {
      return NoticeRail(
        tone: NoticeTone.neutral,
        icon: Icons.wifi_tethering_off_rounded,
        message: AppI18n.of(context).alertsReconnecting,
      );
    }
    if (denial == null || denial == _dismissedDenial) {
      return _updateRail(context);
    }
    final serviceOff = denial == LocationDenial.serviceDisabled;
    return NoticeRail(
      tone: NoticeTone.neutral,
      icon: Icons.location_off_rounded,
      message: serviceOff
          ? AppI18n.of(context).alertsLocationOff
          : AppI18n.of(context).alertsLocationDenied,
      actionLabel: serviceOff
          ? AppI18n.of(context).alertsOpenLocationService
          : AppI18n.of(context).alertsOpenLocationPermission,
      onAction: () => unawaited(_openLocationSettings(denial)),
      onDismiss: () => setState(() => _dismissedDenial = denial),
    );
  }

  /// Last in the condition chain, and deliberately so. Everything above it is
  /// the app failing at its job right now; an available update is optional,
  /// and offline — the condition it most often queues behind — is exactly when
  /// a download can't happen anyway.
  Widget _updateRail(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: availableUpdate,
    builder: (context, version, _) {
      if (version == null) {
        return const NoticeRail(
          tone: NoticeTone.neutral,
          icon: Icons.system_update_rounded,
        );
      }
      final url = storeUrl();
      return NoticeRail(
        tone: NoticeTone.neutral,
        icon: Icons.system_update_rounded,
        message: AppI18n.of(context).updateAvailableVersion(version),
        // No allowed store URL means no action label, rather than a link
        // that no-ops on tap — same rule the blocking screen follows.
        actionLabel: url == null ? null : AppI18n.of(context).settingsUpdateGo,
        onAction: url == null
            ? null
            : () => unawaited(
                launchUrl(url, mode: LaunchMode.externalApplication),
              ),
        onDismiss: () => unawaited(dismissUpdateNudge(version)),
      );
    },
  );
}
