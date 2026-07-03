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
  const AlertStreamFailed(this.error);

  final AppError error;

  @override
  List<Object?> get props => [error];
}

class AlertStreamRecovered extends AlertEvent {
  const AlertStreamRecovered();
}
