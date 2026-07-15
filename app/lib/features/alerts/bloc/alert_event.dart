import 'package:equatable/equatable.dart';
import 'package:wheres_the_car/core/errors/app_error.dart';
import 'package:wheres_the_car/data/models/alert_models.dart';

sealed class AlertEvent extends Equatable {
  const AlertEvent();
  @override
  List<Object?> get props => [];
}

class AlertStarted extends AlertEvent {
  const AlertStarted();
}

class AlertReceived extends AlertEvent {
  const AlertReceived(this.alert);
  final AlertViewModel alert;
  @override
  List<Object?> get props => [alert];
}

class AlertDismissed extends AlertEvent {
  const AlertDismissed(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

class AlertAllDismissed extends AlertEvent {
  const AlertAllDismissed(this.messages);
  final List<String> messages;
  @override
  List<Object?> get props => [messages];
}

class AlertRestored extends AlertEvent {
  const AlertRestored(this.messages);
  final List<String> messages;
  @override
  List<Object?> get props => [messages];
}

class AlertAllRead extends AlertEvent {
  const AlertAllRead();
}

class AlertMarkedRead extends AlertEvent {
  const AlertMarkedRead(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

class AlertStreamFailed extends AlertEvent {
  const AlertStreamFailed(this.error, {this.source});

  final AppError error;

  /// Which subscription failed, if the caller knows. `null` is a legacy/
  /// unscoped failure — it is tracked in the health map under a `null` key,
  /// same as any other source (F32).
  final AlertSourceId? source;

  @override
  List<Object?> get props => [error, source];
}

class AlertStreamRecovered extends AlertEvent {
  const AlertStreamRecovered({this.source});

  /// Which subscription recovered; must match the `source` an earlier
  /// [AlertStreamFailed] used for this to clear that failure (F32).
  final AlertSourceId? source;

  @override
  List<Object?> get props => [source];
}

/// Fired whenever the injected `alert_sources` config stream emits a new
/// (or first) value. Carries the raw CSV so the bloc can diff it against
/// what it last applied and resubscribe only the affected sources (F33).
class AlertConfigChanged extends AlertEvent {
  const AlertConfigChanged(this.sourcesCsv);

  final String sourcesCsv;

  @override
  List<Object?> get props => [sourcesCsv];
}
