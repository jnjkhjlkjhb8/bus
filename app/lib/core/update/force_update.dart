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

/// Gates the whole app: renders [child] normally, but swaps in a blocking
/// [_ForceUpdateScreen] when the running version is below
/// `min_supported_version`. The check runs once; while it's pending the child
/// shows (never a blank flash) since the common case is up-to-date.
class ForceUpdateGate extends StatefulWidget {
  const ForceUpdateGate({required this.child, super.key});

  final Widget child;

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate> {
  String? _current;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final min = AppConfig.getString('min_supported_version');
      if (mounted && isBelowMinVersion(info.version, min)) {
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

  Future<void> _openStore() async {
    final url = Uri.tryParse(_storeUrl);
    if (url == null) return;
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minVersion = AppConfig.getString('min_supported_version');
    final storeUrl = _storeUrl;

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
                if (storeUrl.isNotEmpty)
                  FilledButton(
                    onPressed: _openStore,
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
