/// The unified ETA display status every transit mode maps its live estimate
/// into. The shared arrival tile (shared/widgets/eta_list_tile.dart) renders it
/// through one `EtaValue`, so the mono-time and status-colour invariants have a
/// single owner. The status *labels/colours* are the tile's; the *rules* that
/// pick a status stay in eta_format.dart, applied by each mode's mapper.
sealed class EtaStatus {
  const EtaStatus();
  factory EtaStatus.arriving() = EtaArriving;
  factory EtaStatus.approaching() = EtaApproaching;
  factory EtaStatus.minutes(int m) = EtaMinutes;
  factory EtaStatus.label(String text) = EtaLabel;
  factory EtaStatus.unknown() = EtaUnknown;
}

final class EtaArriving extends EtaStatus {
  const EtaArriving();
}

final class EtaApproaching extends EtaStatus {
  const EtaApproaching();
}

final class EtaMinutes extends EtaStatus {
  const EtaMinutes(this.value);
  final int value;
}

/// A service-state label (e.g. 尚未發車, 末班已過, or a scheduled clock time)
/// carried verbatim from the one status-label mapping in eta_format.dart.
final class EtaLabel extends EtaStatus {
  const EtaLabel(this.text);
  final String text;
}

final class EtaUnknown extends EtaStatus {
  const EtaUnknown();
}
