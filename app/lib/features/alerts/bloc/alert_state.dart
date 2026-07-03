import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';

class AlertState extends Equatable {
  const AlertState({
    this.activeAlerts = const [],
    this.dismissedMessages = const {},
    this.readMessages = const {},
    this.error,
  });

  final List<AlertViewModel> activeAlerts;
  final Set<String> dismissedMessages;
  final Set<String> readMessages;
  final AppError? error;

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
    AppError? error,
    bool clearError = false,
  }) => AlertState(
    activeAlerts: activeAlerts ?? this.activeAlerts,
    dismissedMessages: dismissedMessages ?? this.dismissedMessages,
    readMessages: readMessages ?? this.readMessages,
    error: clearError ? null : error ?? this.error,
  );

  @override
  List<Object?> get props => [
    activeAlerts,
    dismissedMessages,
    readMessages,
    error,
  ];
}
