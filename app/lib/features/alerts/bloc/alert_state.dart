import 'package:equatable/equatable.dart';
import 'package:wheres_the_bus/core/errors/app_error.dart';
import 'package:wheres_the_bus/data/models/alert_models.dart';

class AlertState extends Equatable {
  const AlertState({
    this.alertsBySource = const {},
    this.scope = const {},
    this.dismissedMessages = const {},
    this.readMessages = const {},
    this.sourceHealth = const {},
  });

  /// What each subscribed source currently reports, unfiltered and keyed by
  /// source so a new snapshot replaces exactly its own rows. Filtering happens
  /// in the getters rather than on arrival, so changing 收藏 re-derives what is
  /// shown from data already in hand, with no resubscribe.
  final Map<AlertSourceId, List<AlertViewModel>> alertsBySource;

  /// Every reported alert across all sources, unfiltered.
  List<AlertViewModel> get activeAlerts => [
    for (final alerts in alertsBySource.values) ...alerts,
  ];

  /// The rider's 訂閱範圍 (see `subscription_scope.dart`). An alert scoped to a
  /// route outside it is not shown; an alert that names no route is
  /// system-wide and is shown regardless.
  final Set<String> scope;

  final Set<String> dismissedMessages;
  final Set<String> readMessages;

  /// Per-source subscription failures. A source with no entry is healthy;
  /// only currently-failed sources appear here. Keyed by `null` for a
  /// failure whose caller didn't attribute a source (F32) — the UI can read
  /// this map directly to show which systems are down, or use [error] for
  /// the existing "is anything down" signal.
  final Map<AlertSourceId?, AppError> sourceHealth;

  /// Some recorded failure, or null when every tracked source is healthy.
  /// Existing single-error consumers (OfflineBanner, the notification strip)
  /// only need to know "is at least one source down", not which — recovering
  /// one of several failed sources must not clear this until all recover
  /// (F32).
  AppError? get error =>
      sourceHealth.values.isEmpty ? null : sourceHealth.values.first;

  /// The notices allowed to interrupt: in-scope, undismissed service
  /// disruptions at critical tone. Reads tone rather than level so an
  /// announcement can never reach the interrupt layer by carrying a red
  /// level.
  List<AlertViewModel> get redAlerts =>
      visibleAlerts.where((a) => a.tone == NoticeTone.critical).toList();

  /// Inbox group 「進行中」: something is broken right now. A disruption the
  /// feed stops publishing has been resolved and leaves on its own.
  List<AlertViewModel> get ongoingNotices =>
      visibleAlerts.where((a) => a.ongoing).toList();

  /// Inbox group 「訊息」: route news and app announcements — things to read,
  /// never things happening.
  List<AlertViewModel> get messageNotices =>
      visibleAlerts.where((a) => !a.ongoing).toList();

  /// Announcements the resident rail should carry: an ops maintenance window
  /// for as long as it is enabled, and a general announcement until the rider
  /// has read it. Read state doubles as the rail's dismissal — closing the
  /// strip means "I've seen it", and the notice stays in the inbox.
  List<AlertViewModel> get railAnnouncements => activeAlerts
      .where(
        (a) =>
            a.kind == NoticeKind.announcement &&
            (!a.dismissible || !readMessages.contains(a.message)),
      )
      .toList();

  /// Alerts worth showing: in the rider's 訂閱範圍, not resolved, not
  /// dismissed.
  List<AlertViewModel> get visibleAlerts => activeAlerts
      .where(
        (a) =>
            a.level != AlertSeverity.green &&
            a.matchesScope(scope) &&
            !dismissedMessages.contains(a.message),
      )
      .toList();

  /// Candidates for a page's own inline notice: everything unresolved and
  /// undismissed, deliberately *not* filtered by 訂閱範圍. Standing on a
  /// route's page is stronger evidence of interest than having saved it, so a
  /// disruption on the route being read must not be hidden because the rider
  /// never favorited it. Callers narrow this by route identity themselves.
  List<AlertViewModel> get contextualNotices => activeAlerts
      .where(
        (a) =>
            a.level != AlertSeverity.green &&
            !dismissedMessages.contains(a.message),
      )
      .toList();

  /// Visible alerts the user has not yet read.
  List<AlertViewModel> get unreadAlerts =>
      visibleAlerts.where((a) => !readMessages.contains(a.message)).toList();

  int get unreadCount => unreadAlerts.length;

  AlertState copyWith({
    Map<AlertSourceId, List<AlertViewModel>>? alertsBySource,
    Set<String>? scope,
    Set<String>? dismissedMessages,
    Set<String>? readMessages,
    Map<AlertSourceId?, AppError>? sourceHealth,
  }) => AlertState(
    alertsBySource: alertsBySource ?? this.alertsBySource,
    scope: scope ?? this.scope,
    dismissedMessages: dismissedMessages ?? this.dismissedMessages,
    readMessages: readMessages ?? this.readMessages,
    sourceHealth: sourceHealth ?? this.sourceHealth,
  );

  @override
  List<Object?> get props => [
    alertsBySource,
    scope,
    dismissedMessages,
    readMessages,
    sourceHealth,
  ];
}
