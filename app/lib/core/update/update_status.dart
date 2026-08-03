import 'dart:io' show Platform;

import 'package:wheres_the_bus/core/firebase/remote_config.dart';

/// What the installed build's standing is against the published ones.
enum UpdateStatus {
  /// Nothing newer has been published (or the remote values are unusable).
  upToDate,

  /// A newer build exists. Optional: the rider is nudged, never stopped.
  available,

  /// Below `min_supported_version`. The app refuses to run.
  blocked,
}

/// Resolves the update posture for the running build.
///
/// [UpdateStatus.blocked] wins over [UpdateStatus.available]: a build below
/// the floor is also below the latest, and the rider must not be offered a
/// dismissible nudge for a condition that is actually fatal.
///
/// Every comparison fails OPEN (see [isBelowVersion]), so a malformed remote
/// value degrades to [UpdateStatus.upToDate] rather than locking or nagging.
UpdateStatus resolveUpdateStatus({
  required String current,
  required String minSupported,
  required String latest,
}) {
  if (isBelowVersion(current, minSupported)) return UpdateStatus.blocked;
  if (isBelowVersion(current, latest)) return UpdateStatus.available;
  return UpdateStatus.upToDate;
}

/// True when [current] is strictly below [other] (both dotted numeric, e.g.
/// "1.2.3"). Build metadata / pre-release suffixes are dropped.
///
/// Fails OPEN: any unparseable segment returns false, so a malformed remote
/// version can never lock users out of the app nor nag them forever.
bool isBelowVersion(String current, String other) {
  final a = _segments(current);
  final b = _segments(other);
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

/// This platform's store link, or null when the configured value is missing
/// or fails [isAllowedStoreUrl].
///
/// Null is the signal every caller acts on: render the "search the store"
/// copy instead of a button that no-ops on tap. [isIOS] is injectable so the
/// choice can be tested on a host that is neither platform.
Uri? storeUrl({bool? isIOS}) {
  final raw = (isIOS ?? Platform.isIOS)
      ? AppConfig.getString('store_url_ios')
      : AppConfig.getString('store_url_android');
  final parsed = Uri.tryParse(raw);
  return parsed != null && isAllowedStoreUrl(parsed) ? parsed : null;
}
