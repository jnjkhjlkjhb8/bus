import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wheres_the_bus/app/theme/app_text_styles.dart';
import 'package:wheres_the_bus/core/firebase/remote_config.dart';
import 'package:wheres_the_bus/core/storage/hive_store.dart';
import 'package:wheres_the_bus/core/update/update_status.dart';
import 'package:wheres_the_bus/l10n/app_i18n.dart';

/// The version a soft nudge is currently offering, or null when there is
/// nothing to nudge about (up to date, blocked, already dismissed, or the
/// check hasn't resolved yet).
///
/// Published by [UpdateGate] rather than computed by the rail, so the whole
/// app runs one version check: the blocking screen and the nudge can never
/// disagree about which build is installed. `NoticeRailHost` renders it as a
/// condition strip; see [dismissUpdateNudge] for how it is cleared.
final availableUpdate = ValueNotifier<String?>(null);

/// Silences the nudge for [version]. Persisted, so it stays silenced across
/// launches — but only for that version: publishing a newer one nudges again.
///
/// Deliberately not a timer. The rider has exactly two states here, "I know"
/// and "there's something newer than what I dismissed"; a "remind me in three
/// days" tier would be a third state nobody asked for.
Future<void> dismissUpdateNudge(String version) async {
  availableUpdate.value = null;
  await HiveStore.setDismissedUpdateVersion(version);
}

/// Owns the app's single update check.
///
/// Renders [child] normally, but swaps in a blocking [_ForceUpdateScreen] when
/// the running version is below `min_supported_version`; when the running
/// version merely trails `latest_version`, it publishes [availableUpdate] for
/// the notice rail to pick up instead. The check runs on mount and again on
/// every activated Remote Config revision (F16), so a bar raised — or a
/// release published — after launch takes effect without a relaunch.
///
/// While a check is pending the child shows (never a blank flash) since the
/// common case is up-to-date.
class UpdateGate extends StatefulWidget {
  const UpdateGate({
    required this.child,
    super.key,
    this.revisions,
    this.minVersionOf,
    this.latestVersionOf,
    this.dismissedVersionOf,
  });

  final Widget child;

  /// Injectable for tests; defaults to [AppConfig.revisions()].
  final Stream<void>? revisions;

  /// Injectable for tests; defaults to reading `min_supported_version` from
  /// [AppConfig].
  final String Function()? minVersionOf;

  /// Injectable for tests; defaults to reading `latest_version`.
  final String Function()? latestVersionOf;

  /// Injectable for tests; defaults to the persisted dismissal.
  final String? Function()? dismissedVersionOf;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  String? _blockedAt;
  StreamSubscription<void>? _revisionSub;

  String get _minVersion =>
      (widget.minVersionOf ??
      () => AppConfig.getString('min_supported_version'))();

  String get _latestVersion =>
      (widget.latestVersionOf ?? () => AppConfig.getString('latest_version'))();

  String? get _dismissedVersion =>
      (widget.dismissedVersionOf ?? () => HiveStore.dismissedUpdateVersion)();

  @override
  void initState() {
    super.initState();
    unawaited(_check());
    _revisionSub = (widget.revisions ?? AppConfig.revisions()).listen(
      (_) => unawaited(_check()),
    );
  }

  @override
  void dispose() {
    unawaited(_revisionSub?.cancel());
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final latest = _latestVersion;
      switch (resolveUpdateStatus(
        current: info.version,
        minSupported: _minVersion,
        latest: latest,
      )) {
        case UpdateStatus.blocked:
          availableUpdate.value = null;
          setState(() => _blockedAt = info.version);
        case UpdateStatus.available:
          // A dismissal only covers the exact version it was made against, so
          // a newer release re-arms the nudge on its own.
          availableUpdate.value = _dismissedVersion == latest ? null : latest;
        case UpdateStatus.upToDate:
          availableUpdate.value = null;
      }
    } on Object catch (_) {
      // Fail open: any failure reading the version leaves the app usable.
    }
  }

  @override
  Widget build(BuildContext context) => _blockedAt == null
      ? widget.child
      : _ForceUpdateScreen(currentVersion: _blockedAt!);
}

/// Blocking interstitial for an unsupported build.
///
/// Content sits in the upper third and the action is pinned to the bottom, so
/// the only thing to do is reachable one-handed. Left-aligned rather than
/// centred: the body copy runs to two lines in Chinese, and a centred ragged
/// block is harder to scan than a flush one.
class _ForceUpdateScreen extends StatelessWidget {
  const _ForceUpdateScreen({required this.currentVersion});

  final String currentVersion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minVersion = AppConfig.getString('min_supported_version');
    // Only render the direct-open button for a URL that passes the allowlist
    // (F44); anything else falls back to the "search the store" copy instead
    // of a button that silently no-ops on tap.
    final url = storeUrl();

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(flex: 2),
                Icon(
                  Icons.system_update_rounded,
                  size: 32,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(height: 24),
                Text(
                  AppI18n.of(context).updateRequiredTitle,
                  style: AppTextStyles.heading1,
                ),
                const SizedBox(height: 12),
                Text(
                  AppI18n.of(context).updateRequiredBody,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                // Versions are data, so they render in mono like every other
                // figure in the app.
                Text(
                  AppI18n.of(
                    context,
                  ).updateVersionLine(currentVersion, minVersion),
                  style: AppTextStyles.memo.copyWith(color: cs.outline),
                ),
                const Spacer(flex: 3),
                if (url != null)
                  FilledButton(
                    onPressed: () =>
                        launchUrl(url, mode: LaunchMode.externalApplication),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: Text(AppI18n.of(context).settingsUpdateGo),
                  )
                else
                  Text(
                    Platform.isIOS
                        ? AppI18n.of(context).updateStoreHintIos
                        : AppI18n.of(context).updateStoreHintAndroid,
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
