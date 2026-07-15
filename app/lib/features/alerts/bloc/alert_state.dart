import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';

class AlertState extends Equatable {
  const AlertState({
    this.activeAlerts = const [],
    this.dismissedMessages = const {},
    this.readMessages = const {},
    this.sourceHealth = const {},
  });

  final List<AlertViewModel> activeAlerts;
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

  /// Only red (severe) alerts that haven't been dismissed.
  List<AlertViewModel> get redAlerts => activeAlerts
      .where(
        (a) =>
            a.level == AlertSeverity.red &&
            !dismissedMessages.contains(a.message),
      )
      .toList();

  /// Yellow or red alerts that haven't been dismissed.
  List<AlertViewModel> get visibleAlerts => activeAlerts
      .where((a) => !dismissedMessages.contains(a.message))
      .toList();

  /// Visible alerts the user has not yet read.
  List<AlertViewModel> get unreadAlerts =>
      visibleAlerts.where((a) => !readMessages.contains(a.message)).toList();

  int get unreadCount => unreadAlerts.length;

  AlertState copyWith({
    List<AlertViewModel>? activeAlerts,
    Set<String>? dismissedMessages,
    Set<String>? readMessages,
    Map<AlertSourceId?, AppError>? sourceHealth,
  }) => AlertState(
    activeAlerts: activeAlerts ?? this.activeAlerts,
    dismissedMessages: dismissedMessages ?? this.dismissedMessages,
    readMessages: readMessages ?? this.readMessages,
    sourceHealth: sourceHealth ?? this.sourceHealth,
  );

  @override
  List<Object?> get props => [
    activeAlerts,
    dismissedMessages,
    readMessages,
    sourceHealth,
  ];
}
