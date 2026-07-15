import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wheres_the_car/app/theme/app_text_styles.dart';
import 'package:wheres_the_car/core/firebase/remote_config.dart';

/// True when [current] app version is strictly below [min] (both dotted
/// numeric, e.g. "1.2.3"). Build metadata / pre-release suffixes are dropped.
///
/// Fails OPEN: any unparseable segment returns false so a malformed remote
/// `min_supported_version` can never lock users out of the app.
bool isBelowMinVersion(String current, String min) {
  final a = _segments(current);
  final b = _segments(min);
  if (a == null || b == null) return false;
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x < y;
  }
  return false;
}

List<int>? _segments(String v) {
  final core = v.split(RegExp('[+-]')).first.trim();
  final out = <int>[];
  for (final part in core.split('.')) {
    final n = int.tryParse(part);
    if (n == null) return null;
    out.add(n);
  }
  return out.isEmpty ? null : out;
}

/// Store hosts a `store_url_ios`/`store_url_android` Remote Config value is
/// allowed to point at.
const _allowedStoreHosts = {'apps.apple.com', 'play.google.com'};

/// True when [url] is safe to open as a store link: https and an official
/// Apple/Google store host (F44). Remote Config is server-controlled but not
/// a trusted boundary for arbitrary URL schemes — a compromised or
/// misconfigured console value must never reach `launchUrl` with e.g. an
/// `intent:` or `javascript:` scheme.
bool isAllowedStoreUrl(Uri url) =>
    url.scheme == 'https' && _allowedStoreHosts.contains(url.host);

/// Gates the whole app: renders [child] normally, but swaps in a blocking
/// [_ForceUpdateScreen] when the running version is below
/// `min_supported_version`. The check runs on mount and again on every
/// activated Remote Config revision (F16), so a bar raised after launch is
/// enforced without a relaunch. While a check is pending the child shows
/// (never a blank flash) since the common case is up-to-date.
class ForceUpdateGate extends StatefulWidget {
  const ForceUpdateGate({
    required this.child,
    super.key,
    this.revisions,
    this.minVersionOf,
  });

  final Widget child;

  /// Injectable for tests; defaults to [AppConfig.revisions()].
  final Stream<void>? revisions;

  /// Injectable for tests; defaults to reading `min_supported_version` from
  /// [AppConfig].
  final String Function()? minVersionOf;

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate> {
  String? _current;
  StreamSubscription<void>? _revisionSub;

  String get _minVersion =>
      (widget.minVersionOf ??
      () => AppConfig.getString('min_supported_version'))();

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
      if (mounted && isBelowMinVersion(info.version, _minVersion)) {
        setState(() => _current = info.version);
      }
    } on Object catch (_) {
      // Fail open: any failure reading the version leaves the app usable.
    }
  }

  @override
  Widget build(BuildContext context) => _current == null
      ? widget.child
      : _ForceUpdateScreen(currentVersion: _current!);
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

  String get _storeUrl => Platform.isIOS
      ? AppConfig.getString('store_url_ios')
      : AppConfig.getString('store_url_android');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minVersion = AppConfig.getString('min_supported_version');
    final storeUrl = _storeUrl;
    final parsedStoreUrl = Uri.tryParse(storeUrl);
    // Only render the direct-open button for a URL that passes the
    // allowlist (F44); anything else falls back to the "search the store"
    // copy instead of a button that silently no-ops on tap.
    final allowedStoreUrl =
        parsedStoreUrl != null && isAllowedStoreUrl(parsedStoreUrl)
        ? parsedStoreUrl
        : null;

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
                const Text('請更新至最新版本', style: AppTextStyles.heading1),
                const SizedBox(height: 12),
                Text(
                  '這個版本已不再支援。更新後就能繼續查詢即時到站。',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                // Versions are data, so they render in mono like every other
                // figure in the app.
                Text(
                  '目前 $currentVersion · 需要 $minVersion',
                  style: AppTextStyles.memo.copyWith(color: cs.outline),
                ),
                const Spacer(flex: 3),
                if (allowedStoreUrl case final url?)
                  FilledButton(
                    onPressed: () =>
                        launchUrl(url, mode: LaunchMode.externalApplication),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text('前往更新'),
                  )
                else
                  Text(
                    Platform.isIOS
                        ? '請至 App Store 搜尋「我車呢」並更新。'
                        : '請至 Google Play 搜尋「我車呢」並更新。',
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
