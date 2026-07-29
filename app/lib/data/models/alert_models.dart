import 'package:equatable/equatable.dart';

enum AlertSeverity { red, yellow, green }

/// Which transit domain an alert came from. The subscription layer knows this;
/// carrying it to the UI lets a row show which system is affected at a glance.
/// Bus splits into two kinds because TDX publishes advisories and disruptions
/// on separate topics, and each is its own live stream. The two `app` kinds are
/// not streams at all — they are ops-authored notices read from Remote Config,
/// carried through the same pipeline so read/dismiss/badge behave identically.
enum AlertSourceKind {
  metro,
  busNews,
  busAlert,
  tra,
  thsr,
  appMaintenance,
  appNotice,
}

/// What a notice *is*, independent of how loud it is. Derived from the source
/// rather than stored, so a row can never disagree with the stream it came
/// from.
enum NoticeKind {
  /// Something is broken or degraded right now.
  disruption,

  /// Route changes, timetable revisions — informational, never urgent.
  news,

  /// Ops-authored: maintenance windows and app announcements.
  announcement,
}

/// How loud a notice is allowed to be. The one input to notice coloring;
/// see `app/theme/notice_tone.dart` for the resolved colors.
enum NoticeTone { critical, caution, info, neutral }

/// Origin of an alert: the domain plus the operator/region code the stream was
/// opened with (e.g. metro `TRTC`, bus `Taipei`). Rail kinds carry an empty
/// code since their streams are nationwide.
class AlertSource extends Equatable {
  const AlertSource(this.kind, [this.code = '']);

  final AlertSourceKind kind;
  final String code;

  @override
  List<Object?> get props => [kind, code];
}

/// Alias for [AlertSource] used where the value identifies which live
/// subscription a health/failure record belongs to, rather than where a
/// received message came from. Same type, different reading — kept as an
/// alias instead of a parallel class so subscription bookkeeping and message
/// provenance never drift apart.
typedef AlertSourceId = AlertSource;

class AlertViewModel extends Equatable {
  const AlertViewModel({
    required this.message,
    required this.level,
    this.routeType = '',
    this.routeKeys = const [],
    this.title,
    this.time,
    this.source,
  });

  /// The alert text, and the row's identity: it is the dedupe, read, and
  /// dismiss key. Ingest assigns each alert an id that is this text's hash, so
  /// the two layers agree on what "the same alert" means without the app
  /// having to carry both.
  final String message;
  final AlertSeverity level;

  /// Transit type this alert belongs to (`bus`, `mrt`, `tra`, `thsr`).
  final String routeType;

  /// Route identities the alert is scoped to. Empty means it names no route
  /// and applies system-wide.
  final List<String> routeKeys;

  /// Optional headline distinct from [message]; may be null.
  final String? title;

  /// When the alert was published/updated, if the feed provided it.
  final DateTime? time;

  /// Which system and operator the alert came from, if known.
  final AlertSource? source;

  /// What this notice is. Derived from [source] so it can never disagree with
  /// the stream the row came from.
  NoticeKind get kind => switch (source?.kind) {
    AlertSourceKind.busNews => NoticeKind.news,
    AlertSourceKind.appMaintenance ||
    AlertSourceKind.appNotice => NoticeKind.announcement,
    _ => NoticeKind.disruption,
  };

  /// How loud this notice may be. Severity only decides tone for disruptions:
  /// news and announcements are never critical no matter what level the feed
  /// puts on them.
  NoticeTone get tone => switch (kind) {
    NoticeKind.news => NoticeTone.info,
    NoticeKind.announcement =>
      source?.kind == AlertSourceKind.appMaintenance
          ? NoticeTone.caution
          : NoticeTone.info,
    NoticeKind.disruption =>
      level == AlertSeverity.red ? NoticeTone.critical : NoticeTone.caution,
  };

  /// Whether this is something happening now (the 進行中 group) rather than
  /// something to read (the 訊息 group). Resolved disruptions stop being
  /// published, so they leave the group on their own.
  bool get ongoing => kind == NoticeKind.disruption;

  /// Whether the rider may clear this notice. A maintenance window is ops-
  /// controlled: it goes away when ops turn it off, not when a rider swipes.
  bool get dismissible => source?.kind != AlertSourceKind.appMaintenance;

  /// Whether this alert is worth showing to a rider whose 訂閱範圍 is [scope]
  /// (see `subscription_scope.dart` for the entry format). An alert that names
  /// no route is system-wide and always shows: 「台鐵今日全線停駛」is not about
  /// which routes you saved.
  bool matchesScope(Set<String> scope) =>
      routeKeys.isEmpty ||
      routeKeys.any((key) => scope.contains('$routeType:$key'));

  // [message] stays the sole identity, so enriching a row with
  // title/time/source/scope must not change equality.
  @override
  List<Object?> get props => [message];
}
