import 'package:equatable/equatable.dart';

enum AlertSeverity { red, yellow, green }

class AlertViewModel extends Equatable {
  const AlertViewModel({
    required this.message,
    required this.level,
    required this.rawJson,
  });

  final String message;
  final AlertSeverity level;
  final Map<String, dynamic> rawJson;

  @override
  List<Object?> get props => [message, level];
}
